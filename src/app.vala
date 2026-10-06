using Gtk;

namespace Singularity.Apps.Fediverse {

    public class FediverseApp : Singularity.Application {
        public AccountStore store;
        public DraftStore drafts;
        public UnreadChecker unread;
        private string? pending_action;
        private bool checked_once;

        public FediverseApp () {
            Object (application_id: "dev.sinty.fediverse", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new-post", 0, OptionFlags.NONE, OptionArg.NONE, _("Write a new post"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("new-post")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("fediverse: %s", e.message);
                return 1;
            }
            if (get_is_remote ()) {
                activate_action ("new-post", null);
                return 0;
            }
            pending_action = "new-post";
            return -1;
        }

        protected override void startup () {
            base.startup ();
            store = new AccountStore ();
            drafts = new DraftStore ();
            unread = new UnreadChecker (store);
            if ((flags & ApplicationFlags.IS_SERVICE) != 0) inactivity_timeout = 10000;
            ImageCache.prune ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            var f1 = new GLib.Menu ();
            f1.append (_("New Post"), "win.new-post");
            f1.append (_("Add Account…"), "win.add-account");
            f1.append (_("Remove Account…"), "win.remove-account");
            file.append_section (null, f1);
            var f2 = new GLib.Menu ();
            f2.append (_("Close Window"), "win.close");
            f2.append (_("Quit"), "app.quit");
            file.append_section (null, f2);
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Search"), "win.find");
            edit.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Filters and Mutes"), "win.filters");
            edit.append_section (null, e2);
            var e3 = new GLib.Menu ();
            e3.append (_("Settings"), "app.settings");
            edit.append_section (null, e3);
            menu.append_submenu (_("Edit"), edit);
            var view = new GLib.Menu ();
            var v1 = new GLib.Menu ();
            v1.append (_("Home"), "win.home");
            v1.append (_("All Accounts"), "win.unified");
            v1.append (_("Local"), "win.local");
            v1.append (_("Federated"), "win.federated");
            view.append_section (null, v1);
            var v2 = new GLib.Menu ();
            v2.append (_("Notifications"), "win.notifications");
            v2.append (_("Bookmarks"), "win.bookmarks");
            v2.append (_("Favourites"), "win.favourites");
            v2.append (_("Profile"), "win.profile");
            view.append_section (null, v2);
            var v4 = new GLib.Menu ();
            v4.append (_("Drafts"), "win.drafts");
            v4.append (_("Scheduled"), "win.scheduled");
            view.append_section (null, v4);
            var v3 = new GLib.Menu ();
            v3.append (_("Back"), "win.back");
            v3.append (_("Refresh"), "win.refresh");
            view.append_section (null, v3);
            menu.append_submenu (_("View"), view);
            set_menubar (menu);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ()) w.close ();
            });
            add_action (quit);
            var notes = new SimpleAction ("show-notifications", null);
            notes.activate.connect (() => window ().show_notifications ());
            add_action (notes);
            var check = new SimpleAction ("check-notifications", null);
            check.activate.connect (() => {
                hold ();
                unread.check.begin ((o, res) => {
                    unread.check.end (res);
                    release ();
                });
            });
            add_action (check);
            var new_post = new SimpleAction ("new-post", null);
            new_post.activate.connect (() => {
                var w = window ();
                w.present ();
                w.request_compose ();
            });
            add_action (new_post);
            var compose_media = new SimpleAction ("compose-media", new VariantType ("as"));
            compose_media.activate.connect ((param) => {
                var w = window ();
                w.present ();
                w.request_compose (param.dup_strv ());
            });
            add_action (compose_media);
            var compose_text = new SimpleAction ("compose-text", VariantType.STRING);
            compose_text.activate.connect ((param) => {
                var w = window ();
                w.present ();
                w.request_compose ({}, param.get_string ());
            });
            add_action (compose_text);
            var open_status = new SimpleAction ("open-status", VariantType.STRING);
            open_status.activate.connect ((param) => {
                string[] parts = param.get_string ().split ("\n", 2);
                if (parts.length != 2) return;
                var w = window ();
                w.present ();
                w.open_status_id.begin (parts[0], parts[1]);
            });
            add_action (open_status);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.fediverse");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("win.new-post", { "<Control>n" });
            set_accels_for_action ("win.find", { "<Control>f" });
            set_accels_for_action ("win.refresh", { "<Control>r", "F5" });
            set_accels_for_action ("win.home", { "<Control>1" });
            set_accels_for_action ("win.local", { "<Control>2" });
            set_accels_for_action ("win.federated", { "<Control>3" });
            set_accels_for_action ("win.notifications", { "<Control>4" });
            set_accels_for_action ("win.bookmarks", { "<Control>5" });
            set_accels_for_action ("win.favourites", { "<Control>6" });
            set_accels_for_action ("win.profile", { "<Control>7" });
            set_accels_for_action ("win.drafts", { "<Control>8" });
            set_accels_for_action ("win.scheduled", { "<Control>9" });
            set_accels_for_action ("win.unified", { "<Control>0" });
            set_accels_for_action ("win.filters", { "<Control><Shift>f" });
            set_accels_for_action ("win.back", { "<Alt>Left" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
        }

        private FediverseWindow window () {
            var w = get_active_window () as FediverseWindow;
            if (w == null) {
                foreach (var win in get_windows ()) {
                    if (win is FediverseWindow) w = (FediverseWindow) win;
                }
            }
            if (w == null) w = new FediverseWindow (this);
            return w;
        }

        public override void activate () {
            if (pending_action != null) {
                string action = pending_action;
                pending_action = null;
                activate_action (action, null);
                return;
            }
            window ().present ();
            if (!checked_once) {
                checked_once = true;
                unread.check.begin ();
            }
        }

        public override void open (File[] files, string hint) {
            var w = window ();
            w.present ();
            foreach (var f in files) {
                string uri = f.get_uri ();
                if (uri.down ().has_prefix (Oauth.SCHEME + ":")) w.handle_redirect (uri);
            }
        }

        private const string CSS = """
.fedi-list {
    background: transparent;
}

.fedi-list > row {
    padding: 14px 16px;
    border-bottom: 1px solid alpha(@borders, 0.6);
}

.fedi-list > row:focus-visible {
    outline: 2px solid alpha(@accent_bg_color, 0.7);
    outline-offset: -2px;
    border-radius: 12px;
}

.fedi-column {
    padding-bottom: 24px;
}

.fedi-text,
.fedi-text text {
    background: transparent;
}

.fedi-name,
.fedi-name text {
    font-weight: 700;
}

.fedi-profile-name,
.fedi-profile-name text {
    font-weight: 800;
    font-size: 22px;
}

.fedi-focused-text,
.fedi-focused-text text {
    font-size: 17px;
}

.fedi-preview,
.fedi-preview text {
    opacity: 0.75;
}

.fedi-focused {
    border-left: 3px solid @accent_bg_color;
    padding-left: 10px;
    margin-left: -13px;
}

.fedi-avatar-button {
    padding: 0;
    border-radius: 999px;
    min-width: 0;
    min-height: 0;
}

.fedi-boosted-by {
    padding: 0 4px;
    min-height: 0;
    font-size: 13px;
    font-weight: 600;
    opacity: 0.7;
}

.fedi-cw {
    padding: 10px 12px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.06);
}

.fedi-cw-text,
.fedi-cw-text text {
    font-weight: 600;
}

.fedi-media-grid {
    border-radius: 14px;
}

.fedi-media {
    padding: 0;
    border-radius: 10px;
    background-color: alpha(@window_fg_color, 0.08);
    box-shadow: none;
    border: none;
}

.fedi-media picture {
    border-radius: 10px;
}

.fedi-media-badge {
    padding: 12px;
    border-radius: 999px;
    color: white;
    background-color: alpha(black, 0.55);
}

.fedi-alt-badge {
    font-size: 11px;
    font-weight: 800;
    padding: 1px 6px;
    border-radius: 6px;
    color: white;
    background-color: alpha(black, 0.6);
}

.fedi-sensitive {
    border-radius: 14px;
    background-color: alpha(@window_bg_color, 0.96);
    border: 1px solid alpha(@borders, 0.8);
}

.fedi-poll {
    padding: 10px 12px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.04);
}

.fedi-actions {
    margin-left: -8px;
}

.fedi-action {
    padding: 4px 10px;
    min-height: 0;
    border-radius: 99px;
    opacity: 0.75;
}

.fedi-action:hover {
    opacity: 1;
}

.fedi-action.fedi-on {
    opacity: 1;
    color: @accent_color;
}

.fedi-count {
    font-feature-settings: "tnum";
}

.fedi-notification-icon {
    color: @accent_color;
}

.fedi-account-row {
    padding: 2px 0;
}

.fedi-profile {
    padding: 24px 16px 16px 16px;
    border-bottom: 1px solid alpha(@borders, 0.6);
}

.fedi-fields {
    padding: 10px 12px;
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.04);
}

.fedi-verified,
.fedi-verified text {
    color: #26a269;
}

.fedi-footer {
    padding: 18px;
}

.fedi-new-pill {
    box-shadow: 0 6px 18px alpha(black, 0.25);
}

.fedi-account-switch {
    padding: 8px;
    margin-bottom: 6px;
    border-radius: 12px;
}

.fedi-compose-frame {
    border-radius: 12px;
    border: 1px solid alpha(@borders, 0.9);
}

.fedi-compose-text,
.fedi-compose-text text {
    background: transparent;
}

.fedi-reply-snippet {
    padding: 8px 12px;
    border-radius: 10px;
    background-color: alpha(@window_fg_color, 0.05);
}

.fedi-counter {
    font-feature-settings: "tnum";
    margin: 0 6px;
}

.fedi-upload {
    border-radius: 10px;
    background-color: alpha(@window_fg_color, 0.08);
}

.fedi-alt-button {
    font-size: 11px;
    font-weight: 800;
    padding: 1px 6px;
    min-height: 0;
    border-radius: 6px;
    color: white;
    background-color: alpha(black, 0.6);
}

.fedi-via {
    padding: 1px 8px;
    border-radius: 99px;
    background-color: alpha(@accent_bg_color, 0.15);
}

.fedi-translation-note {
    padding: 2px 0;
}

.fedi-draft,
.fedi-scheduled {
    padding: 2px 0;
}

.fedi-scheduled-on {
    color: @accent_color;
}

.fedi-alt-button.fedi-on {
    background-color: @accent_bg_color;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-fediverse", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-fediverse", "UTF-8");
        Intl.textdomain ("singularity-fediverse");
        return new FediverseApp ().run (args);
    }
}
