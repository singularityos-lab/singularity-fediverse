namespace Singularity.Apps.Fediverse {

    private class CachedMention {
        public Json.Node node;
        public int64 time;

        public CachedMention (Json.Node node, int64 time) {
            this.node = node;
            this.time = time;
        }
    }

    public class UnreadChecker : Object {
        public const string APP_URI = "application://dev.sinty.fediverse.desktop";
        private const int CACHED = 20;

        private AccountStore store;
        private bool running;
        private bool again;

        public int count { get; private set; }

        public UnreadChecker (AccountStore store) {
            this.store = store;
        }

        public static string cache_path () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-fediverse", "mentions.json");
        }

        public static bool newer (string a, string b) {
            if (b == "") return a != "";
            if (a.length != b.length) return a.length > b.length;
            return strcmp (a, b) > 0;
        }

        private static async string marker (Client client) {
            try {
                var root = yield client.call ("GET", "/api/v1/markers", new Params ().add ("timeline[]", "notifications"));
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return "";
                return J.str (J.obj (root.get_object (), "notifications"), "last_read_id");
            } catch (Error e) {
                return "";
            }
        }

        public async void check () {
            if (running) {
                again = true;
                return;
            }
            running = true;
            do {
                again = false;
                yield run ();
            } while (again);
            running = false;
        }

        private async void run () {
            int total = 0;
            var entries = new Gee.ArrayList<CachedMention> ();
            foreach (var a in store.items) {
                string? token = yield AccountStore.lookup_token (a.key ());
                if (token == null || token == "") continue;
                var client = new Client (a.instance, token);
                string last_read = yield marker (client);
                Json.Node? root = null;
                try {
                    root = yield client.call ("GET", "/api/v1/notifications", new Params ().add ("types[]", "mention").add ("limit", "40"));
                } catch (Error e) {
                    debug ("fediverse: unread check failed for an account: %s", e.message);
                    continue;
                }
                int kept = 0;
                foreach (var n in Notice.parse_list (root)) {
                    if (n.status == null) continue;
                    bool unread = last_read != "" && newer (n.id, last_read);
                    if (unread) total++;
                    if (kept >= CACHED) continue;
                    kept++;
                    var s = n.status.shown ();
                    string text = s.spoiler_text.strip () != "" ? s.spoiler_text.strip () : s.body ().plain ().strip ();
                    if (text.char_count () > 280) text = text.substring (0, text.index_of_nth_char (280)) + "…";
                    string? avatar = n.account.avatar != "" ? yield ImageCache.fetch (n.account.avatar) : null;
                    int64 when = n.created_at != null ? n.created_at.to_unix () : 0;
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("account").add_string_value (a.key ());
                    b.set_member_name ("id").add_string_value (s.id);
                    b.set_member_name ("author").add_string_value (n.account.name ());
                    b.set_member_name ("handle").add_string_value (n.account.handle (Oauth.host_of (a.instance) ?? ""));
                    b.set_member_name ("avatar").add_string_value (avatar ?? "");
                    b.set_member_name ("text").add_string_value (text);
                    b.set_member_name ("time").add_int_value (when);
                    b.set_member_name ("direct").add_boolean_value (s.visibility == Visibility.DIRECT);
                    b.set_member_name ("unread").add_boolean_value (unread);
                    b.end_object ();
                    entries.add (new CachedMention (b.get_root (), when));
                }
            }
            entries.sort ((x, y) => x.time > y.time ? -1 : (x.time < y.time ? 1 : 0));
            write_cache (entries);
            count = total;
            publish ();
        }

        private static void write_cache (Gee.List<CachedMention> entries) {
            var arr = new Json.Array ();
            foreach (var e in entries) arr.add_element (e.node);
            var root = new Json.Node (Json.NodeType.ARRAY);
            root.set_array (arr);
            var gen = new Json.Generator ();
            gen.set_root (root);
            string path = cache_path ();
            try {
                DirUtils.create_with_parents (Path.get_dirname (path), 0700);
                FileUtils.set_contents_full (path, gen.to_data (null), -1, FileSetContentsFlags.CONSISTENT, 0600);
            } catch (Error e) {
                warning ("fediverse: %s", e.message);
            }
        }

        public void publish () {
            var conn = GLib.Application.get_default ()?.get_dbus_connection ();
            if (conn == null) return;
            var props = new VariantBuilder (VariantType.VARDICT);
            props.add ("{sv}", "count", new Variant.int64 (count));
            props.add ("{sv}", "count-visible", new Variant.boolean (count > 0));
            try {
                conn.emit_signal (null, "/dev/sinty/fediverse", "com.canonical.Unity.LauncherEntry", "Update",
                    new Variant ("(s@a{sv})", APP_URI, props.end ()));
            } catch (Error e) {
                warning ("fediverse: %s", e.message);
            }
        }

        public async void mark_read (Session s) {
            try {
                var root = yield s.client.call ("GET", "/api/v1/notifications", new Params ().add ("limit", "1"));
                var list = Notice.parse_list (root);
                if (list.size == 0) return;
                string current = yield marker (s.client);
                if (!newer (list[0].id, current)) return;
                yield s.client.call ("POST", "/api/v1/markers", new Params ().add ("notifications[last_read_id]", list[0].id));
            } catch (Error e) {
                debug ("fediverse: could not set the notifications marker: %s", e.message);
                return;
            }
            yield check ();
        }
    }
}
