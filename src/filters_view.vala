using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Fediverse {

    public class FiltersView : Page {
        private Navigator nav;
        private Session session;
        private Gtk.Application app;
        private Stack stack;
        private StatusPage error_page;
        private PreferencesGroup filters_group;
        private PreferencesGroup mutes_group;
        private PreferencesGroup blocks_group;
        private PreferencesGroup domains_group;
        private int serial;

        private struct Choice {
            public string label;
            public int seconds;
        }

        public FiltersView (Feed feed, Navigator nav, Session session, Gtk.Application app) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.feed = feed;
            this.nav = nav;
            this.session = session;
            this.app = app;
            stack = new Stack ();
            stack.vexpand = true;
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

            var page = new WelcomePage ();
            page.is_section = true;
            page.title = _("Filters and Mutes");
            page.subtitle = _("Choose the words, people and servers you do not want to see on %s.").printf (session.host ());
            page.add_action ("dialog-warning", _("New Filter"), _("Hide posts with chosen words, or show a warning first"), () => edit_filter (null));
            page.add_action ("changes-prevent", _("Block a Server"), _("Stop seeing posts and people from a whole server"), () => ask_domain ());
            var lists = new Box (Orientation.VERTICAL, 18);
            lists.margin_bottom = 24;
            apply_view_edge (lists);
            filters_group = new PreferencesGroup (_("Filters"));
            mutes_group = new PreferencesGroup (_("Muted Accounts"));
            blocks_group = new PreferencesGroup (_("Blocked Accounts"));
            domains_group = new PreferencesGroup (_("Blocked Servers"));
            lists.append (filters_group);
            lists.append (mutes_group);
            lists.append (blocks_group);
            lists.append (domains_group);
            page.set_extra_widget (lists);
            stack.add_named (page, "content");
            append (stack);
            reload ();
        }

        public override void reload () {
            load.begin ();
        }

        private async void load () {
            int my = ++serial;
            if (stack.visible_child_name != "content") stack.visible_child_name = "loading";
            try {
                var filters = yield session.client.filters ();
                var mutes = yield session.client.account_list ("/api/v1/mutes");
                var blocks = yield session.client.account_list ("/api/v1/blocks");
                var domains = yield session.client.blocked_domains ();
                if (my != serial) return;
                fill_filters (filters);
                fill_accounts (mutes_group, mutes, _("Unmute"), "unmute", _("Nobody is muted. Mute people from the menu of their posts."));
                fill_accounts (blocks_group, blocks, _("Unblock"), "unblock", _("Nobody is blocked."));
                fill_domains (domains);
                stack.visible_child_name = "content";
            } catch (Error e) {
                if (my != serial) return;
                if (e is ApiError.UNAUTHORIZED) {
                    nav.signed_out ();
                    return;
                }
                error_page.description = TimelineView.describe (e);
                stack.visible_child_name = "error";
            }
        }

        private static string context_label (string c) {
            switch (c) {
                case "home": return _("Home and Lists");
                case "notifications": return _("Notifications");
                case "public": return _("Public Timelines");
                case "thread": return _("Conversations");
                case "account": return _("Profiles");
                default: return c;
            }
        }

        private void fill_filters (Gee.List<Filter> filters) {
            filters_group.clear ();
            filters_group.description = filters.size == 0 ? _("No filters yet.") : "";
            var now = new DateTime.now_utc ();
            foreach (var f in filters) {
                var filter = f;
                string[] where = {};
                foreach (string c in f.context) where += context_label (c);
                string sub = f.summary ();
                if (where.length > 0) sub = _("%s, in %s").printf (sub, string.joinv (", ", where));
                if (f.expired (now)) sub = _("%s, expired").printf (sub);
                else if (f.expires_at != null) sub = _("%s, until %s").printf (sub, Ui.moment (f.expires_at));
                var row = new ActionRow (f.title != "" ? f.title : _("Untitled Filter"), sub, f.hides () ? "view-conceal-symbolic" : "dialog-warning-symbolic");
                var edit = Ui.tool_button ("document-edit-symbolic", _("Edit Filter"));
                edit.clicked.connect (() => edit_filter (filter));
                row.add_suffix (edit);
                var del = Ui.tool_button ("user-trash-symbolic", _("Delete Filter"));
                del.clicked.connect (() => confirm_delete (filter));
                row.add_suffix (del);
                row.activated.connect (() => edit_filter (filter));
                filters_group.add_row (row);
            }
        }

        private void fill_accounts (PreferencesGroup group, Gee.List<Account> list, string label, string verb, string empty) {
            group.clear ();
            group.description = list.size == 0 ? empty : "";
            foreach (var a in list) {
                var acc = a;
                var row = new ActionRow (Content.from_text (a.name (), a.emojis).plain (), a.handle (session.host ()));
                var av = Ui.avatar (a.avatar, 32);
                av.margin_end = 10;
                row.add_prefix (av);
                var b = new Button.with_label (label);
                b.add_css_class ("pill");
                b.valign = Align.CENTER;
                b.clicked.connect (() => {
                    b.sensitive = false;
                    session.client.relate.begin (acc.id, verb, (o, res) => {
                        try {
                            session.client.relate.end (res);
                            reload ();
                            nav.show_error (verb == "unmute" ? _("%s is no longer muted").printf (acc.handle (session.host ())) : _("%s is no longer blocked").printf (acc.handle (session.host ())));
                        } catch (Error e) {
                            b.sensitive = true;
                            nav.show_error (e.message);
                        }
                    });
                });
                row.add_suffix (b);
                row.activated.connect (() => nav.open_account (acc));
                group.add_row (row);
            }
        }

        private void fill_domains (Gee.List<BlockedDomain> list) {
            domains_group.clear ();
            domains_group.description = list.size == 0 ? _("No server is blocked.") : "";
            foreach (var d in list) {
                string domain = d.domain;
                var row = new ActionRow (domain, null, "network-server-symbolic");
                var b = new Button.with_label (_("Unblock"));
                b.add_css_class ("pill");
                b.valign = Align.CENTER;
                b.clicked.connect (() => {
                    b.sensitive = false;
                    session.client.block_domain.begin (domain, false, (o, res) => {
                        try {
                            session.client.block_domain.end (res);
                            reload ();
                            nav.show_error (_("%s is no longer blocked").printf (domain));
                        } catch (Error e) {
                            b.sensitive = true;
                            nav.show_error (e.message);
                        }
                    });
                });
                row.add_suffix (b);
                domains_group.add_row (row);
            }
        }

        private void ask_domain () {
            var dlg = new ConfirmDialog (app, _("Block a Server"), null,
                _("You no longer see posts or notifications from anyone on the server, and your followers there are removed."), _("Block"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = get_root () as Gtk.Window;
            dlg.modal = true;
            var group = new PreferencesGroup ();
            var row = new EntryRow (_("Server, like example.social"));
            group.add_row (row);
            dlg.custom_area.append (group);
            dlg.primary_sensitive = false;
            row.entry_changed.connect (() => dlg.primary_sensitive = Oauth.normalize_instance (row.text) != null);
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                string? inst = Oauth.normalize_instance (row.text);
                string? domain = inst != null ? Oauth.host_of (inst) : null;
                if (domain == null) return;
                session.client.block_domain.begin (domain, true, (o, res) => {
                    try {
                        session.client.block_domain.end (res);
                        nav.show_error (_("%s is blocked").printf (domain));
                        reload ();
                    } catch (Error e) {
                        nav.show_error (e.message);
                    }
                });
            });
            dlg.present ();
            row.grab_focus ();
        }

        private void confirm_delete (Filter f) {
            var dlg = new ConfirmDialog (app, _("Delete %s?").printf (f.title), "user-trash-symbolic",
                _("Posts that match this filter show up again."), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = get_root () as Gtk.Window;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                session.client.delete_filter.begin (f.id, (o, res) => {
                    try {
                        session.client.delete_filter.end (res);
                        reload ();
                    } catch (Error e) {
                        nav.show_error (_("The filter was not deleted: %s").printf (e.message));
                    }
                });
            });
            dlg.present ();
        }

        private void edit_filter (Filter? existing) {
            var words = new Gee.ArrayList<FilterKeyword> ();
            if (existing != null) {
                foreach (var k in existing.keywords) {
                    var copy = new FilterKeyword (k.keyword, k.whole_word);
                    copy.id = k.id;
                    words.add (copy);
                }
            }
            var dlg = new ConfirmDialog (app, existing != null ? _("Edit Filter") : _("New Filter"), null, null, _("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = get_root () as Gtk.Window;
            dlg.modal = true;
            dlg.set_default_size (460, -1);
            var form = new Box (Orientation.VERTICAL, 16);
            var scroller = new ScrolledWindow ();
            scroller.hscrollbar_policy = PolicyType.NEVER;
            scroller.propagate_natural_height = true;
            scroller.max_content_height = 460;
            scroller.child = form;
            dlg.custom_area.append (scroller);

            var main = new PreferencesGroup ();
            var title = new EntryRow (_("Name"));
            if (existing != null) title.text = existing.title;
            main.add_row (title);
            string warn_label = _("Show a Warning");
            string hide_label = _("Hide Completely");
            var action = new SelectionRow (_("Matching Posts"), { warn_label, hide_label }, existing != null && existing.hides () ? hide_label : warn_label);
            action.icon_name = "view-conceal-symbolic";
            main.add_row (action);
            Choice[] choices = {
                Choice () { label = _("Never"), seconds = 0 },
                Choice () { label = _("In 30 Minutes"), seconds = 1800 },
                Choice () { label = _("In 1 Hour"), seconds = 3600 },
                Choice () { label = _("In 12 Hours"), seconds = 43200 },
                Choice () { label = _("In 1 Day"), seconds = 86400 },
                Choice () { label = _("In 1 Week"), seconds = 604800 }
            };
            string[] labels = {};
            string current = choices[0].label;
            string kept = "";
            if (existing != null && existing.expires_at != null && !existing.expired (new DateTime.now_utc ())) {
                kept = _("Until %s").printf (Ui.moment (existing.expires_at));
                labels += kept;
                current = kept;
            }
            foreach (var c in choices) labels += c.label;
            var expiry = new SelectionRow (_("Stops Working"), labels, current);
            expiry.icon_name = "alarm-symbolic";
            main.add_row (expiry);
            form.append (main);

            var where = new PreferencesGroup (_("Where"));
            var switches = new Gee.HashMap<string, SwitchRow> ();
            foreach (string c in Filter.CONTEXTS) {
                bool on = existing != null ? existing.context.contains (c) : (c == "home" || c == "public" || c == "thread");
                var sw = new SwitchRow (context_label (c), null, on);
                switches[c] = sw;
                where.add_row (sw);
            }
            form.append (where);

            var group = new PreferencesGroup (_("Words"));
            form.append (group);

            RebuildWords validate = () => {
                bool any_word = false;
                foreach (var k in words) if (!k.destroy && k.keyword.strip () != "") any_word = true;
                bool any_place = false;
                foreach (var sw in switches.values) if (sw.active) any_place = true;
                dlg.primary_sensitive = title.text.strip () != "" && any_word && any_place;
            };

            RebuildWords rebuild = null;
            rebuild = () => {
                group.clear ();
                foreach (var k in words) {
                    if (k.destroy) continue;
                    var word = k;
                    var row = new ActionRow (k.keyword, k.whole_word ? _("Whole word only") : _("Also inside longer words"));
                    var whole = new ToggleButton.with_label (_("Whole Word"));
                    whole.add_css_class ("flat");
                    whole.active = k.whole_word;
                    whole.valign = Align.CENTER;
                    whole.toggled.connect (() => {
                        word.whole_word = whole.active;
                        row.subtitle = word.whole_word ? _("Whole word only") : _("Also inside longer words");
                    });
                    row.add_suffix (whole);
                    var del = Ui.tool_button ("list-remove-symbolic", _("Remove Word"));
                    del.clicked.connect (() => {
                        if (word.id != "") word.destroy = true;
                        else words.remove (word);
                        rebuild ();
                        validate ();
                    });
                    row.add_suffix (del);
                    group.add_row (row);
                }
                var add = new EntryRow (_("Add a Word or Phrase"), "list-add-symbolic");
                add.entry_activated.connect (() => {
                    string w = add.text.strip ();
                    if (w == "") return;
                    foreach (var k in words) if (!k.destroy && k.keyword.casefold () == w.casefold ()) return;
                    words.add (new FilterKeyword (w, true));
                    rebuild ();
                    validate ();
                    Idle.add (() => {
                        var last = group.get_rows ();
                        if (last.size > 0) last[last.size - 1].grab_focus ();
                        return Source.REMOVE;
                    });
                });
                group.add_row (add);
            };
            rebuild ();
            title.entry_changed.connect (() => validate ());
            foreach (var sw in switches.values) sw.switch_btn.notify["active"].connect (() => validate ());
            validate ();

            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                var ctx = new Gee.ArrayList<string> ();
                foreach (string c in Filter.CONTEXTS) if (switches[c].active) ctx.add (c);
                int expires = 0;
                string chosen = expiry.current_value;
                if (chosen == kept && kept != "") {
                    expires = (int) int64.max (60, existing.expires_at.to_unix () - new DateTime.now_utc ().to_unix ());
                } else {
                    foreach (var c in choices) if (c.label == chosen) expires = c.seconds;
                }
                var p = Requests.filter (title.text, ctx, action.current_value == hide_label, expires, words);
                session.client.save_filter.begin (existing != null ? existing.id : null, p, (o, res) => {
                    try {
                        session.client.save_filter.end (res);
                        nav.show_error (existing != null ? _("Filter saved") : _("Filter created"));
                        reload ();
                    } catch (Error e) {
                        nav.show_error (_("The filter was not saved: %s").printf (e.message));
                    }
                });
            });
            dlg.present ();
            title.grab_focus ();
        }

        private delegate void RebuildWords ();
    }
}
