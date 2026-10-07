using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Fediverse {

    public class EmojiPaintable : Object, Gdk.Paintable {
        private Gdk.Texture? texture;
        private int size;

        public EmojiPaintable (string url, int size) {
            this.size = size;
            ImageCache.texture.begin (url, (o, res) => {
                texture = ImageCache.texture.end (res);
                if (texture != null) invalidate_contents ();
            });
        }

        public int get_intrinsic_width () {
            return size;
        }

        public int get_intrinsic_height () {
            return size;
        }

        public Gdk.PaintableFlags get_flags () {
            return Gdk.PaintableFlags.STATIC_SIZE;
        }

        public void snapshot (Gdk.Snapshot snap, double width, double height) {
            if (texture == null) return;
            double scale = double.min (width / texture.width, height / texture.height);
            double w = texture.width * scale, h = texture.height * scale;
            var gs = (Gtk.Snapshot) snap;
            gs.save ();
            gs.translate ({ (float) ((width - w) / 2), (float) ((height - h) / 2) });
            texture.snapshot (snap, w, h);
            gs.restore ();
        }
    }

    public class RichText : TextView {
        public signal void activated ();

        private weak Navigator? nav;
        private TextTag? link_style;
        private ulong accent_handler;

        public RichText (Content content, Navigator? nav, string? css = null) {
            this.nav = nav;
            editable = false;
            cursor_visible = false;
            wrap_mode = WrapMode.WORD_CHAR;
            focusable = false;
            hexpand = true;
            accepts_tab = false;
            add_css_class ("fedi-text");
            if (css != null) add_css_class (css);
            render (content);
            var click = new GestureClick ();
            click.released.connect ((n, x, y) => {
                TextIter a, b;
                if (buffer.get_selection_bounds (out a, out b)) return;
                var s = span_at (x, y);
                if (s == null) {
                    activated ();
                    return;
                }
                follow (s);
            });
            add_controller (click);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => {
                var s = span_at (x, y);
                set_cursor_from_name (s != null && s.kind != SpanKind.EMOJI ? "pointer" : null);
            });
            add_controller (motion);
            var sm = Singularity.Style.StyleManager.get_default ();
            accent_handler = sm.notify["accent-hex"].connect (() => {
                if (link_style != null) link_style.foreground = sm.accent_hex;
            });
        }

        public override void dispose () {
            if (accent_handler != 0) {
                Singularity.Style.StyleManager.get_default ().disconnect (accent_handler);
                accent_handler = 0;
            }
            base.dispose ();
        }

        private void follow (Span s) {
            if (nav == null) return;
            switch (s.kind) {
                case SpanKind.LINK:
                    nav.open_link (s.href);
                    break;
                case SpanKind.MENTION:
                    nav.open_mention (s.target, s.href);
                    break;
                case SpanKind.HASHTAG:
                    nav.open_tag (s.target);
                    break;
                default:
                    break;
            }
        }

        private Span? span_at (double x, double y) {
            int bx, by;
            window_to_buffer_coords (TextWindowType.WIDGET, (int) x, (int) y, out bx, out by);
            TextIter it;
            if (!get_iter_at_location (out it, bx, by)) return null;
            foreach (var tag in it.get_tags ()) {
                var s = tag.get_data<Span> ("span");
                if (s != null) return s;
            }
            return null;
        }

        private TextTag named (string name) {
            var table = buffer.tag_table;
            var t = table.lookup (name);
            if (t != null) return t;
            t = new TextTag (name);
            switch (name) {
                case "bold":
                    t.weight = 700;
                    break;
                case "italic":
                    t.style = Pango.Style.ITALIC;
                    break;
                case "code":
                    t.family = "monospace";
                    break;
                case "strike":
                    t.strikethrough = true;
                    break;
                case "underline":
                    t.underline = Pango.Underline.SINGLE;
                    break;
                case "quote":
                    t.left_margin = 14;
                    t.style = Pango.Style.ITALIC;
                    break;
                case "link":
                    t.foreground = Singularity.Style.StyleManager.get_default ().accent_hex;
                    link_style = t;
                    break;
            }
            table.add (t);
            return t;
        }

        public void show_content (Content content) {
            buffer.text = "";
            render (content);
        }

        private void render (Content content) {
            var buf = buffer;
            TextIter end;
            foreach (var s in content.spans) {
                buf.get_end_iter (out end);
                if (s.kind == SpanKind.EMOJI) {
                    buf.insert_paintable (end, new EmojiPaintable (s.href, 20));
                    continue;
                }
                int start_offset = end.get_offset ();
                buf.insert (ref end, s.text, -1);
                TextIter from;
                buf.get_iter_at_offset (out from, start_offset);
                buf.get_end_iter (out end);
                if (SpanStyle.BOLD in s.style) buf.apply_tag (named ("bold"), from, end);
                if (SpanStyle.ITALIC in s.style) buf.apply_tag (named ("italic"), from, end);
                if (SpanStyle.CODE in s.style) buf.apply_tag (named ("code"), from, end);
                if (SpanStyle.STRIKE in s.style) buf.apply_tag (named ("strike"), from, end);
                if (SpanStyle.UNDERLINE in s.style) buf.apply_tag (named ("underline"), from, end);
                if (SpanStyle.QUOTE in s.style) buf.apply_tag (named ("quote"), from, end);
                if (s.href != "") {
                    buf.apply_tag (named ("link"), from, end);
                    var tag = new TextTag (null);
                    buf.tag_table.add (tag);
                    tag.set_data<Span> ("span", s);
                    buf.apply_tag (tag, from, end);
                }
            }
        }
    }

    namespace Ui {
        public Label dim (string text, bool caption = true) {
            var l = new Label (text);
            l.add_css_class ("dim-label");
            if (caption) l.add_css_class ("caption");
            l.xalign = 0;
            return l;
        }

        public Avatar avatar (string url, int size) {
            var a = new Avatar (size);
            if (url != "") {
                ImageCache.fetch.begin (url, (o, res) => {
                    string? path = ImageCache.fetch.end (res);
                    if (path != null) a.set_from_file (path);
                });
            }
            return a;
        }

        public void load_picture (Picture pic, string url) {
            ImageCache.texture.begin (url, (o, res) => {
                var t = ImageCache.texture.end (res);
                if (t != null) pic.paintable = t;
            });
        }

        public string remaining (DateTime? end) {
            if (end == null) return "";
            int64 secs = end.to_unix () - new DateTime.now_utc ().to_unix ();
            if (secs <= 0) return _("Closed");
            if (secs < 3600) return _("Closes in %d minutes").printf ((int) int64.max (1, secs / 60));
            if (secs < 86400) return _("Closes in %d hours").printf ((int) (secs / 3600));
            return _("Closes in %d days").printf ((int) (secs / 86400));
        }

        public string until (DateTime? at) {
            if (at == null) return "";
            int64 secs = at.to_unix () - new DateTime.now_utc ().to_unix ();
            if (secs < 60) return _("in less than a minute");
            if (secs < 3600) return ngettext ("in %d minute", "in %d minutes", (ulong) (secs / 60)).printf ((int) (secs / 60));
            if (secs < 86400) return ngettext ("in %d hour", "in %d hours", (ulong) (secs / 3600)).printf ((int) (secs / 3600));
            return ngettext ("in %d day", "in %d days", (ulong) (secs / 86400)).printf ((int) (secs / 86400));
        }

        public string moment (DateTime? at) {
            if (at == null) return "";
            return at.to_local ().format ("%a %-d %b %Y, %H:%M");
        }

        public Button tool_button (string icon, string tooltip) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.add_css_class ("fedi-action");
            b.tooltip_text = tooltip;
            b.valign = Align.CENTER;
            return b;
        }

        public Label preview (string text) {
            var l = new Label (text);
            l.xalign = 0;
            l.wrap = true;
            l.wrap_mode = Pango.WrapMode.WORD_CHAR;
            l.lines = 3;
            l.ellipsize = Pango.EllipsizeMode.END;
            return l;
        }

        public Widget visibility_label (Visibility v) {
            var box = new Box (Orientation.HORIZONTAL, 4);
            var ic = new Image.from_icon_name (v.icon ());
            ic.add_css_class ("dim-label");
            ic.pixel_size = 12;
            box.append (ic);
            box.append (dim (v.label ()));
            return box;
        }

        public void popup_menu (ContextMenu menu) {
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }
    }

    public class MediaGrid : Box {
        public MediaGrid (Status s, Navigator nav) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("fedi-media-grid");
            overflow = Overflow.HIDDEN;
            var overlay = new Overlay ();
            var grid = new Grid ();
            grid.column_spacing = 4;
            grid.row_spacing = 4;
            grid.column_homogeneous = true;
            int n = s.media.size;
            int height = n == 1 ? 280 : (n == 2 ? 200 : 140);
            for (int i = 0; i < n; i++) {
                var m = s.media[i];
                int index = i;
                var pic = new Picture ();
                pic.content_fit = ContentFit.COVER;
                pic.can_shrink = true;
                pic.hexpand = true;
                pic.set_size_request (-1, height);
                pic.alternative_text = m.description != "" ? m.description : null;
                Ui.load_picture (pic, m.preview_url);
                var inner = new Overlay ();
                inner.child = pic;
                if (m.kind != MediaType.IMAGE) {
                    var play = new Image.from_icon_name (m.kind == MediaType.AUDIO ? "audio-x-generic-symbolic" : "media-playback-start-symbolic");
                    play.pixel_size = 24;
                    play.add_css_class ("fedi-media-badge");
                    play.halign = Align.CENTER;
                    play.valign = Align.CENTER;
                    play.can_target = false;
                    inner.add_overlay (play);
                }
                if (m.description != "") {
                    var alt = new Label ("ALT");
                    alt.add_css_class ("fedi-alt-badge");
                    alt.halign = Align.START;
                    alt.valign = Align.END;
                    alt.margin_start = 8;
                    alt.margin_bottom = 8;
                    alt.can_target = false;
                    inner.add_overlay (alt);
                }
                var b = new Button ();
                b.child = inner;
                b.add_css_class ("fedi-media");
                b.tooltip_text = m.description != "" ? m.description : _("Open Media");
                b.clicked.connect (() => nav.view_media (s.media, index));
                int col = n == 3 && i == 0 ? 0 : i % 2;
                int row = n == 3 ? (i == 0 ? 0 : i - 1) : i / 2;
                if (n == 3 && i == 0) {
                    pic.set_size_request (-1, height * 2 + 4);
                    grid.attach (b, 0, 0, 1, 2);
                } else if (n == 3) {
                    grid.attach (b, 1, row, 1, 1);
                } else {
                    grid.attach (b, col, row, 1, 1);
                }
            }
            overlay.child = grid;
            if (s.sensitive) {
                var cover = new Button ();
                cover.add_css_class ("fedi-sensitive");
                var box = new Box (Orientation.VERTICAL, 4);
                box.valign = Align.CENTER;
                var t = new Label (_("Sensitive Content"));
                t.add_css_class ("heading");
                box.append (t);
                box.append (new Label (_("Click to show")));
                cover.child = box;
                cover.clicked.connect (() => cover.visible = false);
                overlay.add_overlay (cover);
            }
            append (overlay);
        }
    }

    public class PollView : Box {
        private Poll poll;
        private Status status;
        private Navigator nav;

        public PollView (Status status, Poll poll, Navigator nav) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            this.status = status;
            this.poll = poll;
            this.nav = nav;
            add_css_class ("fedi-poll");
            build ();
        }

        private void build () {
            Widget? c;
            while ((c = get_first_child ()) != null) remove (c);
            var sess = nav.session_for (status);
            bool own = sess != null && sess.is_me (status.account);
            bool results = poll.expired || poll.voted || own;
            var chosen = new Gee.ArrayList<int> ();
            CheckButton? group = null;
            Button? vote = null;
            for (int i = 0; i < poll.options.size; i++) {
                var opt = poll.options[i];
                int index = i;
                var title = Content.from_text (opt.title, poll.emojis).plain ();
                if (results) {
                    var row = new Box (Orientation.VERTICAL, 2);
                    var line = new Box (Orientation.HORIZONTAL, 6);
                    var l = new Label (title);
                    l.xalign = 0;
                    l.hexpand = true;
                    l.wrap = true;
                    if (poll.own_votes.contains (i)) l.add_css_class ("heading");
                    line.append (l);
                    if (poll.own_votes.contains (i)) {
                        var mine = new Image.from_icon_name ("object-select-symbolic");
                        mine.tooltip_text = _("Your choice");
                        line.append (mine);
                    }
                    line.append (Ui.dim ("%d%%".printf ((int) Math.round (poll.share (i) * 100)), false));
                    row.append (line);
                    var bar = new ProgressBar ();
                    bar.fraction = poll.share (i);
                    row.append (bar);
                    append (row);
                } else {
                    var cb = new CheckButton.with_label (title);
                    if (!poll.multiple) {
                        if (group == null) group = cb;
                        else cb.group = group;
                    }
                    cb.toggled.connect (() => {
                        if (cb.active && !chosen.contains (index)) chosen.add (index);
                        if (!cb.active) chosen.remove (index);
                        if (vote != null) vote.sensitive = chosen.size > 0;
                    });
                    append (cb);
                }
            }
            var foot = new Box (Orientation.HORIZONTAL, 8);
            string people = poll.voters_count >= 0 ? ngettext ("%s person", "%s people", (ulong) poll.voters_count).printf (Text.compact (poll.voters_count)) : ngettext ("%s vote", "%s votes", (ulong) poll.votes_count).printf (Text.compact (poll.votes_count));
            string when = poll.expired ? _("Closed") : Ui.remaining (poll.expires_at);
            var info = Ui.dim (when != "" ? "%s · %s".printf (people, when) : people);
            info.hexpand = true;
            foot.append (info);
            if (!results) {
                vote = new Button.with_label (_("Vote"));
                vote.add_css_class ("pill");
                vote.sensitive = false;
                vote.clicked.connect (() => {
                    var vs = nav.session_for (status);
                    if (vs == null) return;
                    vote.sensitive = false;
                    vs.client.vote.begin (poll.id, chosen, (o, res) => {
                        try {
                            var p = vs.client.vote.end (res);
                            if (p != null) poll = p;
                            else poll.voted = true;
                            build ();
                        } catch (Error e) {
                            vote.sensitive = true;
                            nav.show_error (_("Your vote was not counted: %s").printf (e.message));
                        }
                    });
                });
                foot.append (vote);
            }
            append (foot);
        }
    }

    public class StatusView : Box {
        public Status status;
        private Navigator nav;
        private Box body;
        private RichText? original_text;
        private Content? original_content;
        private Content? translated_content;
        private bool showing_translation;
        private Box? translate_note;
        private Label? translate_label;
        private Button? translate_toggle;
        private PostTranslation? translation;
        private bool translating;
        private Button reply_btn;
        private Button boost_btn;
        private Button fav_btn;
        private Button mark_btn;

        public StatusView (Status status, Navigator nav, bool focused = false, bool compact = false, string filter_note = "") {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            this.status = status;
            this.nav = nav;
            add_css_class ("fedi-status");
            if (focused) add_css_class ("fedi-focused");
            var s = status.shown ();
            var sess = nav.session_for (status);
            string host = sess != null ? sess.host () : "";
            Box outer = this;
            if (filter_note != "") {
                var cover = new Box (Orientation.HORIZONTAL, 8);
                cover.add_css_class ("fedi-cw");
                var warn = new Image.from_icon_name ("dialog-warning-symbolic");
                warn.valign = Align.CENTER;
                cover.append (warn);
                var what = new Label (_("Filtered: %s").printf (filter_note));
                what.xalign = 0;
                what.hexpand = true;
                what.wrap = true;
                what.add_css_class ("fedi-cw-text");
                cover.append (what);
                var show = new Button.with_label (_("Show Anyway"));
                show.add_css_class ("pill");
                show.valign = Align.CENTER;
                cover.append (show);
                append (cover);
                var hidden = new Box (Orientation.VERTICAL, 6);
                var reveal = new Revealer ();
                reveal.transition_type = RevealerTransitionType.SLIDE_DOWN;
                reveal.child = hidden;
                show.clicked.connect (() => {
                    reveal.reveal_child = !reveal.reveal_child;
                    show.label = reveal.reveal_child ? _("Hide Again") : _("Show Anyway");
                });
                append (reveal);
                outer = hidden;
            }

            if (status.reblog != null) {
                var boosted = new Box (Orientation.HORIZONTAL, 6);
                boosted.margin_start = 26;
                var ic = new Image.from_icon_name ("media-playlist-repeat-symbolic");
                ic.add_css_class ("dim-label");
                boosted.append (ic);
                var who = new Button.with_label (_("%s boosted").printf (Content.from_text (status.account.name (), status.account.emojis).plain ()));
                who.add_css_class ("flat");
                who.add_css_class ("fedi-boosted-by");
                who.clicked.connect (() => nav.open_account (status.account));
                boosted.append (who);
                outer.append (boosted);
            }

            var main = new Box (Orientation.HORIZONTAL, 12);
            var av = new Button ();
            av.child = Ui.avatar (s.account.avatar, compact ? 36 : 46);
            av.add_css_class ("flat");
            av.add_css_class ("fedi-avatar-button");
            av.valign = Align.START;
            av.tooltip_text = _("Open Profile of %s").printf (s.account.name ());
            av.clicked.connect (() => nav.open_account (s.account));
            main.append (av);

            var col = new Box (Orientation.VERTICAL, 6);
            col.hexpand = true;
            var head = new Box (Orientation.HORIZONTAL, 6);
            var names = new Box (Orientation.VERTICAL, 0);
            names.hexpand = true;
            var name = new RichText (Content.from_text (s.account.name (), s.account.emojis), null, "fedi-name");
            name.activated.connect (() => nav.open_account (s.account));
            names.append (name);
            var handle = Ui.dim (s.account.handle (host));
            handle.ellipsize = Pango.EllipsizeMode.END;
            names.append (handle);
            head.append (names);
            if (status.merged) {
                var saved = nav.saved_account (status.via);
                if (saved != null) {
                    var badge = new Box (Orientation.HORIZONTAL, 4);
                    badge.add_css_class ("fedi-via");
                    badge.valign = Align.START;
                    if (saved.avatar != "") badge.append (Ui.avatar (saved.avatar, 16));
                    var who = new Label ("@" + saved.username);
                    who.add_css_class ("caption");
                    badge.append (who);
                    badge.tooltip_text = _("From the home timeline of %s").printf (saved.handle ());
                    badge.update_property (AccessibleProperty.LABEL, badge.tooltip_text, -1);
                    head.append (badge);
                }
            }
            if (s.visibility != Visibility.PUBLIC) {
                var vis = new Image.from_icon_name (s.visibility.icon ());
                vis.add_css_class ("dim-label");
                vis.tooltip_text = s.visibility.label ();
                vis.valign = Align.START;
                head.append (vis);
            }
            string time = Text.relative_time (s.created_at);
            if (s.edited_at != null) time = _("%s, edited").printf (time);
            var when = Ui.dim (time);
            when.valign = Align.START;
            if (s.created_at != null) when.tooltip_text = s.created_at.to_local ().format ("%c");
            head.append (when);
            col.append (head);

            if (s.in_reply_to_id != "" && !focused) {
                string target = "";
                foreach (var m in s.mentions) if (m.id == s.in_reply_to_account_id) target = "@" + m.acct;
                if (s.in_reply_to_account_id == s.account.id) target = _("themselves");
                if (target != "") col.append (Ui.dim (_("Replying to %s").printf (target)));
            }

            body = new Box (Orientation.VERTICAL, 8);
            var content = s.body ();
            if (!content.is_empty ()) {
                original_content = content;
                original_text = new RichText (content, nav, focused ? "fedi-focused-text" : null);
                original_text.activated.connect (() => nav.open_status (status));
                body.append (original_text);
            }
            if (s.media.size > 0) body.append (new MediaGrid (s, nav));
            if (s.poll != null) body.append (new PollView (s, s.poll, nav));

            if (s.spoiler_text.strip () != "") {
                var cw = new Box (Orientation.HORIZONTAL, 8);
                cw.add_css_class ("fedi-cw");
                var cwl = new RichText (Content.from_text (s.spoiler_text, s.emojis), nav, "fedi-cw-text");
                cwl.activated.connect (() => nav.open_status (status));
                cw.append (cwl);
                var reveal = new Revealer ();
                reveal.child = body;
                reveal.transition_type = RevealerTransitionType.SLIDE_DOWN;
                var toggle = new Button.with_label (_("Show More"));
                toggle.add_css_class ("pill");
                toggle.valign = Align.CENTER;
                toggle.clicked.connect (() => {
                    reveal.reveal_child = !reveal.reveal_child;
                    toggle.label = reveal.reveal_child ? _("Show Less") : _("Show More");
                });
                cw.append (toggle);
                col.append (cw);
                col.append (reveal);
            } else {
                col.append (body);
            }

            if (focused) {
                string detail = "";
                if (s.created_at != null) detail = s.created_at.to_local ().format ("%e %B %Y, %H:%M").strip ();
                col.append (Ui.dim (detail));
            }

            var actions = new Box (Orientation.HORIZONTAL, 2);
            actions.add_css_class ("fedi-actions");
            reply_btn = action_button ("mail-reply-sender-symbolic", _("Reply"));
            reply_btn.clicked.connect (() => nav.reply (s));
            actions.append (reply_btn);
            boost_btn = action_button ("media-playlist-repeat-symbolic", _("Boost"));
            boost_btn.sensitive = s.visibility == Visibility.PUBLIC || s.visibility == Visibility.UNLISTED;
            if (!boost_btn.sensitive) boost_btn.tooltip_text = _("This post cannot be boosted");
            boost_btn.clicked.connect (() => toggle ("reblog"));
            actions.append (boost_btn);
            fav_btn = action_button ("starred-symbolic", _("Favourite"));
            fav_btn.clicked.connect (() => toggle ("favourite"));
            actions.append (fav_btn);
            mark_btn = action_button ("user-bookmarks-symbolic", _("Bookmark"));
            mark_btn.clicked.connect (() => toggle ("bookmark"));
            actions.append (mark_btn);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            actions.append (spacer);
            var more = action_button ("view-more-symbolic", _("More"));
            more.clicked.connect (() => more_menu (more));
            actions.append (more);
            col.append (actions);
            main.append (col);
            outer.append (main);
            sync ();
        }

        public bool can_translate () {
            var s = status.shown ();
            if (original_text == null) return false;
            return !Requests.same_language (s.language, Requests.user_language ());
        }

        public void translate () {
            if (original_text == null || translating) return;
            if (translation != null) {
                show_translation (!showing_translation);
                return;
            }
            var sess = nav.session_for (status);
            if (sess == null) return;
            var s = status.shown ();
            string lang = Requests.user_language ();
            ensure_note ();
            translating = true;
            translate_label.label = _("Translating…");
            translate_toggle.visible = false;
            translate_note.visible = true;
            if (sess.info.translation) {
                sess.client.translate.begin (s.id, lang, (o, res) => {
                    try {
                        translated (sess.client.translate.end (res));
                    } catch (Error e) {
                        through_app (s, lang);
                    }
                });
            } else {
                through_app (s, lang);
            }
        }

        private void through_app (Status s, string lang) {
            string text = s.body ().plain ();
            if (s.spoiler_text.strip () != "") text = s.spoiler_text.strip () + "\n\n" + text;
            TranslateBridge.translate.begin (text, lang, (o, res) => {
                try {
                    translated (TranslateBridge.translate.end (res));
                } catch (Error e) {
                    translating = false;
                    translate_note.visible = false;
                    nav.show_error (_("The post could not be translated: %s").printf (e.message));
                }
            });
        }

        private void ensure_note () {
            if (translate_note != null) return;
            translate_note = new Box (Orientation.HORIZONTAL, 6);
            translate_note.add_css_class ("fedi-translation-note");
            var ic = new Image.from_icon_name ("preferences-desktop-locale-symbolic");
            ic.add_css_class ("dim-label");
            translate_note.append (ic);
            translate_label = Ui.dim ("");
            translate_label.hexpand = true;
            translate_label.wrap = true;
            translate_note.append (translate_label);
            translate_toggle = new Button.with_label (_("Show Original"));
            translate_toggle.add_css_class ("flat");
            translate_toggle.add_css_class ("fedi-boosted-by");
            translate_toggle.clicked.connect (() => show_translation (!showing_translation));
            translate_note.append (translate_toggle);
            body.insert_child_after (translate_note, original_text);
        }

        private void translated (PostTranslation t) {
            translating = false;
            translation = t;
            var s = status.shown ();
            translated_content = t.html ? Content.parse (t.content, s.emojis, s.mentions) : Content.from_text (t.content, s.emojis);
            string from = t.detected != "" ? t.detected : s.language;
            string by = t.provider != "" ? t.provider : _("the server");
            translate_label.label = from != "" ? _("Translated from %s by %s").printf (Requests.language_name (from), by) : _("Translated by %s").printf (by);
            translate_toggle.visible = true;
            show_translation (true);
        }

        private void show_translation (bool on) {
            if (translated_content == null) return;
            showing_translation = on;
            original_text.show_content (on ? translated_content : original_content);
            translate_toggle.label = on ? _("Show Original") : _("Show Translation");
        }

        private Button action_button (string icon, string tooltip) {
            var b = new Button ();
            var box = new Box (Orientation.HORIZONTAL, 6);
            box.append (new Image.from_icon_name (icon));
            var count = new Label ("");
            count.add_css_class ("caption");
            count.add_css_class ("fedi-count");
            count.visible = false;
            box.append (count);
            b.child = box;
            b.set_data<Label> ("count", count);
            b.add_css_class ("flat");
            b.add_css_class ("fedi-action");
            b.tooltip_text = tooltip;
            return b;
        }

        private static void set_count (Button b, int64 n) {
            var l = b.get_data<Label> ("count");
            l.label = Text.compact (n);
            l.visible = n > 0;
        }

        private static void set_on (Button b, bool on) {
            if (on) b.add_css_class ("fedi-on");
            else b.remove_css_class ("fedi-on");
        }

        private void sync () {
            var s = status.shown ();
            set_count (reply_btn, s.replies_count);
            set_count (boost_btn, s.reblogs_count);
            set_count (fav_btn, s.favourites_count);
            set_on (boost_btn, s.reblogged);
            set_on (fav_btn, s.favourited);
            set_on (mark_btn, s.bookmarked);
            fav_btn.tooltip_text = s.favourited ? _("Remove Favourite") : _("Favourite");
            if (boost_btn.sensitive) boost_btn.tooltip_text = s.reblogged ? _("Undo Boost") : _("Boost");
            mark_btn.tooltip_text = s.bookmarked ? _("Remove Bookmark") : _("Bookmark");
        }

        private void toggle (string what) {
            var sess = nav.session_for (status);
            if (sess == null) return;
            var s = status.shown ();
            bool on;
            string verb;
            switch (what) {
                case "reblog":
                    on = !s.reblogged;
                    s.reblogged = on;
                    s.reblogs_count = int64.max (0, s.reblogs_count + (on ? 1 : -1));
                    verb = on ? "reblog" : "unreblog";
                    break;
                case "favourite":
                    on = !s.favourited;
                    s.favourited = on;
                    s.favourites_count = int64.max (0, s.favourites_count + (on ? 1 : -1));
                    verb = on ? "favourite" : "unfavourite";
                    break;
                default:
                    on = !s.bookmarked;
                    s.bookmarked = on;
                    verb = on ? "bookmark" : "unbookmark";
                    break;
            }
            sync ();
            sess.client.act.begin (s.id, verb, (o, res) => {
                try {
                    var fresh = sess.client.act.end (res).shown ();
                    if (fresh.id == s.id) {
                        s.favourited = fresh.favourited;
                        s.bookmarked = fresh.bookmarked;
                        s.favourites_count = fresh.favourites_count;
                        if (what != "reblog") {
                            s.reblogged = fresh.reblogged;
                            s.reblogs_count = fresh.reblogs_count;
                        }
                    }
                } catch (Error e) {
                    switch (what) {
                        case "reblog":
                            s.reblogged = !on;
                            s.reblogs_count = int64.max (0, s.reblogs_count + (on ? -1 : 1));
                            break;
                        case "favourite":
                            s.favourited = !on;
                            s.favourites_count = int64.max (0, s.favourites_count + (on ? -1 : 1));
                            break;
                        default:
                            s.bookmarked = !on;
                            break;
                    }
                    nav.show_error (_("The action did not reach the server: %s").printf (e.message));
                }
                sync ();
            });
        }

        private void more_menu (Button anchor) {
            var s = status.shown ();
            var menu = new ContextMenu (anchor);
            menu.add_item (_("Open Thread"), "view-list-symbolic", () => nav.open_status (status));
            if (s.url != "") {
                menu.add_item (_("Open in Browser"), "web-browser-symbolic", () => nav.open_link (s.url));
                menu.add_item (_("Copy Link"), "edit-copy-symbolic", () => anchor.get_clipboard ().set_text (s.url));
            }
            menu.add_item (_("Copy Text"), "edit-copy-symbolic", () => anchor.get_clipboard ().set_text (s.body ().plain ()));
            if (original_text != null) {
                if (showing_translation) menu.add_item (_("Show Original"), "preferences-desktop-locale-symbolic", () => show_translation (false));
                else menu.add_item (_("Translate"), "preferences-desktop-locale-symbolic", () => translate ());
            }
            var sess = nav.session_for (status);
            if (sess != null && sess.is_me (s.account)) {
                menu.add_separator ();
                menu.add_item (_("Delete"), "user-trash-symbolic", () => confirm_delete (anchor), "destructive");
            } else if (sess != null) {
                menu.add_separator ();
                string who = "@" + s.account.acct;
                menu.add_item (_("Mute %s").printf (who), "audio-volume-muted-symbolic", () => nav.moderate (status, "mute"));
                menu.add_item (_("Block %s").printf (who), "action-unavailable-symbolic", () => nav.moderate (status, "block"), "destructive");
                if (s.account.acct.contains ("@")) {
                    string domain = s.account.acct.substring (s.account.acct.index_of_char ('@') + 1);
                    menu.add_item (_("Block Server %s").printf (domain), "network-error-symbolic", () => nav.moderate (status, "block-domain"), "destructive");
                }
            }
            Ui.popup_menu (menu);
        }

        private void confirm_delete (Widget anchor) {
            var root = anchor.get_root () as Gtk.Window;
            if (root == null || root.application == null) return;
            var s = status.shown ();
            var dlg = new ConfirmDialog (root.application, _("Delete This Post?"), "user-trash-symbolic",
                _("The post is removed from your profile and from the servers that received it."), _("Delete"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.transient_for = root;
            dlg.modal = true;
            dlg.response.connect ((r) => {
                var sess = nav.session_for (status);
                if (r != ConfirmDialog.Response.PRIMARY || sess == null) return;
                sess.client.delete_status.begin (s.id, (o, res) => {
                    try {
                        sess.client.delete_status.end (res);
                        nav.status_deleted (s.id);
                    } catch (Error e) {
                        nav.show_error (_("The post was not deleted: %s").printf (e.message));
                    }
                });
            });
            dlg.present ();
        }
    }

    public class AccountView : Box {
        public Account account;

        public AccountView (Account a, Navigator nav) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 12);
            account = a;
            add_css_class ("fedi-account-row");
            append (Ui.avatar (a.avatar, 40));
            var texts = new Box (Orientation.VERTICAL, 0);
            texts.hexpand = true;
            texts.valign = Align.CENTER;
            var name = new RichText (Content.from_text (a.name (), a.emojis), null, "fedi-name");
            name.activated.connect (() => nav.open_account (a));
            texts.append (name);
            var h = Ui.dim (a.handle (nav.session != null ? nav.session.host () : ""));
            h.ellipsize = Pango.EllipsizeMode.END;
            texts.append (h);
            append (texts);
        }
    }

    public class NotificationView : Box {
        public Notice notification;

        public NotificationView (Notice n, Navigator nav) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            notification = n;
            add_css_class ("fedi-notification");
            bool full = n.status != null && (n.kind == NotificationKind.MENTION || n.kind == NotificationKind.STATUS);
            if (!full) {
                var head = new Box (Orientation.HORIZONTAL, 10);
                var ic = new Image.from_icon_name (n.icon ());
                ic.add_css_class ("fedi-notification-icon");
                ic.valign = Align.START;
                ic.margin_start = 16;
                ic.margin_end = 12;
                head.append (ic);
                var col = new Box (Orientation.VERTICAL, 6);
                col.hexpand = true;
                var line = new Box (Orientation.HORIZONTAL, 8);
                var av = new Button ();
                av.child = Ui.avatar (n.account.avatar, 28);
                av.add_css_class ("flat");
                av.add_css_class ("fedi-avatar-button");
                av.tooltip_text = _("Open Profile of %s").printf (n.account.name ());
                av.clicked.connect (() => nav.open_account (n.account));
                line.append (av);
                var who = new Label (Content.from_text (n.summary (), n.account.emojis).plain ());
                who.xalign = 0;
                who.wrap = true;
                who.hexpand = true;
                who.add_css_class ("heading");
                line.append (who);
                var when = Ui.dim (Text.relative_time (n.created_at));
                when.valign = Align.START;
                line.append (when);
                col.append (line);
                if (n.status != null) {
                    var body = n.status.shown ().body ();
                    string preview = n.status.shown ().spoiler_text.strip () != "" ? n.status.shown ().spoiler_text : "";
                    Widget w;
                    if (preview != "") {
                        w = Ui.dim (preview, false);
                    } else {
                        var t = new RichText (body, nav, "fedi-preview");
                        t.activated.connect (() => nav.open_status (n.status));
                        w = t;
                    }
                    col.append (w);
                } else if (n.kind == NotificationKind.FOLLOW || n.kind == NotificationKind.FOLLOW_REQUEST) {
                    var h = Ui.dim (n.account.handle (nav.session != null ? nav.session.host () : ""));
                    h.ellipsize = Pango.EllipsizeMode.END;
                    col.append (h);
                    if (n.kind == NotificationKind.FOLLOW_REQUEST) col.append (request_buttons (n, nav));
                }
                head.append (col);
                append (head);
            } else {
                append (new StatusView (n.status, nav));
            }
        }

        private Widget request_buttons (Notice n, Navigator nav) {
            var box = new Box (Orientation.HORIZONTAL, 8);
            var accept = new Button.with_label (_("Accept"));
            accept.add_css_class ("pill");
            accept.add_css_class ("suggested-action");
            var reject = new Button.with_label (_("Reject"));
            reject.add_css_class ("pill");
            box.append (reject);
            box.append (accept);
            accept.clicked.connect (() => answer (n, nav, true, box));
            reject.clicked.connect (() => answer (n, nav, false, box));
            return box;
        }

        private void answer (Notice n, Navigator nav, bool yes, Box box) {
            if (nav.session == null) return;
            box.sensitive = false;
            nav.session.client.call.begin ("POST", "/api/v1/follow_requests/%s/%s".printf (n.account.id, yes ? "authorize" : "reject"), null, null, (o, res) => {
                try {
                    nav.session.client.call.end (res);
                    Widget? c;
                    while ((c = box.get_first_child ()) != null) box.remove (c);
                    box.append (Ui.dim (yes ? _("Request accepted") : _("Request rejected"), false));
                } catch (Error e) {
                    box.sensitive = true;
                    nav.show_error (e.message);
                }
            });
        }
    }

    public class ProfileHeader : Box {
        private static string contacts_dir () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity", "contacts");
        }

        private static bool in_contacts (Account a) {
            string handle = a.acct.contains ("@") ? a.acct : a.url;
            try {
                var dir = Dir.open (contacts_dir ());
                string? name;
                while ((name = dir.read_name ()) != null) {
                    if (!name.has_suffix (".vcf")) continue;
                    string text;
                    FileUtils.get_contents (Path.build_filename (contacts_dir (), name), out text);
                    if (text.contains (handle) || (a.url != "" && text.contains (a.url))) return true;
                }
            } catch (Error e) {
            }
            return false;
        }

        private static bool add_to_contacts (Account a) {
            string name = a.display_name != "" ? a.display_name : a.username;
            string esc = name.replace ("\\", "\\\\").replace (",", "\\,").replace (";", "\\;");
            var sb = new StringBuilder ("BEGIN:VCARD\r\nVERSION:3.0\r\n");
            string uid = Uuid.string_random ();
            sb.append ("UID:%s\r\n".printf (uid));
            sb.append ("FN:%s\r\n".printf (esc));
            sb.append ("N:;%s;;;\r\n".printf (esc));
            sb.append ("NICKNAME:%s\r\n".printf (a.acct));
            if (a.url != "") sb.append ("URL;TYPE=fediverse:%s\r\n".printf (a.url));
            if (a.avatar != "") sb.append ("PHOTO;VALUE=uri:%s\r\n".printf (a.avatar));
            sb.append ("END:VCARD\r\n");
            try {
                DirUtils.create_with_parents (contacts_dir (), 0700);
                FileUtils.set_contents (Path.build_filename (contacts_dir (), uid + ".vcf"), sb.str);
                return true;
            } catch (Error e) {
                warning ("Fediverse: could not add the contact: %s", e.message);
                return false;
            }
        }

        private Account account;
        private Navigator nav;
        private Button follow;
        private Label follows_you;
        private Relationship? rel;
        private Session? session;

        public ProfileHeader (Account a, Navigator nav, Session? sess = null) {
            Object (orientation: Orientation.VERTICAL, spacing: 10);
            account = a;
            this.nav = nav;
            session = sess ?? session;
            add_css_class ("fedi-profile");
            var top = new Box (Orientation.HORIZONTAL, 16);
            top.append (Ui.avatar (a.avatar, 88));
            var texts = new Box (Orientation.VERTICAL, 2);
            texts.hexpand = true;
            texts.valign = Align.CENTER;
            texts.append (new RichText (Content.from_text (a.name (), a.emojis), null, "fedi-profile-name"));
            var handle = Ui.dim (a.handle (session != null ? session.host () : ""), false);
            handle.selectable = true;
            handle.wrap = true;
            handle.wrap_mode = Pango.WrapMode.WORD_CHAR;
            texts.append (handle);
            follows_you = Ui.dim (_("Follows you"));
            follows_you.visible = false;
            texts.append (follows_you);
            top.append (texts);
            follow = new Button.with_label (_("Follow"));
            follow.add_css_class ("pill");
            follow.valign = Align.CENTER;
            follow.visible = false;
            follow.clicked.connect (toggle_follow);
            top.append (follow);
            if (session != null && !session.is_me (a) && !in_contacts (a)) {
                var add = new Button.from_icon_name ("avatar-default-symbolic");
                add.add_css_class ("circular");
                add.valign = Align.CENTER;
                add.tooltip_text = _("Add to Contacts");
                add.update_property (AccessibleProperty.LABEL, _("Add to Contacts"), -1);
                add.clicked.connect (() => {
                    if (add_to_contacts (a)) add.visible = false;
                });
                top.append (add);
            }
            if (session != null && !session.is_me (a)) {
                session.client.relationship.begin (a.id, (o, res) => {
                    rel = session.client.relationship.end (res);
                    sync ();
                });
            }
            append (top);
            var note = Content.parse (a.note, a.emojis);
            if (!note.is_empty ()) append (new RichText (note, nav));
            if (a.fields.size > 0) {
                var grid = new Grid ();
                grid.add_css_class ("fedi-fields");
                grid.column_spacing = 12;
                grid.row_spacing = 6;
                for (int i = 0; i < a.fields.size; i++) {
                    var f = a.fields[i];
                    var k = Ui.dim (Content.from_text (f.name, a.emojis).plain (), false);
                    k.valign = Align.START;
                    k.ellipsize = Pango.EllipsizeMode.END;
                    k.max_width_chars = 18;
                    grid.attach (k, 0, i, 1, 1);
                    var v = new RichText (Content.parse (f.value, a.emojis), nav);
                    if (f.verified) v.add_css_class ("fedi-verified");
                    grid.attach (v, 1, i, 1, 1);
                    if (f.verified) {
                        var ok = new Image.from_icon_name ("emblem-ok-symbolic");
                        ok.tooltip_text = _("Verified link");
                        ok.valign = Align.START;
                        grid.attach (ok, 2, i, 1, 1);
                    }
                }
                append (grid);
            }
            var stats = new Box (Orientation.HORIZONTAL, 18);
            stats.append (stat (a.statuses_count, ngettext ("Post", "Posts", (ulong) a.statuses_count)));
            stats.append (stat (a.following_count, _("Following")));
            stats.append (stat (a.followers_count, ngettext ("Follower", "Followers", (ulong) a.followers_count)));
            append (stats);
        }

        private Widget stat (int64 n, string label) {
            var l = new Label ("<b>%s</b> %s".printf (Text.compact (n), Markup.escape_text (label)));
            l.use_markup = true;
            l.xalign = 0;
            return l;
        }

        private void sync () {
            if (rel == null) return;
            follow.visible = true;
            follow.sensitive = true;
            follows_you.visible = rel.followed_by;
            if (rel.following) {
                follow.label = _("Unfollow");
                follow.remove_css_class ("suggested-action");
            } else if (rel.requested) {
                follow.label = _("Cancel Request");
                follow.remove_css_class ("suggested-action");
            } else {
                follow.label = account.locked ? _("Ask to Follow") : _("Follow");
                follow.add_css_class ("suggested-action");
            }
        }

        private void toggle_follow () {
            if (rel == null || session == null) return;
            bool on = !(rel.following || rel.requested);
            follow.sensitive = false;
            session.client.follow.begin (account.id, on, (o, res) => {
                try {
                    var r = session.client.follow.end (res);
                    if (r != null) rel = r;
                } catch (Error e) {
                    nav.show_error (e.message);
                }
                follow.sensitive = true;
                sync ();
            });
        }
    }
}

namespace Singularity.Apps.Fediverse {

    public class DraftView : Box {
        public Draft draft;

        public DraftView (Draft d, Navigator nav) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            draft = d;
            add_css_class ("fedi-draft");
            var head = new Box (Orientation.HORIZONTAL, 8);
            var ic = new Image.from_icon_name ("document-edit-symbolic");
            ic.add_css_class ("fedi-notification-icon");
            head.append (ic);
            var title = new Label (d.reply_to_id != "" ? _("Reply to %s").printf (d.reply_to_handle) : _("New Post"));
            title.add_css_class ("heading");
            title.xalign = 0;
            title.hexpand = true;
            title.ellipsize = Pango.EllipsizeMode.END;
            head.append (title);
            var when = Ui.dim (_("Saved %s").printf (Text.relative_time (new DateTime.from_unix_utc (d.updated))));
            head.append (when);
            var del = Ui.tool_button ("user-trash-symbolic", _("Delete Draft"));
            del.clicked.connect (() => nav.delete_draft (d));
            head.append (del);
            append (head);
            string text = d.preview ();
            append (Ui.preview (text != "" ? text : _("Empty draft")));
            var meta = new Box (Orientation.HORIZONTAL, 12);
            meta.append (Ui.visibility_label (d.visibility));
            if (d.spoiler_text.strip () != "") meta.append (Ui.dim (_("With content warning")));
            if (d.replaces_scheduled != "") meta.append (Ui.dim (_("Edits a scheduled post")));
            append (meta);
        }
    }

    public class ScheduledView : Box {
        public ScheduledStatus item;

        public ScheduledView (ScheduledStatus sch, Navigator nav) {
            Object (orientation: Orientation.VERTICAL, spacing: 6);
            item = sch;
            add_css_class ("fedi-scheduled");
            var head = new Box (Orientation.HORIZONTAL, 8);
            var ic = new Image.from_icon_name ("alarm-symbolic");
            ic.add_css_class ("fedi-notification-icon");
            head.append (ic);
            var texts = new Box (Orientation.VERTICAL, 0);
            texts.hexpand = true;
            var when = new Label (Ui.moment (sch.scheduled_at));
            when.add_css_class ("heading");
            when.xalign = 0;
            texts.append (when);
            texts.append (Ui.dim (Ui.until (sch.scheduled_at)));
            head.append (texts);
            var time = Ui.tool_button ("x-office-calendar-symbolic", _("Change Time"));
            time.clicked.connect (() => nav.reschedule (sch));
            head.append (time);
            var edit = Ui.tool_button ("document-edit-symbolic", _("Edit"));
            edit.clicked.connect (() => nav.edit_scheduled (sch));
            head.append (edit);
            var cancel = Ui.tool_button ("user-trash-symbolic", _("Delete Scheduled Post"));
            cancel.clicked.connect (() => nav.cancel_scheduled (sch));
            head.append (cancel);
            append (head);
            string text = sch.spoiler_text.strip () != "" ? sch.spoiler_text.strip () : sch.text.strip ();
            append (Ui.preview (text != "" ? text : _("Media only")));
            var meta = new Box (Orientation.HORIZONTAL, 12);
            meta.append (Ui.visibility_label (sch.visibility));
            int media = int.max (sch.media.size, sch.media_ids.size);
            if (media > 0) meta.append (Ui.dim (ngettext ("%d attachment", "%d attachments", media).printf (media)));
            if (sch.in_reply_to_id != "") meta.append (Ui.dim (_("Reply")));
            append (meta);
        }
    }
}
