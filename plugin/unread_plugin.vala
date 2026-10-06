[ModuleInit]
public void peas_register_types (TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (Singularity.Plugin), typeof (FediverseUnreadPlugin));
}

public class FediverseUnreadPlugin : Object, Singularity.Plugin {
    private const uint FIRST_CHECK_SECONDS = 20;
    private const uint INTERVAL_SECONDS = 300;

    private uint timer;

    public void activate (Singularity.PluginContext context) {
        timer = Timeout.add_seconds (FIRST_CHECK_SECONDS, () => {
            check ();
            timer = Timeout.add_seconds (INTERVAL_SECONDS, () => {
                check ();
                return Source.CONTINUE;
            });
            return Source.REMOVE;
        });
    }

    public void deactivate () {
        if (timer != 0) Source.remove (timer);
        timer = 0;
    }

    public Gtk.Widget? get_settings_widget () {
        return null;
    }

    private static bool has_accounts () {
        string path = Path.build_filename (Environment.get_user_config_dir (), "singularity", "fediverse.json");
        try {
            var parser = new Json.Parser ();
            parser.load_from_file (path);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) return false;
            var o = root.get_object ();
            return o.has_member ("accounts") && o.get_member ("accounts").get_node_type () == Json.NodeType.ARRAY
                && o.get_array_member ("accounts").get_length () > 0;
        } catch (Error e) {
            return false;
        }
    }

    private static void check () {
        if (!has_accounts ()) return;
        Bus.get.begin (BusType.SESSION, null, (o, res) => {
            try {
                var bus = Bus.get.end (res);
                bus.call.begin ("dev.sinty.fediverse", "/dev/sinty/fediverse", "org.freedesktop.Application", "ActivateAction",
                    new Variant ("(s@av@a{sv})", "check-notifications", new Variant.array (VariantType.VARIANT, {}),
                        new VariantBuilder (VariantType.VARDICT).end ()),
                    null, DBusCallFlags.NONE, 30000, null, (obj, r) => {
                        try {
                            bus.call.end (r);
                        } catch (Error e) {
                            debug ("fediverse-unread: %s", e.message);
                        }
                    });
            } catch (Error e) {
                debug ("fediverse-unread: %s", e.message);
            }
        });
    }
}
