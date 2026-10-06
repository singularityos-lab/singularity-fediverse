namespace Singularity.Apps.Fediverse {

    public errordomain ApiError {
        HTTP,
        UNAUTHORIZED,
        NOT_FOUND,
        PARSE,
        INVALID
    }

    public class Client : Object {
        public string instance { get; construct; }
        public string token { get; set; default = ""; }

        private static Soup.Session? _session;

        public Client (string instance, string token = "") {
            Object (instance: instance, token: token);
        }

        public static Soup.Session session () {
            if (_session == null) {
                _session = (Soup.Session) Object.new (typeof (Soup.Session), "user-agent", "singularity-fediverse/0.1", "max-conns-per-host", 6, "timeout", 40);
            }
            return _session;
        }

        public string url_for (string path) {
            if (path.has_prefix ("https://") || path.has_prefix ("http://")) return path;
            return instance + path;
        }

        private Soup.Message make (string method, string path, Params? params) throws Error {
            string url = url_for (path);
            bool query = method == "GET" || method == "DELETE";
            if (query && params != null && params.size > 0) url += (url.contains ("?") ? "&" : "?") + params.encode ();
            var msg = new Soup.Message (method, url);
            if (msg == null) throw new ApiError.INVALID (_("The address %s is not valid").printf (url));
            if (!query) {
                string body = params != null ? params.encode () : "";
                msg.set_request_body_from_bytes ("application/x-www-form-urlencoded", new Bytes (body.data));
            }
            return msg;
        }

        public async Json.Node? call (string method, string path, Params? params = null, Cancellable? cancel = null, out string? next = null) throws Error {
            var msg = make (method, path, params);
            return yield send (msg, cancel, out next);
        }

        public async Json.Node? send (Soup.Message msg, Cancellable? cancel = null, out string? next = null) throws Error {
            next = null;
            if (token != "") msg.request_headers.replace ("Authorization", "Bearer " + token);
            msg.request_headers.replace ("Accept", "application/json");
            var bytes = yield session ().send_and_read_async (msg, Priority.DEFAULT, cancel);
            next = Text.next_link (msg.response_headers.get_one ("Link"));
            Json.Node? root = null;
            if (bytes != null && bytes.get_size () > 0) {
                var p = new Json.Parser ();
                try {
                    p.load_from_data ((string) bytes.get_data (), (ssize_t) bytes.get_size ());
                    if (p.get_root () != null) root = p.get_root ().copy ();
                } catch (Error e) {
                    root = null;
                }
            }
            uint status = msg.status_code;
            if (status >= 200 && status < 300) return root;
            string detail = "";
            if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                detail = J.str (root.get_object (), "error_description", J.str (root.get_object (), "error"));
            }
            if (detail == "") detail = msg.reason_phrase ?? "";
            if (detail == "") detail = _("The server answered with error %u").printf (status);
            if (status == 401) throw new ApiError.UNAUTHORIZED (detail);
            if (status == 404) throw new ApiError.NOT_FOUND (detail);
            throw new ApiError.HTTP ("%s (%u)".printf (detail, status));
        }

        public async void register_app (bool with_oob, out string client_id, out string client_secret) throws Error {
            var root = yield call ("POST", "/api/v1/apps", Oauth.registration_params (with_oob));
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) throw new ApiError.PARSE (_("This server did not accept the app registration."));
            client_id = J.str (root.get_object (), "client_id");
            client_secret = J.str (root.get_object (), "client_secret");
            if (client_id == "" || client_secret == "") throw new ApiError.PARSE (_("This server did not accept the app registration."));
        }

        public async string exchange_code (string client_id, string client_secret, string redirect_uri, string code) throws Error {
            var root = yield call ("POST", "/oauth/token", Oauth.token_params (client_id, client_secret, redirect_uri, code));
            string t = root != null && root.get_node_type () == Json.NodeType.OBJECT ? J.str (root.get_object (), "access_token") : "";
            if (t == "") throw new ApiError.PARSE (_("The server did not return an access token."));
            return t;
        }

        public async void revoke (string client_id, string client_secret) {
            try {
                yield call ("POST", "/oauth/revoke", new Params ().add ("client_id", client_id).add ("client_secret", client_secret).add ("token", token));
            } catch (Error e) {
            }
        }

        public async Account verify_credentials () throws Error {
            var root = yield call ("GET", "/api/v1/accounts/verify_credentials");
            var a = root != null && root.get_node_type () == Json.NodeType.OBJECT ? Account.parse (root.get_object ()) : null;
            if (a == null) throw new ApiError.PARSE (_("The server sent an account this app does not understand."));
            return a;
        }

        public async InstanceInfo instance_info () {
            try {
                var root = yield call ("GET", "/api/v2/instance");
                var info = InstanceInfo.parse (root);
                if (info.streaming != "") return info;
                try {
                    var v1 = InstanceInfo.parse (yield call ("GET", "/api/v1/instance"));
                    if (v1.streaming != "") info.streaming = v1.streaming;
                } catch (Error e) {
                }
                return info;
            } catch (Error e) {
                try {
                    return InstanceInfo.parse (yield call ("GET", "/api/v1/instance"));
                } catch (Error e2) {
                    return new InstanceInfo ();
                }
            }
        }

        public async Status status (string id) throws Error {
            var s = parse_status (yield call ("GET", "/api/v1/statuses/" + id));
            return s;
        }

        public async Context context (string id) throws Error {
            return Context.parse (yield call ("GET", "/api/v1/statuses/%s/context".printf (id)));
        }

        public async Status act (string id, string verb) throws Error {
            return parse_status (yield call ("POST", "/api/v1/statuses/%s/%s".printf (id, verb)));
        }

        public async void delete_status (string id) throws Error {
            yield call ("DELETE", "/api/v1/statuses/" + id);
        }

        public async Account account (string id) throws Error {
            var root = yield call ("GET", "/api/v1/accounts/" + id);
            var a = root != null && root.get_node_type () == Json.NodeType.OBJECT ? Account.parse (root.get_object ()) : null;
            if (a == null) throw new ApiError.PARSE (_("This profile could not be read."));
            return a;
        }

        public async Relationship? relationship (string id) {
            try {
                return Relationship.parse (yield call ("GET", "/api/v1/accounts/relationships", new Params ().add ("id[]", id)));
            } catch (Error e) {
                return null;
            }
        }

        public async Relationship? follow (string id, bool on) throws Error {
            return Relationship.parse (yield call ("POST", "/api/v1/accounts/%s/%s".printf (id, on ? "follow" : "unfollow")));
        }

        public async SearchResults search (string q, bool resolve, Cancellable? cancel = null) throws Error {
            var p = new Params ().add ("q", q).add ("limit", "20");
            if (resolve) p.add ("resolve", "true");
            return SearchResults.parse (yield call ("GET", "/api/v2/search", p, cancel));
        }

        public async Poll? vote (string poll_id, Gee.List<int> choices) throws Error {
            var p = new Params ();
            foreach (int c in choices) p.add ("choices[]", c.to_string ());
            var root = yield call ("POST", "/api/v1/polls/%s/votes".printf (poll_id), p);
            return root != null && root.get_node_type () == Json.NodeType.OBJECT ? Poll.parse (root.get_object ()) : null;
        }

        public async Status post (Params p, string idempotency) throws Error {
            var msg = make ("POST", "/api/v1/statuses", p);
            msg.request_headers.replace ("Idempotency-Key", idempotency);
            return parse_status (yield send (msg));
        }

        public async ScheduledStatus post_scheduled (Params p, string idempotency) throws Error {
            var msg = make ("POST", "/api/v1/statuses", p);
            msg.request_headers.replace ("Idempotency-Key", idempotency);
            var root = yield send (msg);
            var s = root != null && root.get_node_type () == Json.NodeType.OBJECT ? ScheduledStatus.parse (root.get_object ()) : null;
            if (s == null) throw new ApiError.PARSE (_("The server did not schedule the post."));
            return s;
        }

        public async Gee.ArrayList<ScheduledStatus> scheduled (Cancellable? cancel = null) throws Error {
            var all = new Gee.ArrayList<ScheduledStatus> ();
            string? page = null;
            for (int i = 0; i < 5; i++) {
                string? next;
                Json.Node? root;
                if (page == null) root = yield call ("GET", "/api/v1/scheduled_statuses", new Params ().add ("limit", "40"), cancel, out next);
                else root = yield call ("GET", page, null, cancel, out next);
                var list = ScheduledStatus.parse_list (root);
                all.add_all (list);
                if (next == null || list.size == 0) break;
                page = next;
            }
            all.sort ((a, b) => a.scheduled_at.compare (b.scheduled_at));
            return all;
        }

        public async ScheduledStatus? reschedule (string id, DateTime at) throws Error {
            var root = yield call ("PUT", "/api/v1/scheduled_statuses/" + id, Requests.reschedule (at));
            return root != null && root.get_node_type () == Json.NodeType.OBJECT ? ScheduledStatus.parse (root.get_object ()) : null;
        }

        public async void cancel_scheduled (string id) throws Error {
            yield call ("DELETE", "/api/v1/scheduled_statuses/" + id);
        }

        public async Gee.ArrayList<Filter> filters () throws Error {
            return Filter.parse_list (yield call ("GET", "/api/v2/filters"));
        }

        public async Filter? save_filter (string? id, Params p) throws Error {
            var root = yield call (id == null ? "POST" : "PUT", id == null ? "/api/v2/filters" : "/api/v2/filters/" + id, p);
            return root != null && root.get_node_type () == Json.NodeType.OBJECT ? Filter.parse (root.get_object ()) : null;
        }

        public async void delete_filter (string id) throws Error {
            yield call ("DELETE", "/api/v2/filters/" + id);
        }

        public async Gee.ArrayList<Account> account_list (string path) throws Error {
            return Merge.accounts (yield call ("GET", path, new Params ().add ("limit", "80")));
        }

        public async Gee.ArrayList<BlockedDomain> blocked_domains () throws Error {
            return BlockedDomain.parse_list (yield call ("GET", "/api/v1/domain_blocks", new Params ().add ("limit", "200")));
        }

        public async void block_domain (string domain, bool on) throws Error {
            yield call (on ? "POST" : "DELETE", "/api/v1/domain_blocks", new Params ().add ("domain", domain));
        }

        public async void relate (string account_id, string verb) throws Error {
            yield call ("POST", "/api/v1/accounts/%s/%s".printf (account_id, verb));
        }

        public async PostTranslation translate (string status_id, string lang) throws Error {
            var t = PostTranslation.parse (yield call ("POST", Requests.translate_path (status_id), new Params ().add ("lang", lang)));
            if (t == null) throw new ApiError.PARSE (_("The server did not return a translation."));
            return t;
        }

        public async Attachment upload (File file, string description, Cancellable? cancel = null) throws Error {
            uint8[] data;
            yield file.load_contents_async (cancel, out data, null);
            string name = file.get_basename () ?? "upload";
            bool uncertain;
            string type = ContentType.get_mime_type (ContentType.guess (name, data, out uncertain)) ?? "application/octet-stream";
            var mp = new Soup.Multipart ("multipart/form-data");
            mp.append_form_file ("file", name, type, new Bytes (data));
            if (description.strip () != "") mp.append_form_string ("description", description.strip ());
            var msg = new Soup.Message.from_multipart (url_for ("/api/v2/media"), mp);
            Json.Node? root;
            try {
                root = yield send (msg, cancel);
            } catch (ApiError.NOT_FOUND e) {
                var mp1 = new Soup.Multipart ("multipart/form-data");
                mp1.append_form_file ("file", name, type, new Bytes (data));
                if (description.strip () != "") mp1.append_form_string ("description", description.strip ());
                root = yield send (new Soup.Message.from_multipart (url_for ("/api/v1/media"), mp1), cancel);
            }
            var a = root != null && root.get_node_type () == Json.NodeType.OBJECT ? Attachment.parse (root.get_object ()) : null;
            if (a == null || a.id == "") throw new ApiError.PARSE (_("The server did not accept %s.").printf (name));
            for (int tries = 0; a.url == "" && tries < 60; tries++) {
                yield sleep (1000);
                if (cancel != null && cancel.is_cancelled ()) throw new IOError.CANCELLED ("cancelled");
                try {
                    var again = yield call ("GET", "/api/v1/media/" + a.id, null, cancel);
                    var b = again != null && again.get_node_type () == Json.NodeType.OBJECT ? Attachment.parse (again.get_object ()) : null;
                    if (b != null) a = b;
                } catch (ApiError.HTTP e) {
                }
            }
            return a;
        }

        public async void update_media_description (string id, string description) throws Error {
            yield call ("PUT", "/api/v1/media/" + id, new Params ().add ("description", description));
        }

        private static async void sleep (uint ms) {
            Timeout.add (ms, () => {
                sleep.callback ();
                return Source.REMOVE;
            });
            yield;
        }

        private static Status parse_status (Json.Node? root) throws Error {
            var s = root != null && root.get_node_type () == Json.NodeType.OBJECT ? Status.parse (root.get_object ()) : null;
            if (s == null) throw new ApiError.PARSE (_("The server sent a post this app does not understand."));
            return s;
        }
    }

    namespace TranslateBridge {
        public const string NAME = "dev.sinty.TranslateService";
        public const string PATH = "/dev/sinty/TranslateService";

        public async PostTranslation translate (string text, string target) throws Error {
            var bus = yield Bus.get (BusType.SESSION);
            Variant reply;
            try {
                reply = yield bus.call (NAME, PATH, NAME, "Translate", new Variant ("(sss)", text, "auto", target), new VariantType ("(sss)"), DBusCallFlags.NONE, 60000, null);
            } catch (DBusError.SERVICE_UNKNOWN e) {
                throw new ApiError.INVALID (_("Install Translate to translate posts that this server cannot translate."));
            } catch (DBusError.NAME_HAS_NO_OWNER e) {
                throw new ApiError.INVALID (_("Install Translate to translate posts that this server cannot translate."));
            } catch (Error e) {
                string m = e.message;
                DBusError.strip_remote_error (e);
                throw new ApiError.HTTP (e.message != "" ? e.message : m);
            }
            string translated, detected, provider;
            reply.get ("(sss)", out translated, out detected, out provider);
            var t = new PostTranslation ();
            t.content = translated;
            t.detected = detected;
            t.provider = provider != "" ? _("%s through Translate").printf (provider) : _("Translate");
            t.html = false;
            return t;
        }
    }

    public class Stream : Object {
        public signal void received (StreamEvent e);
        public signal void lost ();

        private Soup.WebsocketConnection? ws;
        private Cancellable cancel = new Cancellable ();
        private bool closing;

        public async bool open (string url, string token) {
            var msg = new Soup.Message ("GET", url);
            if (msg == null) return false;
            try {
                ws = yield Client.session ().websocket_connect_async (msg, null, { token }, Priority.DEFAULT, cancel);
            } catch (Error e) {
                ws = null;
                return false;
            }
            ws.keepalive_interval = 30;
            ws.message.connect ((type, data) => {
                if (type != Soup.WebsocketDataType.TEXT) return;
                var sb = new StringBuilder ();
                sb.append_len ((string) data.get_data (), (ssize_t) data.get_size ());
                var ev = StreamEvent.parse (sb.str);
                if (ev != null) received (ev);
            });
            ws.closed.connect (() => {
                if (!closing) lost ();
            });
            return true;
        }

        public void close () {
            closing = true;
            cancel.cancel ();
            if (ws != null && ws.state == Soup.WebsocketState.OPEN) ws.close (1000, null);
            ws = null;
        }
    }

    namespace ImageCache {
        private class Waiter {
            public SourceFunc callback;

            public Waiter (owned SourceFunc cb) {
                callback = (owned) cb;
            }
        }

        private Gee.HashMap<string, Gee.ArrayList<Waiter>>? pending;

        public string dir () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-fediverse", "images");
        }

        public string path_for (string url) {
            return Path.build_filename (dir (), Checksum.compute_for_string (ChecksumType.SHA256, url));
        }

        public async string? fetch (string url) {
            if (!Content.safe_href (url) || url.has_prefix ("mailto:")) return null;
            string path = path_for (url);
            if (FileUtils.test (path, FileTest.EXISTS)) return path;
            if (pending == null) pending = new Gee.HashMap<string, Gee.ArrayList<Waiter>> ();
            if (pending.has_key (url)) {
                pending[url].add (new Waiter (fetch.callback));
                yield;
                return FileUtils.test (path, FileTest.EXISTS) ? path : null;
            }
            pending[url] = new Gee.ArrayList<Waiter> ();
            try {
                var msg = new Soup.Message ("GET", url);
                if (msg != null) {
                    var bytes = yield Client.session ().send_and_read_async (msg, Priority.LOW, null);
                    if (msg.status_code == 200 && bytes.get_size () > 0 && bytes.get_size () < 40 * 1024 * 1024) {
                        DirUtils.create_with_parents (dir (), 0700);
                        string tmp = path + ".part";
                        FileUtils.set_data (tmp, bytes.get_data ());
                        FileUtils.rename (tmp, path);
                    }
                }
            } catch (Error e) {
            }
            var waiters = pending[url];
            pending.unset (url);
            foreach (var w in waiters) Idle.add ((owned) w.callback);
            return FileUtils.test (path, FileTest.EXISTS) ? path : null;
        }

        public async Gdk.Texture? texture (string url) {
            string? path = yield fetch (url);
            if (path == null) return null;
            try {
                return Gdk.Texture.from_filename (path);
            } catch (Error e) {
                return null;
            }
        }

        public void prune (int days = 7) {
            try {
                var d = Dir.open (dir ());
                string? name;
                int64 limit = new DateTime.now_utc ().to_unix () - days * 86400;
                while ((name = d.read_name ()) != null) {
                    string p = Path.build_filename (dir (), name);
                    Posix.Stat st;
                    if (Posix.stat (p, out st) == 0 && st.st_atime < limit && st.st_mtime < limit) FileUtils.remove (p);
                }
            } catch (Error e) {
            }
        }
    }
}
