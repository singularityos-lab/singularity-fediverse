using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Fediverse {

    public class ComposeDialog : AppDialog {
        public signal void posted (Status s);
        public signal void scheduled (ScheduledStatus s);

        private class Upload : Object {
            public File file;
            public Attachment? attachment;
            public string description = "";
            public bool busy = true;
            public Cancellable cancel = new Cancellable ();
            public Widget tile;
        }

        private Session session;
        private Status? reply_to;
        private TextView text;
        private Label placeholder;
        private Revealer cw_reveal;
        private Entry cw_entry;
        private ToggleButton cw_toggle;
        private Button vis_button;
        private ToggleButton sensitive_toggle;
        private Visibility visibility = Visibility.PUBLIC;
        private Label counter;
        private Button post_button;
        private Button attach_button;
        private Spinner spinner;
        private Label error;
        private FlowBox media_box;
        private Gee.ArrayList<Upload> uploads = new Gee.ArrayList<Upload> ();
        private string idempotency = Uuid.string_random ();
        private bool sending;
        private bool done;
        private DraftStore? drafts;
        private Draft draft;
        private string reply_id = "";
        private uint save_id;
        private bool touched;
        private DateTime? scheduled_at;
        private Button schedule_button;
        private Revealer schedule_reveal;
        private Label schedule_label;
        public Gee.ArrayList<string> carry_media = new Gee.ArrayList<string> ();

        public ComposeDialog (Gtk.Application app, Session session, Status? reply_to, DraftStore? drafts = null, Draft? from_draft = null, DateTime? schedule = null) {
            base (app, false);
            this.session = session;
            this.reply_to = reply_to;
            this.drafts = drafts;
            if (from_draft != null) {
                draft = from_draft;
            } else {
                draft = new Draft ();
                draft.account = session.saved.key ();
                if (reply_to != null) {
                    draft.reply_to_id = reply_to.id;
                    draft.reply_to_handle = reply_to.account.handle (session.host ());
                    draft.reply_snippet = reply_to.spoiler_text.strip () != "" ? reply_to.spoiler_text : reply_to.body ().plain ();
                }
            }
            reply_id = draft.reply_to_id;
            bool replying = reply_id != "";
            set_title (draft.replaces_scheduled != "" ? _("Edit Scheduled Post") : (replying ? _("Reply") : _("New Post")));
            set_default_size (560, 460);

            var box = new Box (Orientation.VERTICAL, 10);
            box.margin_top = 12;
            box.margin_bottom = 16;
            box.margin_start = 18;
            box.margin_end = 18;

            if (replying) {
                var to = Ui.dim (_("Replying to %s").printf (draft.reply_to_handle), false);
                box.append (to);
                var sn = new Label (draft.reply_snippet);
                sn.xalign = 0;
                sn.wrap = true;
                sn.lines = 2;
                sn.ellipsize = Pango.EllipsizeMode.END;
                sn.add_css_class ("fedi-reply-snippet");
                box.append (sn);
            }

            cw_entry = new Entry ();
            cw_entry.placeholder_text = _("Content warning");
            cw_entry.changed.connect (validate);
            cw_reveal = new Revealer ();
            cw_reveal.child = cw_entry;
            box.append (cw_reveal);

            text = new TextView ();
            text.wrap_mode = WrapMode.WORD_CHAR;
            text.add_css_class ("fedi-compose-text");
            text.top_margin = 12;
            text.bottom_margin = 12;
            text.left_margin = 12;
            text.right_margin = 12;
            text.buffer.changed.connect (validate);
            placeholder = new Label (_("What is on your mind?"));
            placeholder.add_css_class ("dim-label");
            placeholder.halign = Align.START;
            placeholder.valign = Align.START;
            placeholder.margin_start = 14;
            placeholder.margin_top = 12;
            placeholder.can_target = false;
            var tscroll = new ScrolledWindow ();
            tscroll.hscrollbar_policy = PolicyType.NEVER;
            tscroll.min_content_height = 180;
            tscroll.vexpand = true;
            tscroll.child = text;
            var tover = new Overlay ();
            tover.child = tscroll;
            tover.add_overlay (placeholder);
            tover.add_css_class ("fedi-compose-frame");
            tover.overflow = Overflow.HIDDEN;
            box.append (tover);

            media_box = new FlowBox ();
            media_box.selection_mode = SelectionMode.NONE;
            media_box.max_children_per_line = 4;
            media_box.min_children_per_line = 2;
            media_box.column_spacing = 8;
            media_box.row_spacing = 8;
            media_box.homogeneous = true;
            media_box.visible = false;
            box.append (media_box);

            var chip = new Box (Orientation.HORIZONTAL, 8);
            chip.add_css_class ("fedi-reply-snippet");
            var clock = new Image.from_icon_name ("alarm-symbolic");
            chip.append (clock);
            schedule_label = new Label ("");
            schedule_label.xalign = 0;
            schedule_label.hexpand = true;
            chip.append (schedule_label);
            var change = new Button.with_label (_("Change"));
            change.add_css_class ("flat");
            change.clicked.connect (() => pick_time ());
            chip.append (change);
            var unschedule = new Button.from_icon_name ("window-close-symbolic");
            unschedule.add_css_class ("flat");
            unschedule.tooltip_text = _("Publish Right Away Instead");
            unschedule.clicked.connect (() => set_schedule (null));
            chip.append (unschedule);
            schedule_reveal = new Revealer ();
            schedule_reveal.child = chip;
            box.append (schedule_reveal);

            error = new Label ("");
            error.add_css_class ("error");
            error.wrap = true;
            error.xalign = 0;
            error.visible = false;
            box.append (error);

            var bar = new Box (Orientation.HORIZONTAL, 6);
            attach_button = new Button.from_icon_name ("mail-attachment-symbolic");
            attach_button.add_css_class ("flat");
            attach_button.tooltip_text = _("Add Images or Videos");
            attach_button.clicked.connect (pick_files);
            bar.append (attach_button);
            cw_toggle = new ToggleButton ();
            cw_toggle.icon_name = "dialog-warning-symbolic";
            cw_toggle.add_css_class ("flat");
            cw_toggle.tooltip_text = _("Content Warning");
            cw_toggle.toggled.connect (() => {
                cw_reveal.reveal_child = cw_toggle.active;
                if (cw_toggle.active) cw_entry.grab_focus ();
                validate ();
            });
            bar.append (cw_toggle);
            vis_button = new Button ();
            vis_button.add_css_class ("flat");
            vis_button.clicked.connect (visibility_menu);
            bar.append (vis_button);
            sensitive_toggle = new ToggleButton ();
            sensitive_toggle.icon_name = "view-conceal-symbolic";
            sensitive_toggle.add_css_class ("flat");
            sensitive_toggle.tooltip_text = _("Mark Media as Sensitive");
            sensitive_toggle.visible = false;
            bar.append (sensitive_toggle);
            schedule_button = new Button.from_icon_name ("alarm-symbolic");
            schedule_button.add_css_class ("flat");
            schedule_button.tooltip_text = _("Schedule for Later");
            schedule_button.clicked.connect (() => pick_time ());
            bar.append (schedule_button);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            counter = new Label ("");
            counter.add_css_class ("fedi-counter");
            bar.append (counter);
            spinner = new Spinner ();
            bar.append (spinner);
            post_button = new Button.with_label (reply_id != "" ? _("Reply") : _("Post"));
            post_button.add_css_class ("pill");
            post_button.add_css_class ("suggested-action");
            post_button.tooltip_text = _("Publish (Ctrl+Enter)");
            post_button.clicked.connect (() => send.begin ());
            bar.append (post_button);
            box.append (bar);
            content_box.append (box);

            if (from_draft != null) restore ();
            else if (reply_to != null) prefill ();
            set_visibility (visibility);
            if (schedule != null) set_schedule (schedule);
            text.buffer.changed.connect (queue_save);
            cw_entry.changed.connect (queue_save);
            cw_toggle.toggled.connect (queue_save);
            sensitive_toggle.toggled.connect (queue_save);

            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
                if (ctrl && (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter)) {
                    if (post_button.sensitive) send.begin ();
                    return true;
                }
                return false;
            });
            ((Widget) this).add_controller (keys);
            validate ();
            text.grab_focus ();
        }

        private void prefill () {
            var names = new Gee.ArrayList<string> ();
            if (!session.is_me (reply_to.account)) names.add ("@" + reply_to.account.acct);
            foreach (var m in reply_to.mentions) {
                if (m.id == session.saved.id) continue;
                string n = "@" + m.acct;
                if (!names.contains (n)) names.add (n);
            }
            if (names.size > 0) text.buffer.text = string.joinv (" ", names.to_array ()) + " ";
            if (reply_to.visibility > visibility) visibility = reply_to.visibility;
            if (reply_to.spoiler_text.strip () != "") {
                cw_entry.text = reply_to.spoiler_text;
                cw_toggle.active = true;
            }
            TextIter end;
            text.buffer.get_end_iter (out end);
            text.buffer.place_cursor (end);
        }

        private void restore () {
            text.buffer.text = draft.text;
            visibility = draft.visibility;
            if (draft.spoiler_text.strip () != "") {
                cw_entry.text = draft.spoiler_text;
                cw_toggle.active = true;
            }
            sensitive_toggle.active = draft.sensitive;
            TextIter end;
            text.buffer.get_end_iter (out end);
            text.buffer.place_cursor (end);
        }

        private void queue_save () {
            touched = true;
            if (drafts == null || done) return;
            if (save_id != 0) Source.remove (save_id);
            save_id = Timeout.add (600, () => {
                save_id = 0;
                save_draft ();
                return Source.REMOVE;
            });
        }

        private void save_draft () {
            if (drafts == null || done) return;
            if (save_id != 0) {
                Source.remove (save_id);
                save_id = 0;
            }
            draft.text = text.buffer.text;
            draft.spoiler_text = cw_toggle.active ? cw_entry.text : "";
            draft.visibility = visibility;
            draft.sensitive = sensitive_toggle.active;
            drafts.put (draft, new DateTime.now_utc ().to_unix ());
        }

        private void forget_draft () {
            if (save_id != 0) {
                Source.remove (save_id);
                save_id = 0;
            }
            if (drafts != null) drafts.remove (draft.id);
        }

        private void set_schedule (DateTime? at) {
            scheduled_at = at;
            schedule_reveal.reveal_child = at != null;
            if (at != null) schedule_label.label = _("Publishes %s").printf (Ui.moment (at));
            post_button.label = at != null ? _("Schedule") : (reply_id != "" ? _("Reply") : _("Post"));
            schedule_button.icon_name = "alarm-symbolic";
            if (at != null) schedule_button.add_css_class ("fedi-scheduled-on");
            else schedule_button.remove_css_class ("fedi-scheduled-on");
            validate ();
        }

        private void pick_time () {
            SchedulePicker.ask (application, this, scheduled_at, (at) => {
                set_schedule (at);
                queue_save ();
            }, scheduled_at != null ? _("Publish Right Away") : null, () => set_schedule (null));
        }

        private void set_visibility (Visibility v) {
            visibility = v;
            vis_button.icon_name = v.icon ();
            vis_button.tooltip_text = _("Visibility: %s").printf (v.label ());
        }

        private void visibility_menu () {
            var menu = new ContextMenu (vis_button);
            menu.position = PositionType.TOP;
            Visibility[] all = { Visibility.PUBLIC, Visibility.UNLISTED, Visibility.PRIVATE, Visibility.DIRECT };
            foreach (var v in all) {
                var vv = v;
                menu.add_item (v.label (), v == visibility ? "object-select-symbolic" : v.icon (), () => {
                    set_visibility (vv);
                    queue_save ();
                });
            }
            Ui.popup_menu (menu);
        }

        private int remaining () {
            string spoiler = cw_toggle.active ? cw_entry.text : "";
            return session.info.max_characters - Text.count_chars (text.buffer.text, spoiler, session.info.url_length);
        }

        private void validate () {
            placeholder.visible = text.buffer.text == "";
            int left = remaining ();
            counter.label = left.to_string ();
            counter.tooltip_text = ngettext ("%d character left", "%d characters left", (ulong) int.max (left, 0)).printf (int.max (left, 0));
            if (left < 0) counter.add_css_class ("error");
            else counter.remove_css_class ("error");
            bool busy = false;
            foreach (var u in uploads) if (u.busy) busy = true;
            bool has_content = text.buffer.text.strip () != "" || uploads.size > 0 || carry_media.size > 0;
            post_button.sensitive = !sending && has_content && left >= 0 && !busy;
            attach_button.sensitive = !sending && uploads.size < session.info.max_media;
            sensitive_toggle.visible = uploads.size > 0;
            media_box.visible = uploads.size > 0;
        }

        public void add_shared (string[] uris, string shared_text) {
            if (shared_text != "") {
                text.buffer.text = shared_text;
                TextIter end;
                text.buffer.get_end_iter (out end);
                text.buffer.place_cursor (end);
            }
            foreach (string uri in uris) {
                var file = File.new_for_uri (uri);
                string? ct = null;
                try {
                    ct = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE).get_content_type ();
                } catch (Error e) {
                }
                if (ct == null || !(ContentType.is_mime_type (ct, "image/*") || ContentType.is_mime_type (ct, "video/*") || ContentType.is_mime_type (ct, "audio/*"))) continue;
                if (uploads.size >= session.info.max_media) {
                    show_error (ngettext ("A post can hold %d attachment.", "A post can hold %d attachments.", session.info.max_media).printf (session.info.max_media));
                    break;
                }
                add_upload (file);
            }
        }

        private void pick_files () {
            var dialog = new FileDialog ();
            dialog.title = _("Add Images or Videos");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("Images, Videos and Audio");
            f.add_mime_type ("image/*");
            f.add_mime_type ("video/*");
            f.add_mime_type ("audio/*");
            filters.append (f);
            dialog.filters = filters;
            dialog.open_multiple.begin (this, null, (o, res) => {
                try {
                    var files = dialog.open_multiple.end (res);
                    if (files == null) return;
                    for (uint i = 0; i < files.get_n_items (); i++) {
                        if (uploads.size >= session.info.max_media) {
                            show_error (ngettext ("A post can hold %d attachment.", "A post can hold %d attachments.", session.info.max_media).printf (session.info.max_media));
                            break;
                        }
                        add_upload ((File) files.get_item (i));
                    }
                } catch (Error e) {
                }
            });
        }

        private void add_upload (File file) {
            var u = new Upload ();
            u.file = file;
            var over = new Overlay ();
            over.add_css_class ("fedi-upload");
            over.overflow = Overflow.HIDDEN;
            over.set_size_request (110, 110);
            var pic = new Picture ();
            pic.content_fit = ContentFit.COVER;
            pic.can_shrink = true;
            string? path = file.get_path ();
            bool image = false;
            try {
                var info = file.query_info (FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
                string? ct = info.get_content_type ();
                image = ct != null && ContentType.is_mime_type (ct, "image/*");
            } catch (Error e) {
            }
            if (image && path != null) pic.set_filename (path);
            over.child = pic;
            if (!image) {
                var ic = new Image.from_icon_name ("video-x-generic-symbolic");
                ic.pixel_size = 24;
                ic.halign = Align.CENTER;
                ic.valign = Align.CENTER;
                over.add_overlay (ic);
            }
            var spin = new Spinner ();
            spin.spinning = true;
            spin.halign = Align.CENTER;
            spin.valign = Align.CENTER;
            over.add_overlay (spin);
            var remove_btn = new Button.from_icon_name ("window-close-symbolic");
            remove_btn.add_css_class ("circular");
            remove_btn.add_css_class ("osd");
            remove_btn.halign = Align.END;
            remove_btn.valign = Align.START;
            remove_btn.margin_top = 4;
            remove_btn.margin_end = 4;
            remove_btn.tooltip_text = _("Remove");
            remove_btn.clicked.connect (() => {
                u.cancel.cancel ();
                uploads.remove (u);
                media_box.remove (u.tile);
                validate ();
            });
            over.add_overlay (remove_btn);
            var alt = new Button.with_label (_("ALT"));
            alt.add_css_class ("fedi-alt-button");
            alt.halign = Align.START;
            alt.valign = Align.END;
            alt.margin_start = 4;
            alt.margin_bottom = 4;
            alt.tooltip_text = _("Describe for People Who Cannot See It");
            alt.clicked.connect (() => describe_upload (u, alt));
            over.add_overlay (alt);
            var child = new FlowBoxChild ();
            child.child = over;
            child.focusable = false;
            u.tile = child;
            uploads.add (u);
            media_box.append (child);
            validate ();
            session.client.upload.begin (file, u.description, u.cancel, (o, res) => {
                try {
                    u.attachment = session.client.upload.end (res);
                    u.busy = false;
                    spin.visible = false;
                    if (u.description != "") session.client.update_media_description.begin (u.attachment.id, u.description);
                } catch (IOError.CANCELLED e) {
                    return;
                } catch (Error e) {
                    uploads.remove (u);
                    media_box.remove (u.tile);
                    show_error (_("%s could not be uploaded: %s").printf (file.get_basename () ?? "", TimelineView.describe (e)));
                }
                validate ();
            });
        }

        private void describe_upload (Upload u, Button alt) {
            var dlg = new ConfirmDialog (application, _("Describe This Media"), null,
                _("A description helps people who use a screen reader or cannot load images."), _("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.modal = true;
            var group = new PreferencesGroup ();
            var row = new EntryRow (_("Description"));
            row.text = u.description;
            group.add_row (row);
            dlg.custom_area.append (group);
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                u.description = row.text.strip ();
                if (u.description != "") alt.add_css_class ("fedi-on");
                else alt.remove_css_class ("fedi-on");
                if (u.attachment != null) {
                    session.client.update_media_description.begin (u.attachment.id, u.description, (o, res) => {
                        try {
                            session.client.update_media_description.end (res);
                        } catch (Error e) {
                            show_error (_("The description was not saved: %s").printf (e.message));
                        }
                    });
                }
            });
            dlg.present ();
            row.grab_focus ();
        }

        private void show_error (string message) {
            error.label = message;
            error.visible = true;
        }

        private async void send () {
            if (sending) return;
            if (scheduled_at != null) {
                string? why = Requests.schedule_problem (scheduled_at, new DateTime.now_local ());
                if (why != null) {
                    show_error (why);
                    return;
                }
            }
            sending = true;
            error.visible = false;
            spinner.spinning = true;
            text.sensitive = false;
            validate ();
            var media = new Gee.ArrayList<string> ();
            media.add_all (carry_media);
            foreach (var u in uploads) if (u.attachment != null) media.add (u.attachment.id);
            var p = Requests.status (text.buffer.text, cw_toggle.active ? cw_entry.text : "", visibility, sensitive_toggle.active, reply_id, media, scheduled_at);
            try {
                if (scheduled_at != null) {
                    var sch = yield session.client.post_scheduled (p, idempotency);
                    if (draft.replaces_scheduled != "") {
                        try {
                            yield session.client.cancel_scheduled (draft.replaces_scheduled);
                        } catch (ApiError.NOT_FOUND e) {
                        }
                    }
                    done = true;
                    forget_draft ();
                    scheduled (sch);
                } else {
                    var s = yield session.client.post (p, idempotency);
                    if (draft.replaces_scheduled != "") {
                        try {
                            yield session.client.cancel_scheduled (draft.replaces_scheduled);
                        } catch (ApiError.NOT_FOUND e) {
                        }
                    }
                    done = true;
                    forget_draft ();
                    posted (s);
                }
                close ();
            } catch (Error e) {
                show_error ((scheduled_at != null ? _("The post was not scheduled: %s") : _("The post was not published: %s")).printf (TimelineView.describe (e)));
            }
            sending = false;
            spinner.spinning = false;
            text.sensitive = true;
            validate ();
        }

        public override void close_dialog () {
            bool dirty = !done && (text.buffer.text.strip () != "" && (reply_id == "" || text.buffer.text.strip ().split (" ").length > count_mentions ()) || (cw_toggle.active && cw_entry.text.strip () != "") || uploads.size > 0);
            if (!dirty) {
                foreach (var u in uploads) u.cancel.cancel ();
                if (!done && touched) forget_draft ();
                done = true;
                close ();
                return;
            }
            if (drafts == null) {
                var dlg = new ConfirmDialog (application, _("Discard This Post?"), "user-trash-symbolic",
                    _("What you wrote is not saved."), _("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
                dlg.transient_for = this;
                dlg.modal = true;
                dlg.response.connect ((r) => {
                    if (r != ConfirmDialog.Response.PRIMARY) return;
                    foreach (var u in uploads) u.cancel.cancel ();
                    done = true;
                    close ();
                });
                dlg.present ();
                return;
            }
            var ask = new ConfirmDialog (application, _("Keep This Draft?"), "document-new",
                uploads.size > 0 ? _("You can finish it later from Drafts. Attachments are not kept in drafts.") : _("You can finish it later from Drafts."), _("Keep Draft"), ConfirmDialog.ActionStyle.SUGGESTED);
            ask.transient_for = this;
            ask.modal = true;
            ask.set_secondary (_("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            ask.response.connect ((r) => {
                if (r == ConfirmDialog.Response.CANCEL) return;
                foreach (var u in uploads) u.cancel.cancel ();
                if (r == ConfirmDialog.Response.PRIMARY) save_draft ();
                else forget_draft ();
                done = true;
                close ();
            });
            ask.present ();
        }

        private int count_mentions () {
            int n = 0;
            foreach (string w in text.buffer.text.strip ().split (" ")) if (w.has_prefix ("@")) n++;
            return n;
        }
    }
}

namespace Singularity.Apps.Fediverse {

    public class SchedulePicker : Object {
        public delegate void Picked (DateTime at);
        public delegate void Cleared ();

        public static void ask (Gtk.Application app, Gtk.Window parent, DateTime? current, owned Picked done, string? clear_label = null, owned Cleared? cleared = null) {
            var start = (current ?? new DateTime.now_local ().add_hours (1)).to_local ();
            var dlg = new ConfirmDialog (app, _("Schedule Post"), null,
                _("The server publishes the post at the chosen time, even when this app is closed."), _("Schedule"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = parent;
            dlg.modal = true;
            var cal = new Gtk.Calendar ();
            cal.select_day (start);
            cal.halign = Align.CENTER;
            dlg.custom_area.append (cal);
            var group = new PreferencesGroup ();
            var row = new ActionRow (_("Time"), null, "alarm-symbolic");
            var picker = new TimePicker ("%02d:%02d".printf (start.get_hour (), start.get_minute ()));
            row.add_suffix (picker);
            group.add_row (row);
            dlg.custom_area.append (group);
            var problem = new Label ("");
            problem.add_css_class ("error");
            problem.wrap = true;
            problem.visible = false;
            dlg.custom_area.append (problem);
            DateTime? chosen = null;
            Cleared check = () => {
                var d = cal.get_date ().to_local ();
                var parts = picker.time.split (":");
                chosen = new DateTime.local (d.get_year (), d.get_month (), d.get_day_of_month (), int.parse (parts[0]), parts.length > 1 ? int.parse (parts[1]) : 0, 0);
                string? why = Requests.schedule_problem (chosen, new DateTime.now_local ());
                problem.label = why ?? "";
                problem.visible = why != null;
                dlg.primary_sensitive = why == null;
            };
            cal.day_selected.connect (() => check ());
            picker.changed.connect (() => check ());
            check ();
            if (clear_label != null) dlg.set_secondary (clear_label);
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY && chosen != null && Requests.schedule_problem (chosen, new DateTime.now_local ()) == null) done (chosen);
                else if (r == ConfirmDialog.Response.SECONDARY && cleared != null) cleared ();
            });
            dlg.present ();
        }
    }
}
