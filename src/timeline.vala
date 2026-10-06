using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Fediverse {

    public enum FeedKind {
        HOME,
        LOCAL,
        FEDERATED,
        NOTIFICATIONS,
        BOOKMARKS,
        FAVOURITES,
        HASHTAG,
        PROFILE,
        THREAD,
        SEARCH,
        UNIFIED,
        DRAFTS,
        SCHEDULED,
        FILTERS
    }

    public abstract class Page : Box {
        public Feed feed;

        public virtual void reload () {
        }

        public virtual void add_new (Gee.List<Object> items) {
        }

        public virtual void remove_status (string id) {
        }

        public virtual void replace_status (Status fresh) {
        }

        public virtual async void poll_newer () {
        }

        public virtual void focus_list () {
        }
    }

    public class TagItem : Object {
        public string name;

        public TagItem (string name) {
            this.name = name;
        }
    }

    public class Feed : Object {
        public FeedKind kind;
        public string arg = "";
        public Account? account;
        public Status? focus;
        public Gee.List<Session>? sessions;
        public DraftStore? drafts;
        private Gee.HashMap<string, string> cursors = new Gee.HashMap<string, string> ();
        private Gee.HashSet<string> exhausted = new Gee.HashSet<string> ();
        public const string MORE = "unified:more";

        public Feed (FeedKind kind, string arg = "") {
            this.kind = kind;
            this.arg = arg;
        }

        public string title () {
            switch (kind) {
                case FeedKind.HOME: return _("Home");
                case FeedKind.LOCAL: return _("Local");
                case FeedKind.FEDERATED: return _("Federated");
                case FeedKind.NOTIFICATIONS: return _("Notifications");
                case FeedKind.BOOKMARKS: return _("Bookmarks");
                case FeedKind.FAVOURITES: return _("Favourites");
                case FeedKind.HASHTAG: return "#" + arg;
                case FeedKind.PROFILE: return account != null ? account.name () : _("Profile");
                case FeedKind.THREAD: return _("Thread");
                case FeedKind.UNIFIED: return _("All Accounts");
                case FeedKind.DRAFTS: return _("Drafts");
                case FeedKind.SCHEDULED: return _("Scheduled");
                case FeedKind.FILTERS: return _("Filters and Mutes");
                default: return _("Search");
            }
        }

        public string? stream () {
            switch (kind) {
                case FeedKind.LOCAL: return "public:local";
                case FeedKind.FEDERATED: return "public";
                case FeedKind.HASHTAG: return "hashtag";
                default: return null;
            }
        }

        public bool live () {
            return kind == FeedKind.HOME || kind == FeedKind.NOTIFICATIONS || stream () != null;
        }

        public string path () {
            switch (kind) {
                case FeedKind.HOME: return "/api/v1/timelines/home";
                case FeedKind.LOCAL:
                case FeedKind.FEDERATED: return "/api/v1/timelines/public";
                case FeedKind.NOTIFICATIONS: return "/api/v1/notifications";
                case FeedKind.BOOKMARKS: return "/api/v1/bookmarks";
                case FeedKind.FAVOURITES: return "/api/v1/favourites";
                case FeedKind.HASHTAG: return "/api/v1/timelines/tag/" + Uri.escape_string (arg, null, false);
                case FeedKind.PROFILE: return "/api/v1/accounts/%s/statuses".printf (account != null ? account.id : arg);
                default: return "";
            }
        }

        public Params query () {
            var p = new Params ();
            if (kind == FeedKind.LOCAL) p.add ("local", "true");
            p.add ("limit", kind == FeedKind.NOTIFICATIONS ? "30" : "40");
            return p;
        }

        public bool id_paged () {
            return kind != FeedKind.BOOKMARKS && kind != FeedKind.FAVOURITES && kind != FeedKind.THREAD && kind != FeedKind.SEARCH;
        }

        public string context () {
            switch (kind) {
                case FeedKind.HOME:
                case FeedKind.UNIFIED: return "home";
                case FeedKind.NOTIFICATIONS: return "notifications";
                case FeedKind.LOCAL:
                case FeedKind.FEDERATED:
                case FeedKind.HASHTAG:
                case FeedKind.SEARCH: return "public";
                case FeedKind.THREAD: return "thread";
                case FeedKind.PROFILE: return "account";
                default: return "";
            }
        }

        public bool local_list () {
            return kind == FeedKind.DRAFTS || kind == FeedKind.SCHEDULED;
        }

        public static string item_id (Object o) {
            if (o is Status && ((Status) o).merged) return "u:" + ((Status) o).merge_key ();
            if (o is Draft) return "draft:" + ((Draft) o).id;
            if (o is ScheduledStatus) return "scheduled:" + ((ScheduledStatus) o).id;
            if (o is Status) return ((Status) o).id;
            if (o is Notice) return ((Notice) o).id;
            if (o is Account) return "account:" + ((Account) o).id;
            if (o is TagItem) return "tag:" + ((TagItem) o).name;
            return "";
        }

        public Gee.ArrayList<Object> parse (Json.Node? root) {
            var list = new Gee.ArrayList<Object> ();
            if (kind == FeedKind.NOTIFICATIONS) {
                foreach (var n in Notice.parse_list (root)) list.add (n);
            } else {
                foreach (var s in Status.parse_list (root)) list.add (s);
            }
            return list;
        }

        public async Gee.ArrayList<Object> fetch (Session s, string? page_url, Cancellable? cancel, out string? next) throws Error {
            next = null;
            var list = new Gee.ArrayList<Object> ();
            if (kind == FeedKind.DRAFTS) {
                if (drafts != null) list.add_all (drafts.for_account (s.saved.key ()));
                return list;
            }
            if (kind == FeedKind.SCHEDULED) {
                list.add_all (yield s.client.scheduled (cancel));
                return list;
            }
            if (kind == FeedKind.FILTERS) return list;
            if (kind == FeedKind.UNIFIED) {
                string? more;
                list.add_all (yield fetch_unified (s, page_url != null, cancel, out more));
                next = more;
                return list;
            }
            if (kind == FeedKind.THREAD) {
                var fresh = yield s.client.status (focus.id);
                focus = fresh;
                var ctx = yield s.client.context (fresh.id);
                list.add_all (ctx.ancestors);
                list.add (fresh);
                list.add_all (ctx.descendants);
                return list;
            }
            if (kind == FeedKind.SEARCH) {
                var r = yield s.client.search (arg, true, cancel);
                foreach (var t in r.hashtags) list.add (new TagItem (t));
                list.add_all (r.accounts);
                list.add_all (r.statuses);
                return list;
            }
            string? link;
            Json.Node? root;
            if (page_url != null) root = yield s.client.call ("GET", page_url, null, cancel, out link);
            else root = yield s.client.call ("GET", path (), query (), cancel, out link);
            list = parse (root);
            if (list.size == 0) return list;
            next = link;
            if (next == null && id_paged ()) {
                var p = query ();
                p.add ("max_id", item_id (list[list.size - 1]));
                next = s.client.url_for (path ()) + "?" + p.encode ();
            }
            return list;
        }

        private async Gee.ArrayList<Status> fetch_unified (Session primary, bool older, Cancellable? cancel, out string? more) throws Error {
            more = null;
            if (!older) {
                cursors.clear ();
                exhausted.clear ();
            }
            var all = sessions ?? new Gee.ArrayList<Session> ();
            if (all.size == 0) all.add (primary);
            var sources = new Gee.ArrayList<Gee.List<Status>> ();
            Error? first_error = null;
            int ok = 0;
            foreach (var sess in all) {
                string key = sess.saved.key ();
                if (older && (exhausted.contains (key) || !cursors.has_key (key))) continue;
                var p = new Params ().add ("limit", "20");
                if (older) p.add ("max_id", cursors[key]);
                try {
                    var got = Status.parse_list (yield sess.client.call ("GET", "/api/v1/timelines/home", p, cancel));
                    ok++;
                    if (got.size == 0) {
                        exhausted.add (key);
                        continue;
                    }
                    cursors[key] = got[got.size - 1].id;
                    foreach (var st in got) {
                        st.tag_via (key);
                        if (sess != primary) forget_local_ids (st);
                    }
                    sources.add (got);
                } catch (IOError.CANCELLED e) {
                    throw e;
                } catch (Error e) {
                    if (first_error == null) first_error = e;
                    exhausted.add (key);
                }
            }
            if (ok == 0 && first_error != null) throw first_error;
            foreach (var sess in all) {
                if (cursors.has_key (sess.saved.key ()) && !exhausted.contains (sess.saved.key ())) more = MORE;
            }
            return Merge.timelines (sources);
        }

        private static void forget_local_ids (Status st) {
            foreach (var m in st.mentions) m.id = "";
            if (st.reblog != null) foreach (var m in st.reblog.mentions) m.id = "";
        }

        public async Gee.ArrayList<Object> fetch_newer (Session s, string first_id) throws Error {
            var p = query ();
            p.add ("min_id", first_id);
            return parse (yield s.client.call ("GET", path (), p));
        }
    }

    public class TimelineView : Page {
        public const int MAX_ITEMS = 800;

        private Navigator nav;
        private Session session;
        private Stack stack;
        private ListBox list;
        private ScrolledWindow scroll;
        private StatusPage error_page;
        private Widget empty_page;
        private Box footer;
        private Spinner footer_spin;
        private Label footer_label;
        private Button footer_retry;
        private Button new_pill;
        private Widget? header;
        private string? next;
        private bool loading;
        private bool loaded_once;
        private int serial;
        private int count;
        private Gee.HashSet<string> ids = new Gee.HashSet<string> ();
        private Gee.ArrayList<Object> waiting = new Gee.ArrayList<Object> ();
        private Cancellable? cancel;

        public TimelineView (Feed feed, Navigator nav, Session session, Widget? header = null) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.feed = feed;
            this.nav = nav;
            this.session = session;
            this.header = header;
            var overlay = new Overlay ();
            overlay.vexpand = true;
            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;

            var spin = new Spinner ();
            spin.spinning = true;
            spin.set_size_request (32, 32);
            spin.halign = Align.CENTER;
            spin.valign = Align.CENTER;
            stack.add_named (spin, "loading");

            error_page = new StatusPage ();
            error_page.icon_name = "network-error";
            error_page.title = _("Could Not Load");
            var retry = new Button.with_label (_("Try Again"));
            retry.add_css_class ("pill");
            retry.add_css_class ("suggested-action");
            retry.clicked.connect (() => reload ());
            error_page.child = retry;
            stack.add_named (error_page, "error");

            empty_page = build_empty ();
            stack.add_named (empty_page, "empty");

            var column = new Box (Orientation.VERTICAL, 0);
            column.add_css_class ("fedi-column");
            if (header != null) column.append (header);
            list = new ListBox ();
            list.add_css_class ("fedi-list");
            list.selection_mode = SelectionMode.NONE;
            list.activate_on_single_click = false;
            list.row_activated.connect ((row) => activate_item (row.get_data<Object> ("item")));
            column.append (list);
            footer = new Box (Orientation.VERTICAL, 8);
            footer.add_css_class ("fedi-footer");
            footer_spin = new Spinner ();
            footer_spin.halign = Align.CENTER;
            footer.append (footer_spin);
            footer_label = Ui.dim ("", false);
            footer_label.halign = Align.CENTER;
            footer_label.wrap = true;
            footer_label.justify = Justification.CENTER;
            footer.append (footer_label);
            footer_retry = new Button.with_label (_("Try Again"));
            footer_retry.add_css_class ("pill");
            footer_retry.halign = Align.CENTER;
            footer_retry.clicked.connect (() => load_more ());
            footer.append (footer_retry);
            column.append (footer);

            var limit = new Clamp (column, 720);
            scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.child = limit;
            apply_view_edge (scroll);
            scroll.vadjustment.value_changed.connect (check_bottom);
            scroll.edge_reached.connect ((pos) => {
                if (pos == PositionType.BOTTOM) load_more ();
                if (pos == PositionType.TOP) flush_waiting ();
            });
            stack.add_named (scroll, "list");
            overlay.child = stack;

            new_pill = new Button.with_label ("");
            new_pill.add_css_class ("pill");
            new_pill.add_css_class ("suggested-action");
            new_pill.add_css_class ("fedi-new-pill");
            new_pill.halign = Align.CENTER;
            new_pill.valign = Align.START;
            new_pill.margin_top = 64;
            new_pill.visible = false;
            new_pill.clicked.connect (() => {
                flush_waiting ();
                scroll.vadjustment.value = 0;
            });
            overlay.add_overlay (new_pill);
            append (overlay);
            reload ();
        }

        private Widget build_empty () {
            if (feed.kind == FeedKind.SEARCH) {
                var none = new StatusPage ();
                none.icon_name = "system-search";
                none.title = empty_title ();
                none.description = empty_description ();
                var again = new Button.with_label (_("Search Again"));
                again.halign = Align.CENTER;
                again.add_css_class ("pill");
                again.add_css_class ("suggested-action");
                again.clicked.connect (() => activate_action ("win.find", null));
                none.child = again;
                return none;
            }
            var page = new WelcomePage ();
            page.is_section = true;
            page.app_icon_name = empty_icon ();
            page.title = empty_title ();
            page.subtitle = empty_description ();
            switch (feed.kind) {
                case FeedKind.HOME:
                case FeedKind.UNIFIED:
                    add_empty_action (page, "write");
                    add_empty_action (page, "federated");
                    add_empty_action (page, "people");
                    add_empty_action (page, "refresh");
                    break;
                case FeedKind.LOCAL:
                    add_empty_action (page, "write");
                    add_empty_action (page, "federated");
                    add_empty_action (page, "refresh");
                    break;
                case FeedKind.FEDERATED:
                    add_empty_action (page, "write");
                    add_empty_action (page, "people");
                    add_empty_action (page, "refresh");
                    break;
                case FeedKind.NOTIFICATIONS:
                    add_empty_action (page, "write");
                    add_empty_action (page, "people");
                    add_empty_action (page, "refresh");
                    break;
                case FeedKind.BOOKMARKS:
                case FeedKind.FAVOURITES:
                    add_empty_action (page, "home");
                    add_empty_action (page, "federated");
                    add_empty_action (page, "refresh");
                    break;
                case FeedKind.DRAFTS:
                case FeedKind.SCHEDULED:
                    add_empty_action (page, "write");
                    break;
                default:
                    add_empty_action (page, "write");
                    add_empty_action (page, "refresh");
                    break;
            }
            return page;
        }

        private void add_empty_action (WelcomePage page, string what) {
            switch (what) {
                case "write":
                    page.add_action ("document-new", _("Write a Post"), _("Share something with your followers"), () => activate_action ("win.new-post", null));
                    break;
                case "federated":
                    page.add_action ("network-workgroup", _("Explore the Federated Timeline"), _("See public posts from across the network"), () => activate_action ("win.federated", null));
                    break;
                case "home":
                    page.add_action ("user-home", _("Go to Home"), _("Read the posts of the people you follow"), () => activate_action ("win.home", null));
                    break;
                case "people":
                    page.add_action ("avatar-default", _("Find People"), _("Search for accounts and hashtags to follow"), () => activate_action ("win.find", null));
                    break;
                case "refresh":
                    page.add_action ("emblem-synchronizing", _("Refresh"), _("Check for new posts now"), () => reload ());
                    break;
            }
        }

        private string empty_icon () {
            switch (feed.kind) {
                case FeedKind.BOOKMARKS: return "user-bookmarks";
                case FeedKind.DRAFTS:
                case FeedKind.SCHEDULED: return "x-office-document";
                default: return "dev.sinty.fediverse";
            }
        }

        private string empty_title () {
            switch (feed.kind) {
                case FeedKind.NOTIFICATIONS: return _("No Notifications");
                case FeedKind.BOOKMARKS: return _("No Bookmarks");
                case FeedKind.FAVOURITES: return _("No Favourites");
                case FeedKind.SEARCH: return _("No Results");
                case FeedKind.DRAFTS: return _("No Drafts");
                case FeedKind.SCHEDULED: return _("Nothing Scheduled");
                default: return _("Nothing Here Yet");
            }
        }

        private string empty_description () {
            switch (feed.kind) {
                case FeedKind.HOME: return _("Follow people and hashtags and their posts appear here.");
                case FeedKind.LOCAL: return _("Public posts from people on your server appear here.");
                case FeedKind.FEDERATED: return _("Public posts from the servers yours is connected to appear here.");
                case FeedKind.NOTIFICATIONS: return _("Mentions, boosts, favourites and new followers appear here.");
                case FeedKind.BOOKMARKS: return _("Bookmark posts to read them later.");
                case FeedKind.FAVOURITES: return _("Posts you favourite appear here.");
                case FeedKind.SEARCH: return _("Try a full address like @name@server, a hashtag or other words.");
                case FeedKind.HASHTAG: return _("No one has used this hashtag lately.");
                case FeedKind.UNIFIED: return _("Posts from the home timelines of all your accounts appear here.");
                case FeedKind.DRAFTS: return _("Posts you start writing are kept here until you publish them.");
                case FeedKind.SCHEDULED: return _("Choose a date and time while writing a post to publish it later.");
                default: return _("There are no posts to show.");
            }
        }

        public override void reload () {
            if (cancel != null) cancel.cancel ();
            cancel = new Cancellable ();
            int my = ++serial;
            loading = true;
            if (!loaded_once) stack.visible_child_name = "loading";
            footer_retry.visible = false;
            footer_label.visible = false;
            feed.fetch.begin (session, null, cancel, (o, res) => {
                if (my != serial) return;
                loading = false;
                try {
                    string? n;
                    var items = feed.fetch.end (res, out n);
                    next = n;
                    clear ();
                    loaded_once = true;
                    append_items (items);
                    if (items.size == 0 && header == null) {
                        stack.visible_child_name = "empty";
                        return;
                    }
                    stack.visible_child_name = "list";
                    update_footer (null);
                    if (feed.kind == FeedKind.THREAD) scroll_to_focus ();
                    Idle.add (() => {
                        check_bottom ();
                        return Source.REMOVE;
                    });
                } catch (IOError.CANCELLED e) {
                } catch (Error e) {
                    if (e is ApiError.UNAUTHORIZED) {
                        nav.signed_out ();
                        return;
                    }
                    if (loaded_once && list.get_first_child () != null) {
                        nav.show_error (_("Could not refresh: %s").printf (e.message));
                        return;
                    }
                    error_page.description = describe (e);
                    stack.visible_child_name = "error";
                }
            });
        }

        public static string describe (Error e) {
            if (e is ResolverError || e is IOError.NETWORK_UNREACHABLE || e is IOError.HOST_UNREACHABLE || e is IOError.TIMED_OUT || e is IOError.CONNECTION_REFUSED) {
                return _("The server cannot be reached. Check your internet connection. (%s)").printf (e.message);
            }
            if (e is TlsError) return _("The secure connection to the server failed: %s").printf (e.message);
            return e.message;
        }

        private void clear () {
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            ids.clear ();
            waiting.clear ();
            new_pill.visible = false;
            count = 0;
        }

        private void check_bottom () {
            var adj = scroll.vadjustment;
            if (adj.upper - (adj.value + adj.page_size) < 900) load_more ();
        }

        public void load_more () {
            if (loading || next == null || count >= MAX_ITEMS || !loaded_once) return;
            loading = true;
            int my = serial;
            update_footer (null);
            feed.fetch.begin (session, next, cancel, (o, res) => {
                if (my != serial) return;
                loading = false;
                try {
                    string? n;
                    var items = feed.fetch.end (res, out n);
                    next = n;
                    append_items (items);
                    update_footer (null);
                    Idle.add (() => {
                        check_bottom ();
                        return Source.REMOVE;
                    });
                } catch (IOError.CANCELLED e) {
                } catch (Error e) {
                    update_footer (describe (e));
                }
            });
        }

        private void update_footer (string? error) {
            footer_spin.spinning = loading;
            footer_spin.visible = loading;
            footer_retry.visible = error != null;
            if (error != null) {
                footer_label.label = _("More posts could not be loaded: %s").printf (error);
            } else if (count >= MAX_ITEMS) {
                footer_label.label = _("That is a lot of posts. Refresh to start again from the newest.");
            } else if (next == null && !loading && count > 0 && feed.kind != FeedKind.THREAD && feed.kind != FeedKind.SEARCH && !feed.local_list ()) {
                footer_label.label = _("You have reached the end.");
            } else if (next == null && !loading && count == 0) {
                footer_label.label = _("There are no posts to show.");
            } else {
                footer_label.label = "";
            }
            footer_label.visible = footer_label.label != "";
        }

        private ListBoxRow? row_for (Object o) {
            Widget w;
            string titles = "";
            if (o is Status) {
                bool focused = feed.kind == FeedKind.THREAD && feed.focus != null && ((Status) o).id == feed.focus.id;
                var verdict = focused ? FilterVerdict.SHOW : Filters.verdict ((Status) o, feed.context (), out titles);
                if (verdict == FilterVerdict.HIDE) return null;
                w = new StatusView ((Status) o, nav, focused, false, verdict == FilterVerdict.WARN ? titles : "");
            } else if (o is Notice) {
                var n = (Notice) o;
                if (n.status != null && Filters.verdict (n.status, feed.context (), out titles) == FilterVerdict.HIDE) return null;
                w = new NotificationView (n, nav);
            } else if (o is Draft) {
                w = new DraftView ((Draft) o, nav);
            } else if (o is ScheduledStatus) {
                w = new ScheduledView ((ScheduledStatus) o, nav);
            } else if (o is Account) {
                w = new AccountView ((Account) o, nav);
            } else if (o is TagItem) {
                var b = new Box (Orientation.HORIZONTAL, 12);
                b.add_css_class ("fedi-account-row");
                var l = new Label ("#" + ((TagItem) o).name);
                l.add_css_class ("heading");
                l.xalign = 0;
                b.append (l);
                w = b;
            } else {
                return null;
            }
            var row = new ListBoxRow ();
            row.child = w;
            row.set_data<Object> ("item", o);
            row.set_data<string> ("id", Feed.item_id (o));
            return row;
        }

        private void tag (Object o) {
            string key = session.saved.key ();
            if (o is Status) ((Status) o).tag_via (key);
            else if (o is Notice && ((Notice) o).status != null) ((Notice) o).status.tag_via (key);
        }

        private void append_items (Gee.List<Object> items) {
            foreach (var o in items) {
                tag (o);
                string id = Feed.item_id (o);
                if (id != "" && ids.contains (id)) continue;
                var row = row_for (o);
                if (row == null) continue;
                ids.add (id);
                list.append (row);
                count++;
            }
        }

        public override void add_new (Gee.List<Object> items) {
            if (!loaded_once || items.size == 0) return;
            foreach (var o in items) {
                string id = Feed.item_id (o);
                if (ids.contains (id)) continue;
                bool dup = false;
                foreach (var w in waiting) if (Feed.item_id (w) == id) dup = true;
                if (!dup) waiting.add (o);
            }
            if (waiting.size == 0) return;
            if (stack.visible_child_name != "list") {
                flush_waiting ();
                stack.visible_child_name = "list";
                update_footer (null);
                return;
            }
            if (scroll.vadjustment.value < 40) {
                flush_waiting ();
                return;
            }
            new_pill.label = ngettext ("%d New Post", "%d New Posts", waiting.size).printf (waiting.size);
            if (feed.kind == FeedKind.NOTIFICATIONS) new_pill.label = ngettext ("%d New Notification", "%d New Notifications", waiting.size).printf (waiting.size);
            new_pill.visible = true;
        }

        private void flush_waiting () {
            new_pill.visible = false;
            if (waiting.size == 0) return;
            waiting.sort ((a, b) => compare_ids (Feed.item_id (a), Feed.item_id (b)));
            foreach (var o in waiting) {
                tag (o);
                string id = Feed.item_id (o);
                if (ids.contains (id)) continue;
                var row = row_for (o);
                if (row == null) continue;
                ids.add (id);
                list.prepend (row);
                count++;
            }
            waiting.clear ();
        }

        public static int compare_ids (string a, string b) {
            if (a.length != b.length) return a.length < b.length ? -1 : 1;
            return strcmp (a, b);
        }

        public string? first_id () {
            string? best = null;
            for (var c = list.get_first_child (); c != null; c = c.get_next_sibling ()) {
                string? id = c.get_data<string> ("id");
                if (id == null || id.has_prefix ("account:") || id.has_prefix ("tag:") || id.has_prefix ("u:") || id.has_prefix ("draft:") || id.has_prefix ("scheduled:")) continue;
                if (best == null || compare_ids (id, best) > 0) best = id;
            }
            foreach (var w in waiting) {
                string id = Feed.item_id (w);
                if (id.has_prefix ("u:")) continue;
                if (best == null || compare_ids (id, best) > 0) best = id;
            }
            return best;
        }

        public override async void poll_newer () {
            if (!feed.live () || !loaded_once || loading) return;
            string? first = first_id ();
            if (first == null) {
                reload ();
                return;
            }
            try {
                add_new (yield feed.fetch_newer (session, first));
            } catch (Error e) {
            }
        }

        public override void remove_status (string id) {
            ids.remove (id);
            var it = waiting.iterator ();
            while (it.next ()) {
                var o = it.get ();
                if (o is Status && (((Status) o).id == id || ((Status) o).shown ().id == id)) it.remove ();
            }
            Widget? c = list.get_first_child ();
            while (c != null) {
                var next_c = c.get_next_sibling ();
                var o = c.get_data<Object> ("item");
                Status? s = null;
                if (o is Status) s = (Status) o;
                else if (o is Notice) s = ((Notice) o).status;
                if (s != null && (s.id == id || s.shown ().id == id)) {
                    list.remove (c);
                    count--;
                }
                c = next_c;
            }
            if (count <= 0 && header == null && loaded_once) stack.visible_child_name = "empty";
        }

        public override void replace_status (Status fresh) {
            for (var c = list.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var o = c.get_data<Object> ("item");
                if (o is Status && ((Status) o).id == fresh.id) {
                    var row = (ListBoxRow) c;
                    fresh.tag_via (((Status) o).via);
                    fresh.merged = ((Status) o).merged;
                    row.set_data<Object> ("item", fresh);
                    bool focused = feed.kind == FeedKind.THREAD && feed.focus != null && fresh.id == feed.focus.id;
                    row.child = new StatusView (fresh, nav, focused);
                }
            }
        }

        private void activate_item (Object? o) {
            if (o == null) return;
            if (o is Status) nav.open_status ((Status) o);
            else if (o is Notice) {
                var n = (Notice) o;
                if (n.status != null) nav.open_status (n.status);
                else nav.open_account (n.account);
            } else if (o is Account) nav.open_account ((Account) o);
            else if (o is TagItem) nav.open_tag (((TagItem) o).name);
            else if (o is Draft) nav.open_draft ((Draft) o);
            else if (o is ScheduledStatus) nav.edit_scheduled ((ScheduledStatus) o);
        }

        private void scroll_to_focus () {
            Idle.add (() => {
                for (var c = list.get_first_child (); c != null; c = c.get_next_sibling ()) {
                    var o = c.get_data<Object> ("item");
                    if (o is Status && feed.focus != null && ((Status) o).id == feed.focus.id) {
                        Graphene.Point p;
                        if (c.compute_point (scroll.child, { 0, 0 }, out p)) scroll.vadjustment.value = double.max (0, p.y - 12);
                        c.grab_focus ();
                        break;
                    }
                }
                return Source.REMOVE;
            });
        }

        public override void focus_list () {
            var first = list.get_row_at_index (0);
            if (first != null) first.grab_focus ();
        }
    }
}
