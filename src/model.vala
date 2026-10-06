namespace Singularity.Apps.Fediverse {

    namespace J {
        public string str (Json.Object? o, string name, string fallback = "") {
            if (o == null || !o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n == null || n.get_node_type () != Json.NodeType.VALUE) return fallback;
            if (n.get_value_type () == typeof (string)) return n.get_string () ?? fallback;
            if (n.get_value_type () == typeof (int64)) return n.get_int ().to_string ();
            return fallback;
        }

        public int64 num (Json.Object? o, string name, int64 fallback = 0) {
            if (o == null || !o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n == null || n.get_node_type () != Json.NodeType.VALUE) return fallback;
            if (n.get_value_type () == typeof (int64)) return n.get_int ();
            if (n.get_value_type () == typeof (double)) return (int64) n.get_double ();
            if (n.get_value_type () == typeof (string)) return int64.parse (n.get_string ());
            return fallback;
        }

        public double dbl (Json.Object? o, string name, double fallback = 0) {
            if (o == null || !o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n == null || n.get_node_type () != Json.NodeType.VALUE) return fallback;
            if (n.get_value_type () == typeof (double)) return n.get_double ();
            if (n.get_value_type () == typeof (int64)) return (double) n.get_int ();
            return fallback;
        }

        public bool flag (Json.Object? o, string name, bool fallback = false) {
            if (o == null || !o.has_member (name)) return fallback;
            var n = o.get_member (name);
            if (n == null || n.get_node_type () != Json.NodeType.VALUE) return fallback;
            if (n.get_value_type () == typeof (bool)) return n.get_boolean ();
            return fallback;
        }

        public Json.Object? obj (Json.Object? o, string name) {
            if (o == null || !o.has_member (name)) return null;
            var n = o.get_member (name);
            if (n == null || n.get_node_type () != Json.NodeType.OBJECT) return null;
            return n.get_object ();
        }

        public Json.Array? arr (Json.Object? o, string name) {
            if (o == null || !o.has_member (name)) return null;
            var n = o.get_member (name);
            if (n == null || n.get_node_type () != Json.NodeType.ARRAY) return null;
            return n.get_array ();
        }

        public DateTime? date (Json.Object? o, string name) {
            string s = str (o, name);
            if (s == "") return null;
            return new DateTime.from_iso8601 (s, new TimeZone.utc ());
        }
    }

    public class Emoji : Object {
        public string shortcode = "";
        public string url = "";

        public static Gee.ArrayList<Emoji> list (Json.Array? a) {
            var out_list = new Gee.ArrayList<Emoji> ();
            if (a == null) return out_list;
            foreach (var n in a.get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var o = n.get_object ();
                var e = new Emoji ();
                e.shortcode = J.str (o, "shortcode");
                e.url = J.str (o, "static_url", J.str (o, "url"));
                if (e.url == "") e.url = J.str (o, "url");
                if (e.shortcode != "" && Content.safe_href (e.url)) out_list.add (e);
            }
            return out_list;
        }
    }

    public class Mention : Object {
        public string id = "";
        public string username = "";
        public string acct = "";
        public string url = "";

        public static Gee.ArrayList<Mention> list (Json.Array? a) {
            var out_list = new Gee.ArrayList<Mention> ();
            if (a == null) return out_list;
            foreach (var n in a.get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var o = n.get_object ();
                var m = new Mention ();
                m.id = J.str (o, "id");
                m.username = J.str (o, "username");
                m.acct = J.str (o, "acct");
                m.url = J.str (o, "url");
                out_list.add (m);
            }
            return out_list;
        }
    }

    public class Field : Object {
        public string name = "";
        public string value = "";
        public bool verified;
    }

    public class Account : Object {
        public string id = "";
        public string username = "";
        public string acct = "";
        public string display_name = "";
        public string note = "";
        public string url = "";
        public string avatar = "";
        public string header = "";
        public bool locked;
        public bool bot;
        public int64 followers_count;
        public int64 following_count;
        public int64 statuses_count;
        public DateTime? created_at;
        public Gee.ArrayList<Emoji> emojis = new Gee.ArrayList<Emoji> ();
        public Gee.ArrayList<Field> fields = new Gee.ArrayList<Field> ();
        public string via = "";

        public string name () {
            return display_name.strip () != "" ? display_name : username;
        }

        public string handle (string local_host = "") {
            if (acct.contains ("@")) return "@" + acct;
            if (local_host != "") return "@%s@%s".printf (acct, local_host);
            string host = "";
            if (url != "") {
                var u = Oauth.host_of (url);
                if (u != null) host = u;
            }
            return host != "" ? "@%s@%s".printf (acct, host) : "@" + acct;
        }

        public static Account? parse (Json.Object? o) {
            if (o == null || J.str (o, "id") == "") return null;
            var a = new Account ();
            a.id = J.str (o, "id");
            a.username = J.str (o, "username");
            a.acct = J.str (o, "acct", a.username);
            a.display_name = J.str (o, "display_name");
            a.note = J.str (o, "note");
            a.url = J.str (o, "url");
            a.avatar = J.str (o, "avatar_static", J.str (o, "avatar"));
            if (a.avatar == "") a.avatar = J.str (o, "avatar");
            a.header = J.str (o, "header_static", J.str (o, "header"));
            a.locked = J.flag (o, "locked");
            a.bot = J.flag (o, "bot");
            a.followers_count = J.num (o, "followers_count");
            a.following_count = J.num (o, "following_count");
            a.statuses_count = J.num (o, "statuses_count");
            a.created_at = J.date (o, "created_at");
            a.emojis = Emoji.list (J.arr (o, "emojis"));
            var fields = J.arr (o, "fields");
            if (fields != null) {
                foreach (var n in fields.get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    var fo = n.get_object ();
                    var f = new Field ();
                    f.name = J.str (fo, "name");
                    f.value = J.str (fo, "value");
                    f.verified = J.str (fo, "verified_at") != "";
                    a.fields.add (f);
                }
            }
            return a;
        }
    }

    public enum MediaType {
        IMAGE,
        GIFV,
        VIDEO,
        AUDIO,
        UNKNOWN;

        public static MediaType parse (string s) {
            switch (s) {
                case "image": return IMAGE;
                case "gifv": return GIFV;
                case "video": return VIDEO;
                case "audio": return AUDIO;
                default: return UNKNOWN;
            }
        }
    }

    public class Attachment : Object {
        public string id = "";
        public MediaType kind;
        public string url = "";
        public string preview_url = "";
        public string remote_url = "";
        public string description = "";
        public double aspect;

        public static Attachment? parse (Json.Object? o) {
            if (o == null) return null;
            var m = new Attachment ();
            m.id = J.str (o, "id");
            m.kind = MediaType.parse (J.str (o, "type"));
            m.url = J.str (o, "url");
            m.remote_url = J.str (o, "remote_url");
            if (m.url == "") m.url = m.remote_url;
            m.preview_url = J.str (o, "preview_url", m.url);
            if (m.preview_url == "") m.preview_url = m.url;
            m.description = J.str (o, "description");
            var meta = J.obj (o, "meta");
            var small = J.obj (meta, "small") ?? J.obj (meta, "original");
            m.aspect = J.dbl (small, "aspect");
            if (m.aspect <= 0) {
                double w = J.dbl (small, "width"), h = J.dbl (small, "height");
                if (w > 0 && h > 0) m.aspect = w / h;
            }
            return m;
        }
    }

    public class PollOption : Object {
        public string title = "";
        public int64 votes = -1;
    }

    public class Poll : Object {
        public string id = "";
        public bool expired;
        public bool multiple;
        public bool voted;
        public int64 votes_count;
        public int64 voters_count = -1;
        public DateTime? expires_at;
        public Gee.ArrayList<PollOption> options = new Gee.ArrayList<PollOption> ();
        public Gee.ArrayList<int> own_votes = new Gee.ArrayList<int> ();
        public Gee.ArrayList<Emoji> emojis = new Gee.ArrayList<Emoji> ();

        public static Poll? parse (Json.Object? o) {
            if (o == null || J.str (o, "id") == "") return null;
            var p = new Poll ();
            p.id = J.str (o, "id");
            p.expired = J.flag (o, "expired");
            p.multiple = J.flag (o, "multiple");
            p.voted = J.flag (o, "voted");
            p.votes_count = J.num (o, "votes_count");
            p.voters_count = J.num (o, "voters_count", -1);
            p.expires_at = J.date (o, "expires_at");
            p.emojis = Emoji.list (J.arr (o, "emojis"));
            var opts = J.arr (o, "options");
            if (opts != null) {
                foreach (var n in opts.get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    var po = new PollOption ();
                    po.title = J.str (n.get_object (), "title");
                    po.votes = J.num (n.get_object (), "votes_count", -1);
                    p.options.add (po);
                }
            }
            var own = J.arr (o, "own_votes");
            if (own != null) foreach (var n in own.get_elements ()) p.own_votes.add ((int) n.get_int ());
            return p;
        }

        public double share (int index) {
            if (index < 0 || index >= options.size) return 0;
            int64 total = multiple && voters_count > 0 ? voters_count : votes_count;
            if (total <= 0 || options[index].votes < 0) return 0;
            return (double) options[index].votes / total;
        }
    }

    public enum Visibility {
        PUBLIC,
        UNLISTED,
        PRIVATE,
        DIRECT;

        public static Visibility parse (string s) {
            switch (s) {
                case "unlisted": return UNLISTED;
                case "private": return PRIVATE;
                case "direct": return DIRECT;
                default: return PUBLIC;
            }
        }

        public string to_api () {
            switch (this) {
                case UNLISTED: return "unlisted";
                case PRIVATE: return "private";
                case DIRECT: return "direct";
                default: return "public";
            }
        }

        public string label () {
            switch (this) {
                case UNLISTED: return _("Quiet Public");
                case PRIVATE: return _("Followers Only");
                case DIRECT: return _("Mentioned People Only");
                default: return _("Public");
            }
        }

        public string icon () {
            switch (this) {
                case UNLISTED: return "night-light-symbolic";
                case PRIVATE: return "changes-prevent-symbolic";
                case DIRECT: return "mail-unread-symbolic";
                default: return "web-browser-symbolic";
            }
        }
    }

    public class Status : Object {
        public string id = "";
        public string uri = "";
        public string url = "";
        public string content = "";
        public string spoiler_text = "";
        public bool sensitive;
        public Visibility visibility;
        public DateTime? created_at;
        public DateTime? edited_at;
        public Account account;
        public Status? reblog;
        public string in_reply_to_id = "";
        public string in_reply_to_account_id = "";
        public int64 replies_count;
        public int64 reblogs_count;
        public int64 favourites_count;
        public bool favourited;
        public bool reblogged;
        public bool bookmarked;
        public bool pinned;
        public string language = "";
        public Gee.ArrayList<Attachment> media = new Gee.ArrayList<Attachment> ();
        public Gee.ArrayList<Mention> mentions = new Gee.ArrayList<Mention> ();
        public Gee.ArrayList<Emoji> emojis = new Gee.ArrayList<Emoji> ();
        public Poll? poll;
        public Gee.ArrayList<FilterHit> filtered = new Gee.ArrayList<FilterHit> ();
        public string via = "";
        public bool merged;

        public Status shown () {
            return reblog ?? this;
        }

        public Content body () {
            return Content.parse (content, emojis, mentions);
        }

        public static Status? parse (Json.Object? o) {
            if (o == null || J.str (o, "id") == "") return null;
            var acc = Account.parse (J.obj (o, "account"));
            if (acc == null) return null;
            var s = new Status ();
            s.id = J.str (o, "id");
            s.uri = J.str (o, "uri");
            s.url = J.str (o, "url", s.uri);
            if (s.url == "") s.url = s.uri;
            s.content = J.str (o, "content");
            s.spoiler_text = J.str (o, "spoiler_text");
            s.sensitive = J.flag (o, "sensitive");
            s.visibility = Visibility.parse (J.str (o, "visibility"));
            s.created_at = J.date (o, "created_at");
            s.edited_at = J.date (o, "edited_at");
            s.account = acc;
            s.reblog = Status.parse (J.obj (o, "reblog"));
            s.in_reply_to_id = J.str (o, "in_reply_to_id");
            s.in_reply_to_account_id = J.str (o, "in_reply_to_account_id");
            s.replies_count = J.num (o, "replies_count");
            s.reblogs_count = J.num (o, "reblogs_count");
            s.favourites_count = J.num (o, "favourites_count");
            s.favourited = J.flag (o, "favourited");
            s.reblogged = J.flag (o, "reblogged");
            s.bookmarked = J.flag (o, "bookmarked");
            s.pinned = J.flag (o, "pinned");
            s.language = J.str (o, "language");
            var media = J.arr (o, "media_attachments");
            if (media != null) {
                foreach (var n in media.get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    var m = Attachment.parse (n.get_object ());
                    if (m != null && m.url != "") s.media.add (m);
                }
            }
            s.mentions = Mention.list (J.arr (o, "mentions"));
            s.emojis = Emoji.list (J.arr (o, "emojis"));
            s.poll = Poll.parse (J.obj (o, "poll"));
            s.filtered = FilterHit.list (J.arr (o, "filtered"));
            return s;
        }

        public string merge_key () {
            var t = shown ();
            if (t.uri != "") return t.uri;
            if (t.url != "") return t.url;
            return via + "/" + t.id;
        }

        public DateTime? sort_time () {
            return created_at ?? shown ().created_at;
        }

        public void tag_via (string key) {
            if (key == "") return;
            if (via == "") via = key;
            if (account != null && account.via == "") account.via = key;
            if (reblog != null) reblog.tag_via (key);
        }

        public static Gee.ArrayList<Status> parse_list (Json.Node? root) {
            var list = new Gee.ArrayList<Status> ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return list;
            foreach (var n in root.get_array ().get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var s = Status.parse (n.get_object ());
                if (s != null) list.add (s);
            }
            return list;
        }
    }

    public class FilterKeyword : Object {
        public string id = "";
        public string keyword = "";
        public bool whole_word = true;
        public bool destroy;

        public FilterKeyword (string keyword = "", bool whole_word = true) {
            this.keyword = keyword;
            this.whole_word = whole_word;
        }
    }

    public class Filter : Object {
        public const string[] CONTEXTS = { "home", "notifications", "public", "thread", "account" };

        public string id = "";
        public string title = "";
        public Gee.ArrayList<string> context = new Gee.ArrayList<string> ();
        public string action = "warn";
        public DateTime? expires_at;
        public Gee.ArrayList<FilterKeyword> keywords = new Gee.ArrayList<FilterKeyword> ();
        public int statuses;

        public bool hides () {
            return action == "hide";
        }

        public bool applies (string ctx) {
            if (ctx == "") return false;
            if (context.size == 0) return true;
            return context.contains (ctx);
        }

        public bool expired (DateTime now) {
            return expires_at != null && expires_at.compare (now) <= 0;
        }

        public static Filter? parse (Json.Object? o) {
            if (o == null || J.str (o, "id") == "") return null;
            var f = new Filter ();
            f.id = J.str (o, "id");
            f.title = J.str (o, "title", J.str (o, "phrase"));
            var ctx = J.arr (o, "context");
            if (ctx != null) {
                foreach (var n in ctx.get_elements ()) {
                    if (n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (string)) f.context.add (n.get_string ());
                }
            }
            f.action = J.str (o, "filter_action", J.flag (o, "irreversible") ? "hide" : "warn");
            f.expires_at = J.date (o, "expires_at");
            var kws = J.arr (o, "keywords");
            if (kws != null) {
                foreach (var n in kws.get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    var ko = n.get_object ();
                    var k = new FilterKeyword (J.str (ko, "keyword"), J.flag (ko, "whole_word", true));
                    k.id = J.str (ko, "id");
                    if (k.keyword != "") f.keywords.add (k);
                }
            } else if (o.has_member ("phrase")) {
                f.keywords.add (new FilterKeyword (J.str (o, "phrase"), J.flag (o, "whole_word", true)));
            }
            var sts = J.arr (o, "statuses");
            f.statuses = sts != null ? (int) sts.get_length () : 0;
            return f;
        }

        public static Gee.ArrayList<Filter> parse_list (Json.Node? root) {
            var list = new Gee.ArrayList<Filter> ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return list;
            foreach (var n in root.get_array ().get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var f = Filter.parse (n.get_object ());
                if (f != null) list.add (f);
            }
            return list;
        }

        public string summary () {
            string[] words = {};
            foreach (var k in keywords) words += k.keyword;
            string what = words.length > 0 ? string.joinv (", ", words) : _("No words");
            return hides () ? _("Hides posts with %s").printf (what) : _("Warns about posts with %s").printf (what);
        }
    }

    public class FilterHit : Object {
        public Filter filter;
        public Gee.ArrayList<string> keywords = new Gee.ArrayList<string> ();

        public static Gee.ArrayList<FilterHit> list (Json.Array? a) {
            var out_list = new Gee.ArrayList<FilterHit> ();
            if (a == null) return out_list;
            foreach (var n in a.get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var o = n.get_object ();
                var f = Filter.parse (J.obj (o, "filter"));
                if (f == null) continue;
                var h = new FilterHit ();
                h.filter = f;
                var kw = J.arr (o, "keyword_matches");
                if (kw != null) {
                    foreach (var k in kw.get_elements ()) {
                        if (k.get_node_type () == Json.NodeType.VALUE && k.get_value_type () == typeof (string)) h.keywords.add (k.get_string ());
                    }
                }
                out_list.add (h);
            }
            return out_list;
        }
    }

    public enum FilterVerdict {
        SHOW,
        WARN,
        HIDE
    }

    namespace Filters {
        public FilterVerdict verdict (Status s, string context, out string titles, DateTime? now = null) {
            titles = "";
            var when = now ?? new DateTime.now_utc ();
            string[] names = {};
            bool warn = false;
            var hits = new Gee.ArrayList<FilterHit> ();
            hits.add_all (s.filtered);
            if (s.reblog != null) hits.add_all (s.reblog.filtered);
            foreach (var h in hits) {
                if (!h.filter.applies (context) || h.filter.expired (when)) continue;
                if (h.filter.hides ()) return FilterVerdict.HIDE;
                warn = true;
                bool seen = false;
                foreach (string n in names) if (n == h.filter.title) seen = true;
                if (!seen) names += h.filter.title;
            }
            titles = string.joinv (", ", names);
            return warn ? FilterVerdict.WARN : FilterVerdict.SHOW;
        }
    }

    public class ScheduledStatus : Object {
        public string id = "";
        public DateTime? scheduled_at;
        public string text = "";
        public string spoiler_text = "";
        public Visibility visibility;
        public bool sensitive;
        public string in_reply_to_id = "";
        public string language = "";
        public Gee.ArrayList<Attachment> media = new Gee.ArrayList<Attachment> ();
        public Gee.ArrayList<string> media_ids = new Gee.ArrayList<string> ();

        public static ScheduledStatus? parse (Json.Object? o) {
            if (o == null || J.str (o, "id") == "" || J.str (o, "scheduled_at") == "") return null;
            var s = new ScheduledStatus ();
            s.id = J.str (o, "id");
            s.scheduled_at = J.date (o, "scheduled_at");
            var p = J.obj (o, "params");
            s.text = J.str (p, "text");
            s.spoiler_text = J.str (p, "spoiler_text");
            s.visibility = Visibility.parse (J.str (p, "visibility"));
            s.sensitive = J.flag (p, "sensitive");
            s.in_reply_to_id = J.str (p, "in_reply_to_id");
            s.language = J.str (p, "language");
            var ids = J.arr (p, "media_ids");
            if (ids != null) {
                foreach (var n in ids.get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.VALUE) continue;
                    if (n.get_value_type () == typeof (string)) s.media_ids.add (n.get_string ());
                    else if (n.get_value_type () == typeof (int64)) s.media_ids.add (n.get_int ().to_string ());
                }
            }
            var media = J.arr (o, "media_attachments");
            if (media != null) {
                foreach (var n in media.get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    var m = Attachment.parse (n.get_object ());
                    if (m != null) s.media.add (m);
                }
            }
            return s;
        }

        public static Gee.ArrayList<ScheduledStatus> parse_list (Json.Node? root) {
            var list = new Gee.ArrayList<ScheduledStatus> ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return list;
            foreach (var n in root.get_array ().get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var s = ScheduledStatus.parse (n.get_object ());
                if (s != null) list.add (s);
            }
            list.sort ((a, b) => a.scheduled_at.compare (b.scheduled_at));
            return list;
        }
    }

    public class PostTranslation : Object {
        public string content = "";
        public string spoiler_text = "";
        public string detected = "";
        public string provider = "";
        public bool html = true;

        public static PostTranslation? parse (Json.Node? root) {
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;
            var o = root.get_object ();
            var t = new PostTranslation ();
            t.content = J.str (o, "content");
            t.spoiler_text = J.str (o, "spoiler_text");
            t.detected = J.str (o, "detected_source_language");
            t.provider = J.str (o, "provider");
            if (t.content == "" && t.spoiler_text == "") return null;
            return t;
        }
    }

    public class BlockedDomain : Object {
        public string domain;

        public BlockedDomain (string domain) {
            this.domain = domain;
        }

        public static Gee.ArrayList<BlockedDomain> parse_list (Json.Node? root) {
            var list = new Gee.ArrayList<BlockedDomain> ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return list;
            foreach (var n in root.get_array ().get_elements ()) {
                if (n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (string)) {
                    list.add (new BlockedDomain (n.get_string ()));
                } else if (n.get_node_type () == Json.NodeType.OBJECT) {
                    string d = J.str (n.get_object (), "domain");
                    if (d != "") list.add (new BlockedDomain (d));
                }
            }
            return list;
        }
    }

    namespace Merge {
        public Gee.ArrayList<Status> timelines (Gee.List<Gee.List<Status>> sources, Gee.Set<string>? seen = null) {
            var all = new Gee.ArrayList<Status> ();
            foreach (var src in sources) all.add_all (src);
            all.sort ((a, b) => {
                var ta = a.sort_time ();
                var tb = b.sort_time ();
                if (ta == null || tb == null) return ta == null ? (tb == null ? 0 : 1) : -1;
                int c = tb.compare (ta);
                if (c != 0) return c;
                return strcmp (a.via, b.via);
            });
            var keys = new Gee.HashSet<string> ();
            if (seen != null) keys.add_all (seen);
            var result = new Gee.ArrayList<Status> ();
            foreach (var s in all) {
                string k = s.merge_key ();
                if (keys.contains (k)) continue;
                keys.add (k);
                s.merged = true;
                result.add (s);
            }
            return result;
        }

        public Gee.ArrayList<Account> accounts (Json.Node? root) {
            var list = new Gee.ArrayList<Account> ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return list;
            foreach (var n in root.get_array ().get_elements ()) {
                if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                var a = Account.parse (n.get_object ());
                if (a != null) list.add (a);
            }
            return list;
        }
    }

    public enum NotificationKind {
        MENTION,
        STATUS,
        REBLOG,
        FOLLOW,
        FOLLOW_REQUEST,
        FAVOURITE,
        POLL,
        UPDATE,
        OTHER;

        public static NotificationKind parse (string s) {
            switch (s) {
                case "mention": return MENTION;
                case "status": return STATUS;
                case "reblog": return REBLOG;
                case "follow": return FOLLOW;
                case "follow_request": return FOLLOW_REQUEST;
                case "favourite": return FAVOURITE;
                case "poll": return POLL;
                case "update": return UPDATE;
                default: return OTHER;
            }
        }
    }

    public class Notice : Object {
        public string id = "";
        public NotificationKind kind;
        public string raw_kind = "";
        public DateTime? created_at;
        public Account account;
        public Status? status;

        public static Notice? parse (Json.Object? o) {
            if (o == null || J.str (o, "id") == "") return null;
            var acc = Account.parse (J.obj (o, "account"));
            if (acc == null) return null;
            var n = new Notice ();
            n.id = J.str (o, "id");
            n.raw_kind = J.str (o, "type");
            n.kind = NotificationKind.parse (n.raw_kind);
            n.created_at = J.date (o, "created_at");
            n.account = acc;
            n.status = Status.parse (J.obj (o, "status"));
            return n;
        }

        public static Gee.ArrayList<Notice> parse_list (Json.Node? root) {
            var list = new Gee.ArrayList<Notice> ();
            if (root == null || root.get_node_type () != Json.NodeType.ARRAY) return list;
            foreach (var node in root.get_array ().get_elements ()) {
                if (node.get_node_type () != Json.NodeType.OBJECT) continue;
                var n = Notice.parse (node.get_object ());
                if (n != null) list.add (n);
            }
            return list;
        }

        public string summary () {
            string who = account.name ();
            switch (kind) {
                case NotificationKind.MENTION: return _("%s mentioned you").printf (who);
                case NotificationKind.STATUS: return _("%s posted").printf (who);
                case NotificationKind.REBLOG: return _("%s boosted your post").printf (who);
                case NotificationKind.FOLLOW: return _("%s followed you").printf (who);
                case NotificationKind.FOLLOW_REQUEST: return _("%s asked to follow you").printf (who);
                case NotificationKind.FAVOURITE: return _("%s liked your post").printf (who);
                case NotificationKind.POLL: return _("A poll you took part in has ended");
                case NotificationKind.UPDATE: return _("%s edited a post").printf (who);
                default: return _("%s interacted with you").printf (who);
            }
        }

        public string icon () {
            switch (kind) {
                case NotificationKind.MENTION: return "mail-reply-sender-symbolic";
                case NotificationKind.REBLOG: return "media-playlist-repeat-symbolic";
                case NotificationKind.FOLLOW:
                case NotificationKind.FOLLOW_REQUEST: return "contact-new-symbolic";
                case NotificationKind.FAVOURITE: return "starred-symbolic";
                case NotificationKind.POLL: return "view-list-bullet-symbolic";
                case NotificationKind.UPDATE: return "document-edit-symbolic";
                default: return "user-available-symbolic";
            }
        }
    }

    public class Relationship : Object {
        public string id = "";
        public bool following;
        public bool requested;
        public bool followed_by;
        public bool blocking;
        public bool muting;

        public static Relationship? parse (Json.Node? root) {
            Json.Object? o = null;
            if (root == null) return null;
            if (root.get_node_type () == Json.NodeType.ARRAY) {
                var a = root.get_array ();
                if (a.get_length () == 0) return null;
                var first = a.get_element (0);
                if (first.get_node_type () != Json.NodeType.OBJECT) return null;
                o = first.get_object ();
            } else if (root.get_node_type () == Json.NodeType.OBJECT) {
                o = root.get_object ();
            }
            if (o == null) return null;
            var r = new Relationship ();
            r.id = J.str (o, "id");
            r.following = J.flag (o, "following");
            r.requested = J.flag (o, "requested");
            r.followed_by = J.flag (o, "followed_by");
            r.blocking = J.flag (o, "blocking");
            r.muting = J.flag (o, "muting");
            return r;
        }
    }

    public class Context : Object {
        public Gee.ArrayList<Status> ancestors = new Gee.ArrayList<Status> ();
        public Gee.ArrayList<Status> descendants = new Gee.ArrayList<Status> ();

        public static Context parse (Json.Node? root) {
            var c = new Context ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return c;
            var o = root.get_object ();
            if (o.has_member ("ancestors")) c.ancestors = Status.parse_list (o.get_member ("ancestors"));
            if (o.has_member ("descendants")) c.descendants = Status.parse_list (o.get_member ("descendants"));
            return c;
        }
    }

    public class SearchResults : Object {
        public Gee.ArrayList<Account> accounts = new Gee.ArrayList<Account> ();
        public Gee.ArrayList<Status> statuses = new Gee.ArrayList<Status> ();
        public Gee.ArrayList<string> hashtags = new Gee.ArrayList<string> ();

        public static SearchResults parse (Json.Node? root) {
            var r = new SearchResults ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return r;
            var o = root.get_object ();
            var accs = J.arr (o, "accounts");
            if (accs != null) {
                foreach (var n in accs.get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    var a = Account.parse (n.get_object ());
                    if (a != null) r.accounts.add (a);
                }
            }
            if (o.has_member ("statuses")) r.statuses = Status.parse_list (o.get_member ("statuses"));
            var tags = J.arr (o, "hashtags");
            if (tags != null) {
                foreach (var n in tags.get_elements ()) {
                    if (n.get_node_type () == Json.NodeType.OBJECT) {
                        string name = J.str (n.get_object (), "name");
                        if (name != "") r.hashtags.add (name);
                    } else if (n.get_node_type () == Json.NodeType.VALUE && n.get_value_type () == typeof (string)) {
                        r.hashtags.add (n.get_string ());
                    }
                }
            }
            return r;
        }
    }

    public class InstanceInfo : Object {
        public string title = "";
        public string version = "";
        public int max_characters = 500;
        public int max_media = 4;
        public int max_poll_options = 4;
        public int url_length = 23;
        public string streaming = "";
        public bool translation;

        public static InstanceInfo parse (Json.Node? root) {
            var info = new InstanceInfo ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return info;
            var o = root.get_object ();
            info.title = J.str (o, "title");
            info.version = J.str (o, "version");
            var conf = J.obj (o, "configuration");
            var statuses = J.obj (conf, "statuses");
            int64 max_chars = J.num (statuses, "max_characters", J.num (o, "max_toot_chars", 500));
            if (max_chars > 0) info.max_characters = (int) max_chars;
            int64 media = J.num (statuses, "max_media_attachments", 4);
            if (media > 0) info.max_media = (int) media;
            int64 url_len = J.num (statuses, "characters_reserved_per_url", 23);
            if (url_len > 0) info.url_length = (int) url_len;
            int64 poll = J.num (J.obj (conf, "polls"), "max_options", 4);
            if (poll > 0) info.max_poll_options = (int) poll;
            info.streaming = J.str (J.obj (conf, "urls"), "streaming", J.str (J.obj (o, "urls"), "streaming_api"));
            info.translation = J.flag (J.obj (conf, "translation"), "enabled");
            return info;
        }
    }

    public class StreamEvent : Object {
        public string event = "";
        public Json.Node? payload;
        public string payload_text = "";

        public static StreamEvent? parse (string text) {
            var p = new Json.Parser ();
            try {
                p.load_from_data (text);
            } catch (Error e) {
                return null;
            }
            var root = p.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return null;
            var o = root.get_object ();
            var ev = new StreamEvent ();
            ev.event = J.str (o, "event");
            if (ev.event == "") return null;
            if (o.has_member ("payload")) {
                var pn = o.get_member ("payload");
                if (pn.get_node_type () == Json.NodeType.VALUE && pn.get_value_type () == typeof (string)) {
                    ev.payload_text = pn.get_string ();
                    var inner = new Json.Parser ();
                    try {
                        inner.load_from_data (ev.payload_text);
                        ev.payload = inner.get_root () != null ? inner.get_root ().copy () : null;
                    } catch (Error e) {
                        ev.payload = null;
                    }
                } else {
                    ev.payload = pn.copy ();
                }
            }
            return ev;
        }
    }

    namespace Text {
        public string? next_link (string? header) {
            if (header == null) return null;
            foreach (string part in header.split (",")) {
                string p = part.strip ();
                int lt = p.index_of_char ('<');
                int gt = p.index_of_char ('>');
                if (lt < 0 || gt < lt) continue;
                string rest = p.substring (gt + 1).down ().replace (" ", "");
                if (rest.contains ("rel=\"next\"") || rest.contains ("rel=next")) return p.substring (lt + 1, gt - lt - 1);
            }
            return null;
        }

        public int count_chars (string text, string spoiler = "", int url_length = 23) {
            int total = spoiler.char_count ();
            try {
                var url_re = new Regex ("(?<![\\w/])https?://[^\\s<>\"]+", RegexCompileFlags.OPTIMIZE);
                var mention_re = new Regex ("(?<![\\w/@])@([A-Za-z0-9_]+(?:[A-Za-z0-9_.-]*[A-Za-z0-9_])?)@[A-Za-z0-9.-]+\\.[A-Za-z0-9-]+", RegexCompileFlags.OPTIMIZE);
                string s = url_re.replace (text, -1, 0, string.nfill (url_length, 'x'));
                s = mention_re.replace (s, -1, 0, "@\\1");
                total += s.char_count ();
            } catch (RegexError e) {
                total += text.char_count ();
            }
            return total;
        }

        public string relative_time (DateTime? t, DateTime? now = null) {
            if (t == null) return "";
            var n = now ?? new DateTime.now_utc ();
            int64 secs = (n.to_unix () - t.to_unix ());
            if (secs < 60) return _("now");
            if (secs < 3600) return _("%dm").printf ((int) (secs / 60));
            if (secs < 86400) return _("%dh").printf ((int) (secs / 3600));
            if (secs < 86400 * 7) return _("%dd").printf ((int) (secs / 86400));
            var local = t.to_local ();
            if (local.get_year () == n.to_local ().get_year ()) return local.format ("%e %b").strip ();
            return local.format ("%e %b %Y").strip ();
        }

        public string compact (int64 n) {
            if (n < 1000) return n.to_string ();
            if (n < 10000) return "%.1fK".printf (n / 1000.0).replace (".0K", "K");
            if (n < 1000000) return "%dK".printf ((int) (n / 1000));
            return "%.1fM".printf (n / 1000000.0).replace (".0M", "M");
        }
    }
}
