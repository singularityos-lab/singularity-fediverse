namespace Singularity.Apps.Fediverse {

    public class SavedAccount : Object {
        public string instance = "";
        public string id = "";
        public string username = "";
        public string acct = "";
        public string display_name = "";
        public string avatar = "";
        public string client_id = "";
        public string client_secret = "";

        public string key () {
            return "%s@%s".printf (username, Oauth.host_of (instance) ?? instance);
        }

        public string handle () {
            return "@" + key ();
        }

        public string name () {
            return display_name.strip () != "" ? display_name : username;
        }

        public void update_from (Account a) {
            id = a.id;
            username = a.username;
            acct = a.acct;
            display_name = a.display_name;
            avatar = a.avatar;
        }

        public Json.Node to_json () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("instance").add_string_value (instance);
            b.set_member_name ("id").add_string_value (id);
            b.set_member_name ("username").add_string_value (username);
            b.set_member_name ("acct").add_string_value (acct);
            b.set_member_name ("display_name").add_string_value (display_name);
            b.set_member_name ("avatar").add_string_value (avatar);
            b.set_member_name ("client_id").add_string_value (client_id);
            b.set_member_name ("client_secret").add_string_value (client_secret);
            b.end_object ();
            return b.get_root ();
        }

        public static SavedAccount? from_json (Json.Object o) {
            var a = new SavedAccount ();
            a.instance = J.str (o, "instance");
            a.id = J.str (o, "id");
            a.username = J.str (o, "username");
            a.acct = J.str (o, "acct", a.username);
            a.display_name = J.str (o, "display_name");
            a.avatar = J.str (o, "avatar");
            a.client_id = J.str (o, "client_id");
            a.client_secret = J.str (o, "client_secret");
            if (a.instance == "" || a.username == "") return null;
            return a;
        }
    }

    public class RegisteredClient : Object {
        public string instance = "";
        public string client_id = "";
        public string client_secret = "";
        public bool oob = true;
    }

    public class AccountStore : Object {
        public Gee.ArrayList<SavedAccount> items = new Gee.ArrayList<SavedAccount> ();
        public Gee.HashMap<string, RegisteredClient> clients = new Gee.HashMap<string, RegisteredClient> ();
        public string current = "";
        public string pending_instance = "";
        public string pending_state = "";
        private string path;

        public signal void changed ();

        private static Secret.Schema schema () {
            return new Secret.Schema ("dev.sinty.fediverse", Secret.SchemaFlags.NONE, "account", Secret.SchemaAttributeType.STRING);
        }

        public AccountStore (string? file = null) {
            path = file ?? Path.build_filename (Environment.get_user_config_dir (), "singularity", "fediverse.json");
            load ();
        }

        private void load () {
            items.clear ();
            clients.clear ();
            if (!FileUtils.test (path, FileTest.EXISTS)) return;
            try {
                var p = new Json.Parser ();
                p.load_from_file (path);
                var root = p.get_root ();
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return;
                var o = root.get_object ();
                current = J.str (o, "current");
                pending_instance = J.str (o, "pending_instance");
                pending_state = J.str (o, "pending_state");
                var accs = J.arr (o, "accounts");
                if (accs != null) {
                    foreach (var n in accs.get_elements ()) {
                        if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                        var a = SavedAccount.from_json (n.get_object ());
                        if (a != null && find (a.key ()) == null) items.add (a);
                    }
                }
                var cl = J.arr (o, "clients");
                if (cl != null) {
                    foreach (var n in cl.get_elements ()) {
                        if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                        var co = n.get_object ();
                        var c = new RegisteredClient ();
                        c.instance = J.str (co, "instance");
                        c.client_id = J.str (co, "client_id");
                        c.client_secret = J.str (co, "client_secret");
                        c.oob = J.flag (co, "oob", true);
                        if (c.instance != "" && c.client_id != "") clients[c.instance] = c;
                    }
                }
            } catch (Error e) {
                debug ("fediverse: %s", e.message);
            }
        }

        public void save () {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("current").add_string_value (current);
            if (pending_state != "") {
                b.set_member_name ("pending_instance").add_string_value (pending_instance);
                b.set_member_name ("pending_state").add_string_value (pending_state);
            }
            b.set_member_name ("accounts");
            b.begin_array ();
            foreach (var a in items) b.add_value (a.to_json ());
            b.end_array ();
            b.set_member_name ("clients");
            b.begin_array ();
            foreach (var c in clients.values) {
                b.begin_object ();
                b.set_member_name ("instance").add_string_value (c.instance);
                b.set_member_name ("client_id").add_string_value (c.client_id);
                b.set_member_name ("client_secret").add_string_value (c.client_secret);
                b.set_member_name ("oob").add_boolean_value (c.oob);
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.set_root (b.get_root ());
            try {
                DirUtils.create_with_parents (Path.get_dirname (path), 0700);
                FileUtils.set_contents (path, gen.to_data (null));
                FileUtils.chmod (path, 0600);
            } catch (Error e) {
                warning ("fediverse: %s", e.message);
            }
            changed ();
        }

        public SavedAccount? find (string key) {
            foreach (var a in items) if (a.key () == key) return a;
            return null;
        }

        public SavedAccount? active () {
            var a = find (current);
            if (a == null && items.size > 0) a = items[0];
            return a;
        }

        public void put (SavedAccount a) {
            for (int i = 0; i < items.size; i++) {
                if (items[i].key () == a.key ()) {
                    items[i] = a;
                    save ();
                    return;
                }
            }
            items.add (a);
            save ();
        }

        public void remove (SavedAccount a) {
            for (int i = 0; i < items.size; i++) {
                if (items[i].key () == a.key ()) {
                    items.remove_at (i);
                    break;
                }
            }
            if (current == a.key ()) current = items.size > 0 ? items[0].key () : "";
            forget_token.begin (a.key ());
            save ();
        }

        public static async string? lookup_token (string key) {
            try {
                return yield Secret.password_lookup (schema (), null, "account", key);
            } catch (Error e) {
                return null;
            }
        }

        public static async void store_token (SavedAccount a, string token) throws Error {
            yield Secret.password_store (schema (), Secret.COLLECTION_DEFAULT, _("Fediverse access token for %s").printf (a.handle ()), token, null, "account", a.key ());
        }

        public static async void forget_token (string key) {
            try {
                yield Secret.password_clear (schema (), null, "account", key);
            } catch (Error e) {
            }
        }
    }
}
