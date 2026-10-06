namespace Singularity.Apps.Fediverse {

    public enum SpanKind {
        TEXT,
        LINK,
        MENTION,
        HASHTAG,
        EMOJI
    }

    [Flags]
    public enum SpanStyle {
        NONE = 0,
        BOLD = 1,
        ITALIC = 2,
        CODE = 4,
        STRIKE = 8,
        UNDERLINE = 16,
        QUOTE = 32
    }

    public class Span : Object {
        public SpanKind kind;
        public string text;
        public SpanStyle style;
        public string href;
        public string target;

        public Span (SpanKind kind, string text, SpanStyle style = SpanStyle.NONE, string href = "", string target = "") {
            this.kind = kind;
            this.text = text;
            this.style = style;
            this.href = href;
            this.target = target;
        }

        public bool same_format (Span o) {
            return kind == o.kind && style == o.style && href == o.href && target == o.target && kind != SpanKind.EMOJI;
        }
    }

    public class Content : Object {
        public Gee.ArrayList<Span> spans = new Gee.ArrayList<Span> ();

        private class Open {
            public string name;
            public SpanStyle style;
            public bool hidden;
            public bool ellipsis;
            public bool link;
            public bool list;
            public int counter;
            public bool ordered;
        }

        private Gee.ArrayList<Open> stack = new Gee.ArrayList<Open> ();
        private Gee.List<Emoji>? emojis;
        private Gee.List<Mention>? mentions;
        private SpanKind link_kind = SpanKind.TEXT;
        private string link_href = "";
        private string link_target = "";
        private int pre_depth;

        private const string[] VOID = { "br", "img", "hr", "meta", "link", "input", "wbr", "source", "col", "area", "base", "embed", "param", "track" };
        private const string[] SKIP = { "script", "style", "iframe", "object", "head", "title", "template", "noscript", "svg", "math", "textarea", "select", "button", "video", "audio" };

        public static Content parse (string? html, Gee.List<Emoji>? emojis = null, Gee.List<Mention>? mentions = null) {
            var c = new Content ();
            c.emojis = emojis;
            c.mentions = mentions;
            c.run (html ?? "");
            c.finish ();
            return c;
        }

        public static Content from_text (string? text, Gee.List<Emoji>? emojis = null) {
            var c = new Content ();
            c.emojis = emojis;
            c.pre_depth = 1;
            c.add_text (text ?? "");
            c.pre_depth = 0;
            c.finish ();
            return c;
        }

        public string plain () {
            var sb = new StringBuilder ();
            foreach (var s in spans) sb.append (s.text);
            return sb.str;
        }

        public string markup () {
            var sb = new StringBuilder ();
            foreach (var s in spans) {
                string t = Markup.escape_text (s.text);
                if (SpanStyle.CODE in s.style) t = "<tt>" + t + "</tt>";
                if (SpanStyle.BOLD in s.style) t = "<b>" + t + "</b>";
                if (SpanStyle.ITALIC in s.style || SpanStyle.QUOTE in s.style) t = "<i>" + t + "</i>";
                if (SpanStyle.STRIKE in s.style) t = "<s>" + t + "</s>";
                if (SpanStyle.UNDERLINE in s.style) t = "<u>" + t + "</u>";
                if (s.href != "" && s.kind != SpanKind.EMOJI) t = "<a href=\"%s\">%s</a>".printf (Markup.escape_text (s.href), t);
                sb.append (t);
            }
            return sb.str;
        }

        public bool is_empty () {
            foreach (var s in spans) if (s.text.strip () != "") return false;
            return true;
        }

        private void run (string html) {
            int i = 0;
            int n = html.length;
            while (i < n) {
                int lt = html.index_of_char ('<', i);
                if (lt < 0) {
                    add_text (decode (html.substring (i)));
                    break;
                }
                if (lt > i) add_text (decode (html.substring (i, lt - i)));
                if (html.substring (lt).has_prefix ("<!--")) {
                    int end = html.index_of ("-->", lt + 4);
                    i = end < 0 ? n : end + 3;
                    continue;
                }
                int gt = tag_end (html, lt + 1);
                if (gt < 0) {
                    add_text (decode (html.substring (lt)));
                    break;
                }
                string inner = html.substring (lt + 1, gt - lt - 1);
                i = gt + 1;
                if (inner.has_prefix ("!") || inner.has_prefix ("?")) continue;
                if (inner.has_prefix ("/")) {
                    close_tag (tag_name (inner.substring (1)));
                    continue;
                }
                string name = tag_name (inner);
                if (name == "") {
                    add_text ("<" + decode (inner) + ">");
                    continue;
                }
                var attrs = parse_attrs (inner.substring (name.length));
                bool self_closing = inner.strip ().has_suffix ("/");
                if (name in SKIP && !self_closing) {
                    int close = find_close (html, name, i);
                    i = close < 0 ? n : close;
                    continue;
                }
                open_tag (name, attrs, self_closing);
            }
        }

        private static int tag_end (string html, int from) {
            char quote = 0;
            for (int j = from; j < html.length; j++) {
                char ch = html[j];
                if (quote != 0) {
                    if (ch == quote) quote = 0;
                } else if (ch == '"' || ch == '\'') {
                    quote = ch;
                } else if (ch == '>') {
                    return j;
                }
            }
            return -1;
        }

        private static int find_close (string html, string name, int from) {
            string lower = html.down ();
            int at = lower.index_of ("</" + name, from);
            if (at < 0) return -1;
            int gt = html.index_of_char ('>', at);
            return gt < 0 ? -1 : gt + 1;
        }

        private static string tag_name (string s) {
            var sb = new StringBuilder ();
            for (int j = 0; j < s.length; j++) {
                char ch = s[j];
                if (ch.isalnum () || ch == '-') sb.append_c (ch.tolower ());
                else break;
            }
            return sb.str;
        }

        public static Gee.HashMap<string, string> parse_attrs (string s) {
            var map = new Gee.HashMap<string, string> ();
            int j = 0;
            int n = s.length;
            while (j < n) {
                while (j < n && (s[j].isspace () || s[j] == '/')) j++;
                int start = j;
                while (j < n && !s[j].isspace () && s[j] != '=' && s[j] != '>' && s[j] != '/') j++;
                if (j == start) {
                    j++;
                    continue;
                }
                string key = s.substring (start, j - start).down ();
                while (j < n && s[j].isspace ()) j++;
                string val = "";
                if (j < n && s[j] == '=') {
                    j++;
                    while (j < n && s[j].isspace ()) j++;
                    if (j < n && (s[j] == '"' || s[j] == '\'')) {
                        char q = s[j];
                        int end = s.index_of_char (q, j + 1);
                        if (end < 0) end = n;
                        val = s.substring (j + 1, end - j - 1);
                        j = end + 1;
                    } else {
                        int vs = j;
                        while (j < n && !s[j].isspace ()) j++;
                        val = s.substring (vs, j - vs);
                    }
                }
                if (!map.has_key (key)) map[key] = decode (val);
            }
            return map;
        }

        private SpanStyle current_style () {
            SpanStyle st = SpanStyle.NONE;
            foreach (var o in stack) st |= o.style;
            return st;
        }

        private bool hidden () {
            foreach (var o in stack) if (o.hidden) return true;
            return false;
        }

        private int trailing_newlines () {
            int count = 0;
            for (int k = spans.size - 1; k >= 0; k--) {
                string t = spans[k].text;
                for (int j = t.length - 1; j >= 0; j--) {
                    if (t[j] == '\n') count++;
                    else if (t[j] == ' ') continue;
                    else return count;
                }
            }
            return spans.size == 0 ? -1 : count;
        }

        private void block_break (int wanted) {
            int have = trailing_newlines ();
            if (have < 0) return;
            trim_trailing_spaces ();
            for (int k = have; k < wanted; k++) push (new Span (SpanKind.TEXT, "\n", current_style () & SpanStyle.QUOTE));
        }

        private void trim_trailing_spaces () {
            while (spans.size > 0) {
                var last = spans[spans.size - 1];
                if (last.kind == SpanKind.EMOJI) return;
                string t = last.text;
                int end = t.length;
                while (end > 0 && t[end - 1] == ' ') end--;
                if (end == t.length) return;
                if (end == 0) {
                    spans.remove_at (spans.size - 1);
                    continue;
                }
                last.text = t.substring (0, end);
                return;
            }
        }

        private void push (Span s) {
            if (s.text == "") return;
            if (spans.size > 0) {
                var last = spans[spans.size - 1];
                if (last.same_format (s)) {
                    last.text += s.text;
                    return;
                }
            }
            spans.add (s);
        }

        private bool at_line_start () {
            int have = trailing_newlines ();
            return have != 0;
        }

        private void open_tag (string name, Gee.HashMap<string, string> attrs, bool self_closing) {
            if (name == "br") {
                if (!hidden ()) {
                    trim_trailing_spaces ();
                    push (new Span (SpanKind.TEXT, "\n", current_style () & SpanStyle.QUOTE));
                }
                return;
            }
            if (name == "hr") {
                if (!hidden ()) block_break (2);
                return;
            }
            if (name == "img") {
                if (hidden ()) return;
                string alt = attrs["alt"] ?? "";
                if (alt != "") add_text (alt);
                return;
            }
            if (name in VOID || self_closing) return;
            var o = new Open ();
            o.name = name;
            string cls = (attrs["class"] ?? "").down ();
            switch (name) {
                case "p":
                case "div":
                case "section":
                case "article":
                    block_break (2);
                    break;
                case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
                    block_break (2);
                    o.style = SpanStyle.BOLD;
                    break;
                case "blockquote":
                    block_break (2);
                    o.style = SpanStyle.QUOTE;
                    break;
                case "pre":
                    block_break (2);
                    o.style = SpanStyle.CODE;
                    pre_depth++;
                    break;
                case "ul":
                case "ol":
                    block_break (1);
                    o.list = true;
                    o.ordered = name == "ol";
                    break;
                case "li":
                    block_break (1);
                    if (!hidden ()) {
                        Open? list = null;
                        for (int k = stack.size - 1; k >= 0; k--) {
                            if (stack[k].list) {
                                list = stack[k];
                                break;
                            }
                        }
                        string bullet = "• ";
                        if (list != null && list.ordered) bullet = "%d. ".printf (++list.counter);
                        push (new Span (SpanKind.TEXT, bullet, current_style () & SpanStyle.QUOTE));
                    }
                    break;
                case "b":
                case "strong":
                    o.style = SpanStyle.BOLD;
                    break;
                case "i":
                case "em":
                case "cite":
                    o.style = SpanStyle.ITALIC;
                    break;
                case "u":
                case "ins":
                    o.style = SpanStyle.UNDERLINE;
                    break;
                case "s":
                case "del":
                case "strike":
                    o.style = SpanStyle.STRIKE;
                    break;
                case "code":
                case "kbd":
                case "samp":
                case "tt":
                    o.style = SpanStyle.CODE;
                    break;
                case "span":
                    string[] classes = cls.split (" ");
                    if (has_class (classes, "invisible")) o.hidden = true;
                    if (has_class (classes, "ellipsis")) o.ellipsis = true;
                    break;
                case "a":
                    open_link (attrs, cls);
                    o.link = true;
                    break;
            }
            stack.add (o);
        }

        private void open_link (Gee.HashMap<string, string> attrs, string cls) {
            string href = (attrs["href"] ?? "").strip ();
            if (!safe_href (href)) {
                link_kind = SpanKind.TEXT;
                link_href = "";
                link_target = "";
                return;
            }
            string[] classes = cls.split (" ");
            link_href = href;
            link_target = "";
            link_kind = SpanKind.LINK;
            if (has_class (classes, "mention") && !has_class (classes, "hashtag")) {
                link_kind = SpanKind.MENTION;
                if (mentions != null) {
                    foreach (var m in mentions) {
                        if (m.url == href) {
                            link_target = m.id;
                            break;
                        }
                    }
                }
            } else if (has_class (classes, "hashtag") || ((attrs["rel"] ?? "").contains ("tag") && href.contains ("/tag"))) {
                link_kind = SpanKind.HASHTAG;
                int slash = href.last_index_of ("/");
                string tag = slash >= 0 ? href.substring (slash + 1) : href;
                int q = tag.index_of_char ('?');
                if (q >= 0) tag = tag.substring (0, q);
                link_target = Uri.unescape_string (tag) ?? tag;
            }
        }

        private static bool has_class (string[] classes, string name) {
            foreach (string c in classes) if (c == name) return true;
            return false;
        }

        public static bool safe_href (string href) {
            string h = href.down ();
            return h.has_prefix ("https://") || h.has_prefix ("http://") || h.has_prefix ("mailto:");
        }

        private void close_tag (string name) {
            int at = -1;
            for (int k = stack.size - 1; k >= 0; k--) {
                if (stack[k].name == name) {
                    at = k;
                    break;
                }
            }
            if (at < 0) return;
            while (stack.size > at) {
                var o = stack.remove_at (stack.size - 1);
                finish_open (o);
            }
        }

        private void finish_open (Open o) {
            if (o.ellipsis && !hidden ()) add_text ("…");
            if (o.link) {
                link_kind = SpanKind.TEXT;
                link_href = "";
                link_target = "";
            }
            switch (o.name) {
                case "p": case "div": case "section": case "article":
                case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
                case "blockquote":
                    block_break (2);
                    break;
                case "pre":
                    pre_depth--;
                    block_break (2);
                    break;
                case "ul":
                case "ol":
                    block_break (2);
                    break;
                case "li":
                    block_break (1);
                    break;
            }
        }

        private void add_text (string raw) {
            if (hidden () || raw == "") return;
            string text = raw;
            if (pre_depth == 0) {
                var sb = new StringBuilder ();
                bool space = false;
                unichar c;
                int idx = 0;
                while (text.get_next_char (ref idx, out c)) {
                    if (c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\f') {
                        space = true;
                        continue;
                    }
                    if (space) sb.append_c (' ');
                    space = false;
                    sb.append_unichar (c);
                }
                if (space) sb.append_c (' ');
                text = sb.str;
                if (at_line_start ()) text = text.chug ();
                if (text == "") return;
                if (text.has_prefix (" ") && spans.size > 0 && spans[spans.size - 1].text.has_suffix (" ")) text = text.substring (1);
                if (text == "") return;
            } else {
                text = text.replace ("\r\n", "\n");
            }
            SpanStyle st = current_style ();
            if (emojis == null || emojis.size == 0 || !text.contains (":")) {
                push (new Span (link_kind, text, st, link_href, link_target));
                return;
            }
            int pos = 0;
            while (pos < text.length) {
                int a = text.index_of_char (':', pos);
                if (a < 0) break;
                int b = text.index_of_char (':', a + 1);
                if (b < 0) break;
                string code = text.substring (a + 1, b - a - 1);
                Emoji? found = null;
                if (code != "" && !code.contains (" ")) {
                    foreach (var e in emojis) {
                        if (e.shortcode == code) {
                            found = e;
                            break;
                        }
                    }
                }
                if (found == null) {
                    if (a > pos) push (new Span (link_kind, text.substring (pos, a - pos), st, link_href, link_target));
                    push (new Span (link_kind, ":", st, link_href, link_target));
                    pos = a + 1;
                    continue;
                }
                if (a > pos) push (new Span (link_kind, text.substring (pos, a - pos), st, link_href, link_target));
                spans.add (new Span (SpanKind.EMOJI, ":" + code + ":", st, found.url, found.shortcode));
                pos = b + 1;
            }
            if (pos < text.length) push (new Span (link_kind, text.substring (pos), st, link_href, link_target));
        }

        private void finish () {
            while (stack.size > 0) finish_open (stack.remove_at (stack.size - 1));
            while (spans.size > 0) {
                var last = spans[spans.size - 1];
                if (last.kind == SpanKind.EMOJI) break;
                string t = last.text;
                int end = t.length;
                while (end > 0 && (t[end - 1] == ' ' || t[end - 1] == '\n')) end--;
                if (end == t.length) break;
                if (end == 0) {
                    spans.remove_at (spans.size - 1);
                    continue;
                }
                last.text = t.substring (0, end);
                break;
            }
        }

        public static string decode (string s) {
            if (!s.contains ("&")) return s;
            var sb = new StringBuilder ();
            int i = 0;
            while (i < s.length) {
                int amp = s.index_of_char ('&', i);
                if (amp < 0) {
                    sb.append (s.substring (i));
                    break;
                }
                sb.append (s.substring (i, amp - i));
                int semi = s.index_of_char (';', amp);
                if (semi < 0 || semi - amp > 10) {
                    sb.append_c ('&');
                    i = amp + 1;
                    continue;
                }
                string ent = s.substring (amp + 1, semi - amp - 1);
                unichar ch = 0;
                if (ent.has_prefix ("#x") || ent.has_prefix ("#X")) {
                    ch = (unichar) ulong.parse (ent.substring (2), 16);
                } else if (ent.has_prefix ("#")) {
                    ch = (unichar) ulong.parse (ent.substring (1));
                } else {
                    switch (ent) {
                        case "amp": ch = '&'; break;
                        case "lt": ch = '<'; break;
                        case "gt": ch = '>'; break;
                        case "quot": ch = '"'; break;
                        case "apos": ch = '\''; break;
                        case "nbsp": ch = 0xA0; break;
                        case "hellip": ch = 0x2026; break;
                        case "ndash": ch = 0x2013; break;
                        case "mdash": ch = 0x2014; break;
                        case "lsquo": ch = 0x2018; break;
                        case "rsquo": ch = 0x2019; break;
                        case "ldquo": ch = 0x201C; break;
                        case "rdquo": ch = 0x201D; break;
                        case "copy": ch = 0xA9; break;
                        case "reg": ch = 0xAE; break;
                        case "trade": ch = 0x2122; break;
                        case "euro": ch = 0x20AC; break;
                        case "middot": ch = 0xB7; break;
                        case "bull": ch = 0x2022; break;
                    }
                }
                if (ch == 0 || !ch.validate () || ch == 0xFFFE) {
                    sb.append_c ('&');
                    i = amp + 1;
                    continue;
                }
                sb.append_unichar (ch);
                i = semi + 1;
            }
            return sb.str;
        }
    }
}
