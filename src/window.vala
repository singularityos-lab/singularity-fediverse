using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Fediverse {

    public class FediverseWindow : Singularity.Widgets.Window, Navigator {
        private class PendingLogin {
            public string instance;
            public RegisteredClient client;
            public string state;
        }

        private FediverseApp app;
        private AccountStore store;
        private Session? _session;
        private Stack main_stack;
        private Stack pages;
        private Gee.ArrayList<Page> history = new Gee.ArrayList<Page> ();
        private Gee.HashMap<string, Session> sessions = new Gee.HashMap<string, Session> ();
        private int page_serial;
        private AppSidebar sidebar;
        private Box sidebar_box;
        private Gee.HashMap<FeedKind, SidebarRow> nav_rows = new Gee.HashMap<FeedKind, SidebarRow> ();
        private StatusPage login_page;
        private Button login_again;
        private Button login_code;
        private StatusPage signed_out_page;
        private Button back_bubble;
        private Button refresh_bubble;
        private Button compose_bubble;
        private SearchBubble search;
        private Overlay overlay;
        private Singularity.Widgets.Toast? last_toast = null;
        private PendingLogin? pending;
        private Stream? user_stream;
        private Stream? view_stream;
        private string view_stream_key = "";
        private uint poll_id;
        private uint reconnect_id;
        private int activation;
        private bool pending_compose;
        private string[] shared_uris = {};
        private string shared_text = "";

        public Session? session {
            get { return _session; }
        }

        public FediverseWindow (FediverseApp app) {
            Object (application: app);
            this.app = app;
            store = app.store;
            set_default_size (1100, 820);
            set_title (_("Fediverse"));

            sidebar = new AppSidebar (230);
            sidebar_box = new Box (Orientation.VERTICAL, 2);
            sidebar_box.valign = Align.START;
            sidebar.box.append (sidebar_box);
            set_sidebar (sidebar);

            back_bubble = add_bubble_icon ("go-previous-symbolic", _("Back (Alt+Left)"), () => go_back ());
            search = add_bubble_search (_("Search the Fediverse"), (t) => { });
            search.entry.activate.connect (() => run_search (search.text));
            search.entry.input_hints = InputHints.NO_SPELLCHECK;
            refresh_bubble = add_bubble_icon ("view-refresh-symbolic", _("Refresh (Ctrl+R)"), () => refresh ());
            compose_bubble = add_bubble_icon ("document-edit-symbolic", _("New Post (Ctrl+N)"), () => compose (null));

            main_stack = new Stack ();
            main_stack.transition_type = StackTransitionType.CROSSFADE;

            var welcome = new WelcomePage ();
            welcome.app_icon_name = "dev.sinty.fediverse";
            welcome.title = _("Fediverse");
            welcome.subtitle = _("Follow people on Mastodon, GoToSocial, Akkoma and other servers of the social web, all from one place.");
            welcome.add_action ("avatar-default", _("Add Account"), _("Sign in with an account on any server"), () => add_account ());
            welcome.add_action ("network-workgroup", _("Join a Server"), _("Find a server and create an account"), () => open_link ("https://joinmastodon.org/servers"));
            main_stack.add_named (welcome, "welcome");

            login_page = new StatusPage ();
            login_page.icon_name = "dev.sinty.fediverse";
            var login_buttons = new Box (Orientation.VERTICAL, 10);
            login_buttons.halign = Align.CENTER;
            login_again = new Button.with_label (_("Open the Browser Again"));
            login_again.add_css_class ("pill");
            login_again.add_css_class ("suggested-action");
            login_again.clicked.connect (() => {
                if (pending != null) open_link (Oauth.authorize_url (pending.instance, pending.client.client_id, Oauth.REDIRECT, pending.state));
            });
            login_buttons.append (login_again);
            login_code = new Button.with_label (_("Enter a Code Instead"));
            login_code.add_css_class ("pill");
            login_code.clicked.connect (() => enter_code ());
            login_buttons.append (login_code);
            var login_cancel = new Button.with_label (_("Cancel"));
            login_cancel.add_css_class ("pill");
            login_cancel.clicked.connect (() => {
                forget_pending ();
                show_start ();
            });
            login_buttons.append (login_cancel);
            login_page.child = login_buttons;
            main_stack.add_named (login_page, "login");

            signed_out_page = new StatusPage ();
            signed_out_page.icon_name = "dev.sinty.fediverse";
            signed_out_page.title = _("Signed Out");
            var so_buttons = new Box (Orientation.VERTICAL, 10);
            so_buttons.halign = Align.CENTER;
            var sign_in = new Button.with_label (_("Sign In Again"));
            sign_in.add_css_class ("pill");
            sign_in.add_css_class ("suggested-action");
            sign_in.clicked.connect (() => {
                var a = store.active ();
                if (a != null) start_login.begin (a.instance);
            });
            so_buttons.append (sign_in);
            var remove_btn = new Button.with_label (_("Remove Account"));
            remove_btn.add_css_class ("pill");
            remove_btn.clicked.connect (() => {
                var a = store.active ();
                if (a != null) confirm_remove (a);
            });
            so_buttons.append (remove_btn);
            signed_out_page.child = so_buttons;
            main_stack.add_named (signed_out_page, "signed-out");

            var loading = new Spinner ();
            loading.spinning = true;
            loading.set_size_request (32, 32);
            loading.halign = Align.CENTER;
            loading.valign = Align.CENTER;
            main_stack.add_named (loading, "loading");

            pages = new Stack ();
            pages.transition_type = StackTransitionType.SLIDE_LEFT_RIGHT;
            pages.transition_duration = 180;
            main_stack.add_named (pages, "main");

            overlay = new Overlay ();
            overlay.child = main_stack;
            set_content (overlay);

            install_actions ();
            sync_actions ();
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                bool alt = (state & Gdk.ModifierType.ALT_MASK) != 0;
                if ((alt && keyval == Gdk.Key.Left) || keyval == Gdk.Key.Back) {
                    go_back ();
                    return true;
                }
                if (keyval == Gdk.Key.Escape && history.size > 1 && !search.entry.has_focus) {
                    go_back ();
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);
            close_request.connect (() => {
                stop_live ();
                return false;
            });
            store.changed.connect (fill_sidebar);
            store.changed.connect (sync_actions);
            app.drafts.changed.connect (() => {
                foreach (var v in history) if (v.feed.kind == FeedKind.DRAFTS) v.reload ();
                fill_sidebar ();
            });
            show_start ();
        }

        private void install_actions () {
            string[] names = { "new-post", "add-account", "find", "back", "refresh", "home", "local", "federated", "notifications", "bookmarks", "favourites", "profile", "unified", "drafts", "scheduled", "filters", "remove-account", "close" };
            foreach (string n in names) {
                var a = new SimpleAction (n, null);
                string name = n;
                a.activate.connect (() => run_action (name));
                add_action (a);
            }
        }

        private void run_action (string name) {
            bool ready = _session != null && main_stack.visible_child_name == "main";
            switch (name) {
                case "new-post":
                    if (ready) compose (null);
                    break;
                case "add-account":
                    add_account ();
                    break;
                case "find":
                    if (ready) search.grab_focus_entry ();
                    break;
                case "back":
                    go_back ();
                    break;
                case "refresh":
                    refresh ();
                    break;
                case "home":
                    if (ready) show_root (new Feed (FeedKind.HOME));
                    break;
                case "local":
                    if (ready) show_root (new Feed (FeedKind.LOCAL));
                    break;
                case "federated":
                    if (ready) show_root (new Feed (FeedKind.FEDERATED));
                    break;
                case "notifications":
                    if (ready) show_root (new Feed (FeedKind.NOTIFICATIONS));
                    break;
                case "bookmarks":
                    if (ready) show_root (new Feed (FeedKind.BOOKMARKS));
                    break;
                case "favourites":
                    if (ready) show_root (new Feed (FeedKind.FAVOURITES));
                    break;
                case "profile":
                    if (ready && _session.me != null) open_account (_session.me);
                    break;
                case "unified":
                    if (ready && store.items.size > 1) show_root (new Feed (FeedKind.UNIFIED));
                    break;
                case "drafts":
                    if (ready) show_root (new Feed (FeedKind.DRAFTS));
                    break;
                case "scheduled":
                    if (ready) show_root (new Feed (FeedKind.SCHEDULED));
                    break;
                case "filters":
                    if (ready) show_root (new Feed (FeedKind.FILTERS));
                    break;
                case "remove-account":
                    var active = store.active ();
                    if (active != null) confirm_remove (active);
                    break;
                case "close":
                    close ();
                    break;
            }
        }

        private void sync_actions () {
            bool ready = _session != null && main_stack.visible_child_name == "main";
            string[] session_actions = { "new-post", "find", "refresh", "home", "local", "federated", "notifications", "bookmarks", "favourites", "drafts", "scheduled", "filters" };
            foreach (string n in session_actions) ((SimpleAction) lookup_action (n)).set_enabled (ready);
            ((SimpleAction) lookup_action ("profile")).set_enabled (ready && _session.me != null);
            ((SimpleAction) lookup_action ("unified")).set_enabled (ready && store.items.size > 1);
            ((SimpleAction) lookup_action ("back")).set_enabled (history.size > 1);
            ((SimpleAction) lookup_action ("remove-account")).set_enabled (store.active () != null);
        }

        private void set_chrome (bool main) {
            search.visible = main;
            refresh_bubble.visible = main;
            compose_bubble.visible = main;
            back_bubble.visible = main && history.size > 1;
            set_sidebar_visible (main || store.items.size > 0);
            sync_actions ();
        }

        public void show_start () {
            stop_live ();
            fill_sidebar ();
            var a = store.active ();
            if (a == null) {
                _session = null;
                main_stack.visible_child_name = "welcome";
                set_chrome (false);
                set_sidebar_visible (false);
                return;
            }
            activate_account.begin (a);
        }

        private async void activate_account (SavedAccount a) {
            int my = ++activation;
            stop_live ();
            clear_pages ();
            _session = null;
            store.current = a.key ();
            main_stack.visible_child_name = "loading";
            set_chrome (false);
            fill_sidebar ();
            string? token = yield AccountStore.lookup_token (a.key ());
            if (my != activation) return;
            if (token == null || token == "") {
                show_signed_out (a, _("The access token of %s is not in the keyring. Sign in again to keep using this account.").printf (a.handle ()));
                return;
            }
            var s = new Session (a, token);
            _session = s;
            sessions[a.key ()] = s;
            main_stack.visible_child_name = "main";
            set_chrome (true);
            show_root (new Feed (FeedKind.HOME));
            if (pending_compose) {
                pending_compose = false;
                compose (null);
            }
            s.client.instance_info.begin ((o, res) => {
                s.info = s.client.instance_info.end (res);
                if (_session == s) start_live ();
            });
            s.client.verify_credentials.begin ((o, res) => {
                try {
                    s.me = s.client.verify_credentials.end (res);
                    a.update_from (s.me);
                    store.put (a);
                } catch (ApiError.UNAUTHORIZED e) {
                    if (_session == s) show_signed_out (a, _("%s no longer accepts the sign-in of this app. Sign in again to keep using this account.").printf (s.host ()));
                } catch (Error e) {
                }
            });
        }

        private void show_signed_out (SavedAccount a, string message) {
            stop_live ();
            _session = null;
            signed_out_page.description = message;
            main_stack.visible_child_name = "signed-out";
            set_chrome (false);
            fill_sidebar ();
        }

        private void fill_sidebar () {
            Widget? c;
            while ((c = sidebar_box.get_first_child ()) != null) sidebar_box.remove (c);
            nav_rows.clear ();
            var a = store.active ();
            if (a == null) return;
            var acct_btn = new Button ();
            acct_btn.add_css_class ("flat");
            acct_btn.add_css_class ("fedi-account-switch");
            var ab = new Box (Orientation.HORIZONTAL, 10);
            ab.append (Ui.avatar (a.avatar, 32));
            var at = new Box (Orientation.VERTICAL, 0);
            at.hexpand = true;
            var an = new Label (a.name ());
            an.xalign = 0;
            an.ellipsize = Pango.EllipsizeMode.END;
            an.add_css_class ("heading");
            at.append (an);
            var ah = Ui.dim (a.handle ());
            ah.ellipsize = Pango.EllipsizeMode.END;
            at.append (ah);
            ab.append (at);
            ab.append (new Image.from_icon_name ("pan-down-symbolic"));
            acct_btn.child = ab;
            acct_btn.tooltip_text = _("Switch Account");
            acct_btn.clicked.connect (() => account_menu (acct_btn));
            sidebar_box.append (acct_btn);
            if (_session == null) return;
            sidebar_box.append (new SidebarSectionLabel (_("Timelines")));
            nav_row ("user-home-symbolic", _("Home"), FeedKind.HOME);
            if (store.items.size > 1) nav_row ("system-users-symbolic", _("All Accounts"), FeedKind.UNIFIED);
            nav_row ("mark-location-symbolic", _("Local"), FeedKind.LOCAL);
            nav_row ("network-workgroup-symbolic", _("Federated"), FeedKind.FEDERATED);
            sidebar_box.append (new SidebarSectionLabel (_("You")));
            nav_row ("preferences-system-notifications-symbolic", _("Notifications"), FeedKind.NOTIFICATIONS);
            nav_row ("user-bookmarks-symbolic", _("Bookmarks"), FeedKind.BOOKMARKS);
            nav_row ("starred-symbolic", _("Favourites"), FeedKind.FAVOURITES);
            var me = new SidebarRow ("avatar-default-symbolic", _("Profile"));
            me.clicked.connect (() => run_action ("profile"));
            sidebar_box.append (me);
            sidebar_box.append (new SidebarSectionLabel (_("Writing")));
            nav_row ("document-edit-symbolic", _("Drafts"), FeedKind.DRAFTS);
            int n = app.drafts.count (_session.saved.key ());
            if (n > 0) {
                var badge = new Label (n.to_string ());
                badge.add_css_class ("fedi-count");
                badge.add_css_class ("dim-label");
                var inner = nav_rows[FeedKind.DRAFTS].get_child () as Box;
                if (inner != null) inner.append (badge);
            }
            nav_row ("alarm-symbolic", _("Scheduled"), FeedKind.SCHEDULED);
            nav_row ("view-conceal-symbolic", _("Filters and Mutes"), FeedKind.FILTERS);
            highlight ();
        }

        private void nav_row (string icon, string label, FeedKind kind) {
            var row = new SidebarRow (icon, label);
            row.clicked.connect (() => show_root (new Feed (kind)));
            nav_rows[kind] = row;
            sidebar_box.append (row);
        }

        private void highlight () {
            bool single = history.size == 1;
            FeedKind current = single ? history[0].feed.kind : FeedKind.SEARCH;
            foreach (var e in nav_rows.entries) e.value.set_active (single && e.key == current);
            sync_actions ();
        }

        private void account_menu (Widget anchor) {
            var menu = new ContextMenu (anchor);
            menu.position = PositionType.BOTTOM;
            var active = store.active ();
            foreach (var a in store.items) {
                var acc = a;
                bool is_current = active != null && a.key () == active.key ();
                menu.add_item (a.handle (), is_current ? "object-select-symbolic" : "avatar-default-symbolic", () => {
                    if (!is_current) {
                        store.current = acc.key ();
                        store.save ();
                        activate_account.begin (acc);
                    }
                });
            }
            menu.add_separator ();
            menu.add_item (_("Add Account"), "list-add-symbolic", () => add_account ());
            if (active != null) menu.add_item (_("Remove %s").printf (active.handle ()), "user-trash-symbolic", () => confirm_remove (active), "destructive");
            Ui.popup_menu (menu);
        }

        private void confirm_remove (SavedAccount a) {
            var dlg = new ConfirmDialog (app, _("Remove %s?").printf (a.handle ()), "user-trash-symbolic",
                _("This app signs out of the account and forgets it. The account itself stays on its server."), _("Remove"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                AccountStore.lookup_token.begin (a.key (), (o, res) => {
                    string? token = AccountStore.lookup_token.end (res);
                    if (token != null && a.client_id != "") new Client (a.instance, token).revoke.begin (a.client_id, a.client_secret);
                    stop_live ();
                    _session = null;
                    sessions.unset (a.key ());
                    store.remove (a);
                    show_start ();
                });
            });
            dlg.present ();
        }

        public void add_account () {
            var dlg = new ConfirmDialog (app, _("Add Account"), null,
                _("Enter the server where your account lives, like mastodon.social, or your full address."), _("Continue"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            var group = new PreferencesGroup ();
            var row = new EntryRow (_("Server"));
            group.add_row (row);
            dlg.custom_area.append (group);
            var hint = Ui.dim ("", true);
            hint.wrap = true;
            hint.max_width_chars = 44;
            dlg.custom_area.append (hint);
            dlg.primary_sensitive = false;
            row.entry_changed.connect (() => {
                string? inst = Oauth.normalize_instance (row.text);
                dlg.primary_sensitive = inst != null;
                hint.label = row.text.strip () == "" ? "" : (inst == null ? _("This is not a server address.") : _("Signs in on %s.").printf (Oauth.host_of (inst) ?? inst));
            });
            row.entry_activated.connect (() => {
                if (Oauth.normalize_instance (row.text) == null) return;
                dlg.response (ConfirmDialog.Response.PRIMARY);
                dlg.close_dialog ();
            });
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                string? inst = Oauth.normalize_instance (row.text);
                if (inst != null) start_login.begin (inst);
            });
            dlg.present ();
            row.grab_focus ();
        }

        private async void start_login (string instance) {
            stop_live ();
            _session = null;
            set_chrome (false);
            set_sidebar_visible (false);
            string host = Oauth.host_of (instance) ?? instance;
            login_page.title = _("Contacting %s").printf (host);
            login_page.description = _("Registering this app on the server.");
            login_again.visible = false;
            login_code.visible = false;
            main_stack.visible_child_name = "login";
            RegisteredClient? rc = store.clients[instance];
            if (rc == null) {
                var client = new Client (instance);
                rc = new RegisteredClient ();
                rc.instance = instance;
                try {
                    string id, secret;
                    try {
                        yield client.register_app (true, out id, out secret);
                        rc.oob = true;
                    } catch (ApiError e) {
                        yield client.register_app (false, out id, out secret);
                        rc.oob = false;
                    }
                    rc.client_id = id;
                    rc.client_secret = secret;
                    store.clients[instance] = rc;
                    store.save ();
                } catch (Error e) {
                    login_failed (_("%s could not be reached or does not speak the Mastodon API: %s").printf (host, TimelineView.describe (e)));
                    return;
                }
            }
            pending = new PendingLogin ();
            pending.instance = instance;
            pending.client = rc;
            pending.state = Oauth.new_state ();
            store.pending_instance = instance;
            store.pending_state = pending.state;
            store.save ();
            login_page.title = _("Continue in Your Browser");
            login_page.description = _("Sign in to %s and allow Fediverse to use your account. You come back here on your own when it is done.").printf (host);
            login_again.visible = true;
            login_code.visible = rc.oob;
            open_link (Oauth.authorize_url (instance, rc.client_id, Oauth.REDIRECT, pending.state));
        }

        private void login_failed (string message) {
            var dlg = new ConfirmDialog.message (app, _("Could Not Sign In"), "dialog-error-symbolic", message);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.present ();
            forget_pending ();
            show_start ();
        }

        private void forget_pending () {
            pending = null;
            if (store.pending_state == "") return;
            store.pending_instance = "";
            store.pending_state = "";
            store.save ();
        }

        private void enter_code () {
            if (pending == null) return;
            var p = pending;
            open_link (Oauth.authorize_url (p.instance, p.client.client_id, Oauth.OOB, p.state));
            var dlg = new ConfirmDialog (app, _("Enter the Code"), null,
                _("After you allow access, the server shows a code. Copy it here."), _("Sign In"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            var group = new PreferencesGroup ();
            var row = new EntryRow (_("Authorization Code"));
            group.add_row (row);
            dlg.custom_area.append (group);
            dlg.primary_sensitive = false;
            row.entry_changed.connect (() => dlg.primary_sensitive = row.text.strip () != "");
            row.entry_activated.connect (() => {
                if (row.text.strip () == "") return;
                dlg.response (ConfirmDialog.Response.PRIMARY);
                dlg.close_dialog ();
            });
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY && pending == p) finish_login.begin (p, row.text.strip (), Oauth.OOB);
            });
            dlg.present ();
            row.grab_focus ();
        }

        public void handle_redirect (string uri) {
            string code, state, err;
            if (!Oauth.parse_redirect (uri, out code, out state, out err)) return;
            if (pending == null && store.pending_state != "" && store.clients.has_key (store.pending_instance)) {
                pending = new PendingLogin ();
                pending.instance = store.pending_instance;
                pending.client = store.clients[store.pending_instance];
                pending.state = store.pending_state;
            }
            if (pending == null) {
                show_toast (_("There is no sign-in waiting for this link."));
                return;
            }
            if (err != "") {
                login_failed (_("The server refused the sign-in: %s").printf (err));
                return;
            }
            if (state != pending.state) {
                show_toast (_("This sign-in link does not belong to the sign-in in progress."));
                return;
            }
            finish_login.begin (pending, code, Oauth.REDIRECT);
        }

        private async void finish_login (PendingLogin p, string code, string redirect) {
            login_page.title = _("Signing In");
            login_page.description = Oauth.host_of (p.instance) ?? p.instance;
            login_again.visible = false;
            login_code.visible = false;
            main_stack.visible_child_name = "login";
            var client = new Client (p.instance);
            try {
                client.token = yield client.exchange_code (p.client.client_id, p.client.client_secret, redirect, code);
                var me = yield client.verify_credentials ();
                var a = new SavedAccount ();
                a.instance = p.instance;
                a.client_id = p.client.client_id;
                a.client_secret = p.client.client_secret;
                a.update_from (me);
                try {
                    yield AccountStore.store_token (a, client.token);
                } catch (Error e) {
                    login_failed (_("The keyring is not available, so the sign-in cannot be kept: %s").printf (e.message));
                    return;
                }
                forget_pending ();
                store.current = a.key ();
                store.put (a);
                present ();
                yield activate_account (a);
            } catch (Error e) {
                login_failed (TimelineView.describe (e));
            }
        }

        private void clear_pages () {
            foreach (var v in history) pages.remove (v);
            history.clear ();
        }

        private void push (Page v) {
            string name = "page-%d".printf (++page_serial);
            pages.add_named (v, name);
            history.add (v);
            pages.visible_child = v;
            set_title (v.feed.title ());
            back_bubble.visible = history.size > 1;
            highlight ();
            update_view_stream ();
        }

        private void show_root (Feed f) {
            if (_session == null) return;
            if (f.kind == FeedKind.UNIFIED && f.sessions == null) {
                var s = _session;
                all_sessions.begin ((o, res) => {
                    f.sessions = all_sessions.end (res);
                    if (_session == s) show_root (f);
                });
                return;
            }
            if (f.kind == FeedKind.DRAFTS) f.drafts = app.drafts;
            if (f.kind == FeedKind.NOTIFICATIONS) app.unread.mark_read.begin (_session);
            var old = new Gee.ArrayList<Page> ();
            old.add_all (history);
            history.clear ();
            if (f.kind == FeedKind.FILTERS) push (new FiltersView (f, this, _session, app));
            else push (new TimelineView (f, this, _session));
            foreach (var v in old) pages.remove (v);
        }

        private async Gee.List<Session> all_sessions () {
            var list = new Gee.ArrayList<Session> ();
            foreach (var a in store.items) {
                Session? s = sessions[a.key ()];
                if (s == null) {
                    string? token = yield AccountStore.lookup_token (a.key ());
                    if (token == null || token == "") continue;
                    s = new Session (a, token);
                    sessions[a.key ()] = s;
                    var fresh = s;
                    fresh.client.instance_info.begin ((o, res) => fresh.info = fresh.client.instance_info.end (res));
                }
                list.add (s);
            }
            return list;
        }

        private void go_back () {
            if (history.size <= 1) return;
            var top = history.remove_at (history.size - 1);
            var prev = history[history.size - 1];
            pages.visible_child = prev;
            set_title (prev.feed.title ());
            back_bubble.visible = history.size > 1;
            Timeout.add (pages.transition_duration + 50, () => {
                pages.remove (top);
                return Source.REMOVE;
            });
            highlight ();
            update_view_stream ();
        }

        private Page? current_view () {
            return history.size > 0 ? history[history.size - 1] : null;
        }

        private void refresh () {
            var v = current_view ();
            if (v != null) v.reload ();
        }

        private void run_search (string text) {
            string q = text.strip ();
            if (q == "" || _session == null) return;
            if (q.has_prefix ("#") && !q.contains (" ") && q.length > 1) {
                open_tag (q.substring (1));
                return;
            }
            push (new TimelineView (new Feed (FeedKind.SEARCH, q), this, _session));
        }

        private void compose (Status? reply_to, Draft? draft = null, DateTime? schedule = null, Gee.List<string>? media = null) {
            if (_session == null) return;
            var sess = reply_to != null ? session_for (reply_to) : (draft != null ? session_by_key (draft.account) : _session);
            if (sess == null) sess = _session;
            var dlg = new ComposeDialog (app, sess, reply_to, app.drafts, draft, schedule);
            if (media != null) dlg.carry_media.add_all (media);
            if (reply_to == null && draft == null && (shared_uris.length > 0 || shared_text != "")) {
                dlg.add_shared (shared_uris, shared_text);
                shared_uris = {};
                shared_text = "";
            }
            dlg.transient_for = this;
            dlg.posted.connect ((s) => {
                show_toast (s.in_reply_to_id != "" ? _("Reply published") : _("Post published"));
                foreach (var v in history) {
                    if (v.feed.kind == FeedKind.HOME || (v.feed.kind == FeedKind.THREAD && s.in_reply_to_id != "")) {
                        var one = new Gee.ArrayList<Object> ();
                        one.add (s);
                        if (v.feed.kind == FeedKind.THREAD) v.reload ();
                        else v.add_new (one);
                    }
                    if (v.feed.kind == FeedKind.SCHEDULED) v.reload ();
                }
            });
            dlg.scheduled.connect ((sch) => {
                show_toast (_("Scheduled for %s").printf (Ui.moment (sch.scheduled_at)));
                foreach (var v in history) if (v.feed.kind == FeedKind.SCHEDULED) v.reload ();
            });
            dlg.present ();
        }

        private Session? session_by_key (string key) {
            if (_session != null && _session.saved.key () == key) return _session;
            return sessions[key];
        }

        public Session? session_for (Status s) {
            if (s.via != "") {
                var found = session_by_key (s.via);
                if (found != null) return found;
            }
            return _session;
        }

        public SavedAccount? saved_account (string key) {
            return store.find (key);
        }

        public void open_draft (Draft d) {
            compose (null, d);
        }

        public void delete_draft (Draft d) {
            var dlg = new ConfirmDialog (app, _("Delete This Draft?"), "user-trash-symbolic",
                _("The text is removed from this device."), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) app.drafts.remove (d.id);
            });
            dlg.present ();
        }

        public void edit_scheduled (ScheduledStatus sch) {
            if (_session == null) return;
            var d = new Draft ();
            d.account = _session.saved.key ();
            d.text = sch.text;
            d.spoiler_text = sch.spoiler_text;
            d.visibility = sch.visibility;
            d.sensitive = sch.sensitive;
            d.replaces_scheduled = sch.id;
            if (sch.in_reply_to_id != "") {
                d.reply_to_id = sch.in_reply_to_id;
                d.reply_to_handle = _("an earlier post");
            }
            var media = new Gee.ArrayList<string> ();
            media.add_all (sch.media_ids);
            if (media.size == 0) foreach (var m in sch.media) media.add (m.id);
            compose (null, d, sch.scheduled_at, media);
        }

        public void reschedule (ScheduledStatus sch) {
            if (_session == null) return;
            var s = _session;
            SchedulePicker.ask (app, this, sch.scheduled_at, (at) => {
                s.client.reschedule.begin (sch.id, at, (o, res) => {
                    try {
                        s.client.reschedule.end (res);
                        show_toast (_("Moved to %s").printf (Ui.moment (at)));
                        foreach (var v in history) if (v.feed.kind == FeedKind.SCHEDULED) v.reload ();
                    } catch (Error e) {
                        show_toast (_("The time was not changed: %s").printf (e.message));
                    }
                });
            });
        }

        public void cancel_scheduled (ScheduledStatus sch) {
            if (_session == null) return;
            var s = _session;
            var dlg = new ConfirmDialog (app, _("Delete Scheduled Post?"), "user-trash-symbolic",
                _("The server will not publish it, and its text is not kept."), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                s.client.cancel_scheduled.begin (sch.id, (o, res) => {
                    try {
                        s.client.cancel_scheduled.end (res);
                        show_toast (_("Scheduled post deleted"));
                        foreach (var v in history) if (v.feed.kind == FeedKind.SCHEDULED) v.reload ();
                    } catch (Error e) {
                        show_toast (_("The scheduled post was not deleted: %s").printf (e.message));
                    }
                });
            });
            dlg.present ();
        }

        public void moderate (Status status, string verb) {
            var sess = session_for (status);
            if (sess == null) return;
            var target = status.shown ().account;
            string who = "@" + target.acct;
            string domain = target.acct.contains ("@") ? target.acct.substring (target.acct.index_of_char ('@') + 1) : "";
            string title, body, button;
            switch (verb) {
                case "mute":
                    title = _("Mute %s?").printf (who);
                    body = _("Their posts and notifications stop showing up. They are not told.");
                    button = _("Mute");
                    break;
                case "block":
                    title = _("Block %s?").printf (who);
                    body = _("They can no longer follow you or see your posts, and you stop seeing theirs.");
                    button = _("Block");
                    break;
                default:
                    if (domain == "") return;
                    title = _("Block %s?").printf (domain);
                    body = _("You stop seeing posts and people from the whole server, and your followers there are removed.");
                    button = _("Block Server");
                    break;
            }
            var dlg = new ConfirmDialog (app, title, verb == "mute" ? null : "changes-prevent", body, button, ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = this;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                if (verb == "block-domain") {
                    sess.client.block_domain.begin (domain, true, (o, res) => {
                        try {
                            sess.client.block_domain.end (res);
                            show_toast (_("%s is blocked").printf (domain));
                        } catch (Error e) {
                            show_toast (e.message);
                        }
                    });
                    return;
                }
                sess.client.relate.begin (target.id, verb, (o, res) => {
                    try {
                        sess.client.relate.end (res);
                        show_toast (verb == "mute" ? _("%s is muted").printf (who) : _("%s is blocked").printf (who));
                        foreach (var v in history) if (v.feed.kind == FeedKind.FILTERS) v.reload ();
                    } catch (Error e) {
                        show_toast (e.message);
                    }
                });
            });
            dlg.present ();
        }

        public void request_compose (string[] uris = {}, string text = "") {
            shared_uris = uris;
            shared_text = text;
            if (_session != null && main_stack.visible_child_name == "main") compose (null);
            else if (store.active () != null) pending_compose = true;
            if (!pending_compose) {
                shared_uris = {};
                shared_text = "";
            }
        }

        public async void open_status_id (string account_key, string id) {
            for (int i = 0; i < 50 && _session == null; i++) {
                Timeout.add (200, () => {
                    open_status_id.callback ();
                    return Source.REMOVE;
                });
                yield;
            }
            if (_session == null) return;
            Session? sess = session_by_key (account_key);
            if (sess == null) {
                var saved = store.find (account_key);
                if (saved == null) return;
                string? token = yield AccountStore.lookup_token (account_key);
                if (token == null || token == "") return;
                sess = new Session (saved, token);
                sessions[account_key] = sess;
            }
            try {
                var st = yield sess.client.status (id);
                st.tag_via (account_key);
                open_status (st);
            } catch (Error e) {
                show_error (_("The post could not be opened: %s").printf (e.message));
            }
        }

        public void open_status (Status s) {
            if (_session == null) return;
            var f = new Feed (FeedKind.THREAD);
            f.focus = s.shown ();
            var top = current_view ();
            if (top != null && top.feed.kind == FeedKind.THREAD && top.feed.focus != null && top.feed.focus.id == f.focus.id) return;
            push (new TimelineView (f, this, session_for (s) ?? _session));
        }

        public void open_account (Account a) {
            if (_session == null) return;
            var top = current_view ();
            if (top != null && top.feed.kind == FeedKind.PROFILE && top.feed.account != null && top.feed.account.id == a.id && top.feed.account.via == a.via) return;
            var f = new Feed (FeedKind.PROFILE, a.id);
            f.account = a;
            var sess = a.via != "" ? (session_by_key (a.via) ?? _session) : _session;
            push (new TimelineView (f, this, sess, new ProfileHeader (a, this, sess)));
        }

        public void open_mention (string account_id, string url) {
            if (_session == null) return;
            var s = _session;
            if (account_id != "") {
                s.client.account.begin (account_id, (o, res) => {
                    try {
                        var a = s.client.account.end (res);
                        if (_session == s) open_account (a);
                    } catch (Error e) {
                        open_link (url);
                    }
                });
                return;
            }
            s.client.search.begin (url, true, null, (o, res) => {
                try {
                    var r = s.client.search.end (res);
                    if (r.accounts.size > 0 && _session == s) {
                        open_account (r.accounts[0]);
                        return;
                    }
                } catch (Error e) {
                }
                open_link (url);
            });
        }

        public void open_tag (string tag) {
            if (_session == null || tag == "") return;
            var top = current_view ();
            if (top != null && top.feed.kind == FeedKind.HASHTAG && top.feed.arg.down () == tag.down ()) return;
            push (new TimelineView (new Feed (FeedKind.HASHTAG, tag), this, _session));
        }

        public void open_link (string url) {
            if (!Content.safe_href (url)) return;
            new UriLauncher (url).launch.begin (this, null, (o, res) => {
                try {
                    new UriLauncher (url).launch.end (res);
                } catch (Error e) {
                    show_toast (_("The link could not be opened: %s").printf (e.message));
                }
            });
        }

        public void reply (Status s) {
            compose (s);
        }

        public void view_media (Gee.List<Attachment> media, int index) {
            var m = media[index];
            if (m.kind != MediaType.IMAGE) {
                open_link (m.url);
                return;
            }
            var images = new Gee.ArrayList<Attachment> ();
            int start = 0;
            foreach (var a in media) {
                if (a.kind != MediaType.IMAGE) continue;
                if (a == m) start = images.size;
                images.add (a);
            }
            Gdk.Paintable?[] slots = new Gdk.Paintable?[images.size];
            var viewer = new ImageViewer (this, slots, start);
            for (int i = 0; i < images.size; i++) {
                int idx = i;
                ImageCache.texture.begin (images[i].url, (o, res) => {
                    var t = ImageCache.texture.end (res);
                    if (t != null) viewer.set_image (idx, t);
                });
            }
            viewer.present ();
        }

        public void show_error (string text) {
            show_toast (text);
        }

        public void status_deleted (string id) {
            foreach (var v in history) v.remove_status (id);
            show_toast (_("Post deleted"));
        }

        public void show_toast (string text) {
            if (last_toast != null) last_toast.dismiss ();
            last_toast = new Singularity.Widgets.Toast (text);
            last_toast.timeout = 4;
            add_toast (last_toast);
        }

        private void start_live () {
            if (_session == null) return;
            var s = _session;
            if (user_stream != null) user_stream.close ();
            user_stream = new Stream ();
            var st = user_stream;
            st.received.connect ((e) => on_event (e, true));
            st.lost.connect (() => {
                if (user_stream == st) schedule_reconnect ();
            });
            st.open.begin (Oauth.streaming_url (s.saved.instance, s.info.streaming, "user"), s.client.token, (o, res) => {
                if (!st.open.end (res) && user_stream == st) schedule_reconnect ();
            });
            if (poll_id == 0) {
                poll_id = Timeout.add_seconds (90, () => {
                    poll ();
                    return Source.CONTINUE;
                });
            }
            update_view_stream ();
        }

        private void schedule_reconnect () {
            if (user_stream != null) user_stream.close ();
            user_stream = null;
            if (reconnect_id != 0) return;
            reconnect_id = Timeout.add_seconds (300, () => {
                reconnect_id = 0;
                if (_session != null) start_live ();
                return Source.REMOVE;
            });
        }

        private void poll () {
            foreach (var v in history) {
                if (!v.feed.live ()) continue;
                bool streamed = (v.feed.kind == FeedKind.HOME || v.feed.kind == FeedKind.NOTIFICATIONS) ? user_stream != null : (view_stream != null && view_stream_key == stream_key (v.feed));
                if (!streamed) v.poll_newer.begin ();
            }
        }

        private string stream_key (Feed f) {
            string? st = f.stream ();
            if (st == null) return "";
            return f.kind == FeedKind.HASHTAG ? st + ":" + f.arg.down () : st;
        }

        private void update_view_stream () {
            var v = current_view ();
            string key = v != null && _session != null ? stream_key (v.feed) : "";
            if (key == view_stream_key) return;
            if (view_stream != null) view_stream.close ();
            view_stream = null;
            view_stream_key = key;
            if (key == "" || _session == null) return;
            var s = _session;
            var st = new Stream ();
            view_stream = st;
            st.received.connect ((e) => on_event (e, false));
            st.lost.connect (() => {
                if (view_stream == st) {
                    view_stream = null;
                    view_stream_key = "";
                }
            });
            st.open.begin (Oauth.streaming_url (s.saved.instance, s.info.streaming, v.feed.stream (), v.feed.kind == FeedKind.HASHTAG ? v.feed.arg : null), s.client.token, (o, res) => {
                if (!st.open.end (res) && view_stream == st) {
                    view_stream = null;
                    view_stream_key = "";
                }
            });
        }

        private void stop_live () {
            if (user_stream != null) user_stream.close ();
            user_stream = null;
            if (view_stream != null) view_stream.close ();
            view_stream = null;
            view_stream_key = "";
            if (poll_id != 0) Source.remove (poll_id);
            poll_id = 0;
            if (reconnect_id != 0) Source.remove (reconnect_id);
            reconnect_id = 0;
        }

        private void on_event (StreamEvent e, bool user) {
            switch (e.event) {
                case "update":
                    var s = e.payload != null && e.payload.get_node_type () == Json.NodeType.OBJECT ? Status.parse (e.payload.get_object ()) : null;
                    if (s == null) return;
                    var one = new Gee.ArrayList<Object> ();
                    one.add (s);
                    foreach (var v in history) {
                        if (user && v.feed.kind == FeedKind.HOME) v.add_new (one);
                        if (!user && stream_key (v.feed) == view_stream_key) v.add_new (one);
                    }
                    break;
                case "notification":
                    var n = e.payload != null && e.payload.get_node_type () == Json.NodeType.OBJECT ? Notice.parse (e.payload.get_object ()) : null;
                    if (n == null) return;
                    var one = new Gee.ArrayList<Object> ();
                    one.add (n);
                    foreach (var v in history) if (v.feed.kind == FeedKind.NOTIFICATIONS) v.add_new (one);
                    if (n.kind == NotificationKind.MENTION) app.unread.check.begin ();
                    if (!is_active) {
                        var gn = new GLib.Notification (n.summary ());
                        if (n.status != null) {
                            string body = n.status.shown ().spoiler_text.strip () != "" ? n.status.shown ().spoiler_text : n.status.shown ().body ().plain ();
                            gn.set_body (body.length > 200 ? body.substring (0, body.index_of_nth_char (200)) + "…" : body);
                        }
                        gn.set_default_action ("app.show-notifications");
                        app.send_notification ("fedi-" + n.id, gn);
                    }
                    break;
                case "delete":
                    string id = e.payload_text != "" ? e.payload_text : "";
                    if (id != "") foreach (var v in history) v.remove_status (id);
                    break;
                case "status.update":
                    var s = e.payload != null && e.payload.get_node_type () == Json.NodeType.OBJECT ? Status.parse (e.payload.get_object ()) : null;
                    if (s != null) foreach (var v in history) v.replace_status (s);
                    break;
            }
        }

        public void signed_out () {
            var a = store.active ();
            if (a == null || _session == null) return;
            show_signed_out (a, _("%s no longer accepts the sign-in of this app. Sign in again to keep using this account.").printf (_session.host ()));
        }

        public void show_notifications () {
            present ();
            if (_session != null && main_stack.visible_child_name == "main") show_root (new Feed (FeedKind.NOTIFICATIONS));
        }
    }
}
