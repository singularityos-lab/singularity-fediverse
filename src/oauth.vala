namespace Singularity.Apps.Fediverse {

    public class Params : Object {
        private Gee.ArrayList<string> keys = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> values = new Gee.ArrayList<string> ();

        public Params add (string key, string value) {
            keys.add (key);
            values.add (value);
            return this;
        }

        public int size {
            get { return keys.size; }
        }

        public string? lookup (string key) {
            for (int i = 0; i < keys.size; i++) if (keys[i] == key) return values[i];
            return null;
        }

        public string encode () {
            var sb = new StringBuilder ();
            for (int i = 0; i < keys.size; i++) {
                if (i > 0) sb.append_c ('&');
                sb.append (Uri.escape_string (keys[i], "[]", false));
                sb.append_c ('=');
                sb.append (Uri.escape_string (values[i], null, false));
            }
            return sb.str;
        }

        public static Params decode (string query) {
            var p = new Params ();
            foreach (string pair in query.split ("&")) {
                if (pair == "") continue;
                int eq = pair.index_of_char ('=');
                string k = eq < 0 ? pair : pair.substring (0, eq);
                string v = eq < 0 ? "" : pair.substring (eq + 1);
                k = Uri.unescape_string (k.replace ("+", " ")) ?? k;
                v = Uri.unescape_string (v.replace ("+", " ")) ?? v;
                p.add (k, v);
            }
            return p;
        }
    }

    namespace Oauth {
        public const string SCHEME = "sinty-fediverse";
        public const string REDIRECT = "sinty-fediverse://oauth";
        public const string OOB = "urn:ietf:wg:oauth:2.0:oob";
        public const string SCOPES = "read write";
        public const string CLIENT_NAME = "Singularity Fediverse";
        public const string WEBSITE = "https://github.com/singularityos-lab/singularity-fediverse";

        public string? host_of (string url) {
            try {
                var u = Uri.parse (url, UriFlags.NONE);
                string? h = u.get_host ();
                if (h == null || h == "") return null;
                return h.down ();
            } catch (Error e) {
                return null;
            }
        }

        public string? normalize_instance (string input) {
            string s = input.strip ();
            if (s == "") return null;
            if (s.has_prefix ("@") && s.index_of_char ('@', 1) > 0) s = s.substring (s.index_of_char ('@', 1) + 1);
            else if (!s.contains ("://") && s.index_of_char ('@') > 0) s = s.substring (s.index_of_char ('@') + 1);
            string lower = s.down ();
            if (lower.has_prefix ("http://")) return null;
            if (lower.has_prefix ("https://")) s = s.substring (8);
            if (s.contains ("://")) return null;
            int slash = s.index_of_char ('/');
            if (slash >= 0) s = s.substring (0, slash);
            s = s.down ();
            if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
            if (s == "" || !s.contains (".") && !s.has_prefix ("localhost")) return null;
            for (int i = 0; i < s.length; i++) {
                char c = s[i];
                if (!(c.isalnum () || c == '.' || c == '-' || c == ':' || c == '[' || c == ']')) return null;
            }
            if (s.has_prefix (".") || s.has_prefix ("-") || s.contains ("..")) return null;
            return "https://" + s;
        }

        public string new_state () {
            var sb = new StringBuilder ();
            for (int i = 0; i < 4; i++) sb.append ("%08x".printf (Random.next_int ()));
            return sb.str;
        }

        public string redirect_uris () {
            return REDIRECT + "\n" + OOB;
        }

        public Params registration_params (bool with_oob = true) {
            return new Params ()
                .add ("client_name", CLIENT_NAME)
                .add ("redirect_uris", with_oob ? redirect_uris () : REDIRECT)
                .add ("scopes", SCOPES)
                .add ("website", WEBSITE);
        }

        public string authorize_url (string instance, string client_id, string redirect_uri, string state) {
            var p = new Params ()
                .add ("response_type", "code")
                .add ("client_id", client_id)
                .add ("redirect_uri", redirect_uri)
                .add ("scope", SCOPES);
            if (redirect_uri != OOB) p.add ("state", state);
            return instance + "/oauth/authorize?" + p.encode ();
        }

        public Params token_params (string client_id, string client_secret, string redirect_uri, string code) {
            return new Params ()
                .add ("grant_type", "authorization_code")
                .add ("code", code)
                .add ("client_id", client_id)
                .add ("client_secret", client_secret)
                .add ("redirect_uri", redirect_uri)
                .add ("scope", SCOPES);
        }

        public bool parse_redirect (string uri, out string code, out string state, out string error) {
            code = "";
            state = "";
            error = "";
            if (!uri.down ().has_prefix (SCHEME + ":")) return false;
            int q = uri.index_of_char ('?');
            if (q < 0) return false;
            string query = uri.substring (q + 1);
            int hash = query.index_of_char ('#');
            if (hash >= 0) query = query.substring (0, hash);
            var p = Params.decode (query);
            code = p.lookup ("code") ?? "";
            state = p.lookup ("state") ?? "";
            error = p.lookup ("error_description") ?? p.lookup ("error") ?? "";
            return code != "" || error != "";
        }

        public string streaming_url (string instance, string streaming_base, string stream, string? tag = null) {
            string b = streaming_base.strip ();
            if (b == "") b = instance;
            if (b.has_prefix ("https://")) b = "wss://" + b.substring (8);
            else if (b.has_prefix ("http://")) b = "ws://" + b.substring (7);
            if (b.has_suffix ("/")) b = b.substring (0, b.length - 1);
            var p = new Params ().add ("stream", stream);
            if (tag != null) p.add ("tag", tag);
            return b + "/api/v1/streaming?" + p.encode ();
        }
    }
}
