using Gtk;
using Singularity;

namespace SingularityFediverseWidget {

    public class MentionsProvider : Object, OverviewWidgetProvider {
        public string id { get { return "fediverse.mentions"; } }
        public string provider_id { get { return "dev.sinty.fediverse"; } }
        public string display_name { get { return _("Latest Mentions"); } }
        public string icon_name { get { return "mail-unread-symbolic"; } }
        private WidgetSize[] _sizes;
        public WidgetSize[] supported_sizes {
            get {
                if (_sizes == null) _sizes = { WidgetSize (2, 2), WidgetSize (2, 4), WidgetSize (4, 2), WidgetSize (4, 4) };
                return _sizes;
            }
        }

        public static bool shows_direct (Variant? config) {
            return config != null && config.is_of_type (VariantType.BOOLEAN) && config.get_boolean ();
        }

        public Gtk.Widget create_instance (string instance_id, WidgetSize size, Variant? config) {
            return new MentionsInstance (size, shows_direct (config));
        }

        public bool can_configure (string instance_id) {
            return true;
        }

        public void configure_instance (string instance_id) {
            var registry = OverviewWidgetRegistry.get_default ();
            bool direct = shows_direct (registry.get_instance_config (instance_id));
            var dialog = new Singularity.Shell.ShellDialog.anchored (GLib.Application.get_default (), true, true, true, true);
            var box = new Box (Orientation.VERTICAL, 16);
            box.set_size_request (420, -1);
            box.margin_top = box.margin_bottom = 24;
            box.margin_start = box.margin_end = 24;
            var group = new Singularity.Widgets.PreferencesGroup (_("Latest Mentions"));
            var row = new Singularity.Widgets.SwitchRow (_("Show Direct Messages"), _("Anyone looking at the screen can read them"), direct);
            group.add_row (row);
            box.append (group);
            var buttons = new Box (Orientation.HORIZONTAL, 8);
            buttons.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            cancel.clicked.connect (() => dialog.close_dialog ());
            buttons.append (cancel);
            var save = new Button.with_label (_("Save"));
            save.add_css_class ("suggested-action");
            save.clicked.connect (() => {
                registry.save_instance_config (instance_id, row.active ? new Variant.boolean (true) : null);
                dialog.close_dialog ();
            });
            buttons.append (save);
            box.append (buttons);
            dialog.content_box.append (box);
            dialog.present ();
        }
    }

    public class MentionsInstance : Box {
        private WidgetSize size;
        private bool show_direct;
        private Box list;
        private Label empty;
        private FileMonitor? monitor;
        private uint reload_id;

        public MentionsInstance (WidgetSize size, bool show_direct) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            this.size = size;
            this.show_direct = show_direct;
            add_css_class ("overview-widget-card");
            hexpand = true;
            vexpand = true;
            overflow = Overflow.HIDDEN;
            var title = new Label (_("Latest Mentions"));
            title.add_css_class ("heading");
            title.xalign = 0;
            title.margin_start = 14;
            title.margin_top = 12;
            append (title);
            list = new Box (Orientation.VERTICAL, 4);
            list.margin_start = list.margin_end = 8;
            list.margin_bottom = 10;
            list.vexpand = true;
            append (list);
            empty = new Label (_("Mentions of your Fediverse accounts appear here"));
            empty.add_css_class ("dim-label");
            empty.wrap = true;
            empty.justify = Justification.CENTER;
            empty.vexpand = true;
            empty.valign = Align.CENTER;
            empty.margin_start = empty.margin_end = 16;
            append (empty);
            var file = File.new_for_path (cache_path ());
            try {
                monitor = file.monitor_file (FileMonitorFlags.WATCH_MOVES);
                monitor.changed.connect (() => {
                    if (reload_id != 0) Source.remove (reload_id);
                    reload_id = Timeout.add (300, () => {
                        reload_id = 0;
                        reload ();
                        return Source.REMOVE;
                    });
                });
            } catch (Error e) {
            }
            reload ();
            destroy.connect (() => {
                if (reload_id != 0) Source.remove (reload_id);
                reload_id = 0;
                if (monitor != null) monitor.cancel ();
            });
        }

        private static string cache_path () {
            return Path.build_filename (Environment.get_user_cache_dir (), "singularity-fediverse", "mentions.json");
        }

        private void reload () {
            Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
            int limit = size.h >= 4 ? 6 : 3;
            int shown = 0;
            try {
                var parser = new Json.Parser ();
                parser.load_from_file (cache_path ());
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.ARRAY) {
                    foreach (var n in root.get_array ().get_elements ()) {
                        if (shown >= limit) break;
                        if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                        var o = n.get_object ();
                        if (o.get_boolean_member_with_default ("direct", false) && !show_direct) continue;
                        list.append (make_row (o));
                        shown++;
                    }
                }
            } catch (Error e) {
            }
            list.visible = shown > 0;
            empty.visible = shown == 0;
        }

        private static string ago (int64 when) {
            if (when <= 0) return "";
            int64 d = new DateTime.now_utc ().to_unix () - when;
            if (d < 60) return _("now");
            if (d < 3600) return _("%d min").printf ((int) (d / 60));
            if (d < 86400) return _("%d h").printf ((int) (d / 3600));
            return _("%d d").printf ((int) (d / 86400));
        }

        private Widget make_row (Json.Object o) {
            var button = new Button ();
            button.add_css_class ("flat");
            var box = new Box (Orientation.HORIZONTAL, 10);
            var avatar = new Singularity.Widgets.Avatar (36);
            string path = o.get_string_member_with_default ("avatar", "");
            if (path != "" && FileUtils.test (path, FileTest.EXISTS)) avatar.set_from_file (path);
            avatar.valign = Align.START;
            box.append (avatar);
            var texts = new Box (Orientation.VERTICAL, 2);
            texts.hexpand = true;
            var head = new Box (Orientation.HORIZONTAL, 6);
            var name = new Label (o.get_string_member_with_default ("author", ""));
            name.add_css_class ("heading");
            name.xalign = 0;
            name.ellipsize = Pango.EllipsizeMode.END;
            name.hexpand = true;
            head.append (name);
            if (o.get_boolean_member_with_default ("direct", false)) {
                var dm_icon = new Image.from_icon_name ("mail-send-symbolic");
                dm_icon.tooltip_text = _("Direct message");
                head.append (dm_icon);
            }
            var time = new Label (ago (o.get_int_member_with_default ("time", 0)));
            time.add_css_class ("dim-label");
            time.add_css_class ("caption");
            head.append (time);
            texts.append (head);
            var text = new Label (o.get_string_member_with_default ("text", ""));
            text.xalign = 0;
            text.wrap = true;
            text.wrap_mode = Pango.WrapMode.WORD_CHAR;
            text.lines = 2;
            text.ellipsize = Pango.EllipsizeMode.END;
            text.add_css_class ("caption");
            texts.append (text);
            box.append (texts);
            button.child = box;
            string target = o.get_string_member_with_default ("account", "") + "\n" + o.get_string_member_with_default ("id", "");
            button.clicked.connect (() => open_post (target));
            return button;
        }

        private static void open_post (string target) {
            Bus.get.begin (BusType.SESSION, null, (o, res) => {
                try {
                    var bus = Bus.get.end (res);
                    var args = new VariantBuilder (new VariantType ("av"));
                    args.add ("v", new Variant.string (target));
                    bus.call.begin ("dev.sinty.fediverse", "/dev/sinty/fediverse", "org.freedesktop.Application", "ActivateAction",
                        new Variant ("(s@av@a{sv})", "open-status", args.end (), new VariantBuilder (VariantType.VARDICT).end ()),
                        null, DBusCallFlags.NONE, 5000, null);
                } catch (Error e) {
                    warning ("fediverse widget: %s", e.message);
                }
            });
        }
    }

    [CCode (cname = "singularity_fediverse_widget_new")]
    public static Object singularity_fediverse_widget_new () {
        return new MentionsProvider ();
    }
}
