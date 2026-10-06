using Singularity.Apps.Fediverse;

Gee.ArrayList<Emoji> emojis () {
    var list = new Gee.ArrayList<Emoji> ();
    var e = new Emoji ();
    e.shortcode = "blobcat";
    e.url = "https://files.example/blobcat.png";
    list.add (e);
    return list;
}

Span? find_kind (Content c, SpanKind kind) {
    foreach (var s in c.spans) if (s.kind == kind) return s;
    return null;
}

void test_paragraphs () {
    var c = Content.parse ("<p>Hello<br>world</p><p>Second</p>");
    assert (c.plain () == "Hello\nworld\n\nSecond");
    assert (Content.parse ("<p>  a \n  b  </p><p></p>").plain () == "a b");
    assert (Content.parse ("<P>Upper</P><BR/>case").plain () == "Upper\n\n\ncase");
    assert (Content.parse ("").plain () == "");
    assert (Content.parse (null).is_empty ());
    assert (Content.parse ("<p> </p>").is_empty ());
    assert (Content.parse ("plain text").plain () == "plain text");
    assert (Content.parse ("<div>a</div><div>b</div>").plain () == "a\n\nb");
}

void test_links () {
    var c = Content.parse ("<p>See <a href=\"https://example.com/a/very/long/path\" rel=\"nofollow noopener\" target=\"_blank\"><span class=\"invisible\">https://</span><span class=\"ellipsis\">example.com/a/very/lo</span><span class=\"invisible\">ng/path</span></a> now</p>");
    assert (c.plain () == "See example.com/a/very/lo… now");
    var link = find_kind (c, SpanKind.LINK);
    assert (link != null);
    assert (link.href == "https://example.com/a/very/long/path");
    assert (link.text == "example.com/a/very/lo…");
    var q = Content.parse ("<a href=\"https://x.example/?a=1&amp;b=2\" title=\"x > y\">go</a>");
    assert (q.plain () == "go");
    assert (find_kind (q, SpanKind.LINK).href == "https://x.example/?a=1&b=2");
    var mail = Content.parse ("<a href=\"mailto:a@b.example\">mail</a>");
    assert (find_kind (mail, SpanKind.LINK) != null);
}

void test_mentions_and_tags () {
    var mentions = new Gee.ArrayList<Mention> ();
    var m = new Mention ();
    m.id = "55";
    m.acct = "dave@third.example";
    m.url = "https://third.example/@dave";
    mentions.add (m);
    var c = Content.parse ("<p><span class=\"h-card\"><a href=\"https://third.example/@dave\" class=\"u-url mention\">@<span>dave</span></a></span> and <a href=\"https://unknown.example/@zed\" class=\"u-url mention\">@<span>zed</span></a> about <a href=\"https://example.social/tags/Vala\" class=\"mention hashtag\" rel=\"tag\">#<span>Vala</span></a></p>", null, mentions);
    assert (c.plain () == "@dave and @zed about #Vala");
    int found = 0;
    foreach (var s in c.spans) {
        if (s.kind == SpanKind.MENTION && s.text == "@dave") {
            assert (s.target == "55");
            found++;
        }
        if (s.kind == SpanKind.MENTION && s.text == "@zed") {
            assert (s.target == "");
            assert (s.href == "https://unknown.example/@zed");
            found++;
        }
        if (s.kind == SpanKind.HASHTAG) {
            assert (s.target == "Vala");
            assert (s.text == "#Vala");
            found++;
        }
    }
    assert (found == 3);
    var akkoma = Content.parse ("<a class=\"hashtag\" data-tag=\"café\" href=\"https://ak.example/tag/caf%C3%A9\">#café</a>");
    assert (find_kind (akkoma, SpanKind.HASHTAG).target == "café");
}

void test_sanitizer () {
    assert (Content.parse ("<p>a<script>alert('x')</script>b</p>").plain () == "ab");
    assert (Content.parse ("<style>p{color:red}</style><p>ok</p>").plain () == "ok");
    assert (Content.parse ("<p>x<iframe src=\"https://evil.example\">inner</iframe>y</p>").plain () == "xy");
    assert (Content.parse ("<img src=x onerror=alert(1)>t").plain () == "t");
    var js = Content.parse ("<a href=\"javascript:alert(1)\">click</a>");
    assert (js.plain () == "click");
    assert (find_kind (js, SpanKind.LINK) == null);
    foreach (var s in js.spans) assert (s.href == "");
    var data = Content.parse ("<a href=\"data:text/html,x\">d</a><a href=\"  JAVASCRIPT:x\">e</a>");
    foreach (var s in data.spans) assert (s.href == "");
    assert (Content.parse ("<p>a<!-- hidden <b>x</b> -->b</p>").plain () == "ab");
    assert (Content.parse ("<p>open <b>bold").plain () == "open bold");
    assert (Content.parse ("a < b and c > d").plain () == "a < b and c > d");
    assert (Content.parse ("<p>1 <unknown-tag attr='1'>kept</unknown-tag> 2</p>").plain () == "1 kept 2");
    assert (Content.parse ("</p></b>stray").plain () == "stray");
    assert (Content.parse ("<span class=\"invisible\">hidden</span>shown").plain () == "shown");
    string markup = Content.parse ("<p>&lt;b&gt;x&lt;/b&gt; \"q\" <a href=\"https://a.example/?x=1&amp;y=<\">l</a></p>").markup ();
    assert (!markup.contains ("<b>"));
    assert (markup.contains ("&lt;b&gt;"));
    assert (markup.contains ("href=\"https://a.example/?x=1&amp;y=&lt;\""));
    MarkupParser parser = { null, null, null, null, null };
    var ctx = new MarkupParseContext (parser, 0, null, null);
    try {
        ctx.parse ("<markup>" + markup + "</markup>", -1);
        ctx.end_parse ();
    } catch (Error e) {
        assert_not_reached ();
    }
}

void test_entities () {
    assert (Content.decode ("&lt;&gt;&amp;&quot;&#39;&apos;") == "<>&\"''");
    assert (Content.decode ("&#x1F600;&#128512;") == "\xF0\x9F\x98\x80\xF0\x9F\x98\x80");
    assert (Content.decode ("a&nbsp;b") == "a b");
    assert (Content.decode ("&hellip;&copy;") == "…©");
    assert (Content.decode ("&unknown; & alone &#0; &#xZZ;") == "&unknown; & alone &#0; &#xZZ;");
    assert (Content.decode ("no entities") == "no entities");
}

void test_styles () {
    var c = Content.parse ("<p><strong>B</strong><em>I</em><code>C</code><del>S</del><u>U</u></p>");
    assert (c.plain () == "BICSU");
    assert (c.spans.size == 5);
    assert (c.spans[0].style == SpanStyle.BOLD);
    assert (c.spans[1].style == SpanStyle.ITALIC);
    assert (c.spans[2].style == SpanStyle.CODE);
    assert (c.spans[3].style == SpanStyle.STRIKE);
    assert (c.spans[4].style == SpanStyle.UNDERLINE);
    string mk = c.markup ();
    assert (mk == "<b>B</b><i>I</i><tt>C</tt><s>S</s><u>U</u>");
    var pre = Content.parse ("<p>x</p><pre><code>line 1\n  indented</code></pre><p>y</p>");
    assert (pre.plain () == "x\n\nline 1\n  indented\n\ny");
    var quote = Content.parse ("<blockquote><p>quoted</p></blockquote><p>after</p>");
    assert (quote.plain () == "quoted\n\nafter");
    assert (SpanStyle.QUOTE in quote.spans[0].style);
    var lists = Content.parse ("<p>Items:</p><ul><li>one</li><li>two</li></ul><ol><li>first</li><li>second</li></ol>");
    assert (lists.plain () == "Items:\n\n• one\n• two\n\n1. first\n2. second");
    var nested = Content.parse ("<b>bold <i>both</i></b>");
    assert (nested.spans[1].style == (SpanStyle.BOLD | SpanStyle.ITALIC));
}

void test_emoji () {
    var c = Content.parse ("<p>:blobcat: hi :unknown: x:blobcat:y 12:30</p>", emojis ());
    assert (c.plain () == ":blobcat: hi :unknown: x:blobcat:y 12:30");
    int n = 0;
    foreach (var s in c.spans) {
        if (s.kind == SpanKind.EMOJI) {
            assert (s.href == "https://files.example/blobcat.png");
            assert (s.target == "blobcat");
            n++;
        }
    }
    assert (n == 2);
    var link = Content.parse ("<a href=\"https://x.example\">go :blobcat:</a>", emojis ());
    assert (find_kind (link, SpanKind.EMOJI) != null);
    assert (find_kind (link, SpanKind.LINK).text == "go ");
    var name = Content.from_text ("Ada :blobcat: Lovelace\nline", emojis ());
    assert (name.plain () == "Ada :blobcat: Lovelace\nline");
    assert (find_kind (name, SpanKind.EMOJI) != null);
    assert (Content.from_text ("<b>not html</b>").plain () == "<b>not html</b>");
    assert (Content.parse ("::: :: :", emojis ()).plain () == "::: :: :");
}

void test_attrs () {
    var a = Content.parse_attrs (" href=\"x\" class='a b' data-x=unquoted disabled HREF=\"dup\"");
    assert (a["href"] == "x");
    assert (a["class"] == "a b");
    assert (a["data-x"] == "unquoted");
    assert (a.has_key ("disabled"));
    assert (Content.safe_href ("https://a"));
    assert (Content.safe_href ("HTTP://a"));
    assert (!Content.safe_href ("javascript:x"));
    assert (!Content.safe_href ("//evil.example"));
    assert (!Content.safe_href (""));
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Test.init (ref args);
    Test.add_func ("/html/paragraphs", test_paragraphs);
    Test.add_func ("/html/links", test_links);
    Test.add_func ("/html/mentions-tags", test_mentions_and_tags);
    Test.add_func ("/html/sanitizer", test_sanitizer);
    Test.add_func ("/html/entities", test_entities);
    Test.add_func ("/html/styles", test_styles);
    Test.add_func ("/html/emoji", test_emoji);
    Test.add_func ("/html/attrs", test_attrs);
    return Test.run ();
}
