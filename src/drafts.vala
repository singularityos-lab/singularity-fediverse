namespace Singularity.Apps.Fediverse {

    public class Draft : Object {
        public string id = "";
        public string account = "";
        public string text = "";
        public string spoiler_text = "";
        public Visibility visibility = Visibility.PUBLIC;
        public bool sensitive;
        public string reply_to_id = "";
        public string reply_to_handle = "";
        public string reply_snippet = "";
        public string replaces_scheduled = "";
        public int64 updated;

        public Draft () {
            id = Uuid.string_random ();
        }

        public bool is_empty () {
            return text.strip () == "" && spoiler_text.strip () == "";
        }

        public string preview () {
            string t = spoiler_text.strip () != "" ? spoiler_text.strip () : text.strip ();
            t = t.replace ("\n", " ");
            if (t.char_count () > 160) t = t.substring (0, t.index_of_nth_char (160)) + "…";
            return t;
        }

        public Json.Node to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("id").add_string_value (id);
            b.set_member_name ("account").add_string_value (account);
            b.set_member_name ("text").add_string_value (text);
            b.set_member_name ("spoiler_text").add_string_value (spoiler_text);
            b.set_member_name ("visibility").add_string_value (visibility.to_api ());
            b.set_member_name ("sensitive").add_boolean_value (sensitive);
            if (reply_to_id != "") {
                b.set_member_name ("reply_to_id").add_string_value (reply_to_id);
                b.set_member_name ("reply_to_handle").add_string_value (reply_to_handle);
                b.set_member_name ("reply_snippet").add_string_value (reply_snippet);
            }
            if (replaces_scheduled != "") b.set_member_name ("replaces_scheduled").add_string_value (replaces_scheduled);
            b.set_member_name ("updated").add_int_value (updated);
            b.end_object ();
            return b.get_root ();
        }

        public static Draft? from_json (Json.Object o) {
            var d = new Draft ();
            d.id = J.str (o, "id");
            d.account = J.str (o, "account");
            d.text = J.str (o, "text");
            d.spoiler_text = J.str (o, "spoiler_text");
            d.visibility = Visibility.parse (J.str (o, "visibility"));
            d.sensitive = J.flag (o, "sensitive");
            d.reply_to_id = J.str (o, "reply_to_id");
            d.reply_to_handle = J.str (o, "reply_to_handle");
            d.reply_snippet = J.str (o, "reply_snippet");
            d.replaces_scheduled = J.str (o, "replaces_scheduled");
            d.updated = J.num (o, "updated");
            if (d.id == "" || d.account == "") return null;
            return d;
        }
    }

    public class DraftStore : Object {
        public Gee.ArrayList<Draft> items = new Gee.ArrayList<Draft> ();
        private string path;

        public signal void changed ();

        public DraftStore (string? file = null) {
            path = file ?? Path.build_filename (Environment.get_user_data_dir (), "singularity", "fediverse", "drafts.json");
            load ();
        }

        private void load () {
            items.clear ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            try {
                var p = new Json.Parser ();
                p.load_from_file (path);
                var root = p.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return;
                foreach (var n in root.get_array ().get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    var d = Draft.from_json (n.get_object ());
                    if (d != null && find (d.id) == null) items.add (d);
                }
            } catch (Error e) {
                warning ("fediverse: %s", e.message);
            }
        }

        public bool save () {
            var b = new Json.Builder ();
            b.begin_array ();
            foreach (var d in items) b.add_value (d.to_json ());
            b.end_array ();
            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.set_root (b.get_root ());
            try {
                DirUtils.create_with_parents (Path.get_dirname (path), 0700);
                FileUtils.set_contents_full (path, gen.to_data (null), -1, FileSetContentsFlags.CONSISTENT, 0600);
            } catch (Error e) {
                warning ("fediverse: %s", e.message);
                return false;
            }
            changed ();
            return true;
        }

        public Draft? find (string id) {
            foreach (var d in items) if (d.id == id) return d;
            return null;
        }

        public void put (Draft d, int64 now) {
            d.updated = now;
            if (d.is_empty ()) {
                remove (d.id);
                return;
            }
            if (!items.contains (d)) {
                var old = find (d.id);
                if (old != null) items.remove (old);
                items.add (d);
            }
            save ();
        }

        public void remove (string id) {
            var d = find (id);
            if (d == null) return;
            items.remove (d);
            save ();
        }

        public Gee.List<Draft> for_account (string key) {
            var list = new Gee.ArrayList<Draft> ();
            foreach (var d in items) if (d.account == key) list.add (d);
            list.sort ((a, b) => a.updated > b.updated ? -1 : (a.updated < b.updated ? 1 : 0));
            return list;
        }

        public int count (string key) {
            int n = 0;
            foreach (var d in items) if (d.account == key) n++;
            return n;
        }
    }
}
