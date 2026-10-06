using Singularity.Apps.Fediverse;

Json.Node load (string name) {
    var p = new Json.Parser ();
    try {
        p.load_from_file (Path.build_filename (Environment.get_variable ("FEDIVERSE_FIXTURES"), name));
    } catch (Error e) {
        assert_not_reached ();
    }
    return p.get_root ().copy ();
}

string read_fixture (string name) {
    try {
        string text;
        FileUtils.get_contents (Path.build_filename (Environment.get_variable ("FEDIVERSE_FIXTURES"), name), out text);
        return text;
    } catch (Error e) {
        assert_not_reached ();
    }
}

void test_account () {
    var a = Account.parse (load ("account.json").get_object ());
    assert (a != null);
    assert (a.id == "109302");
    assert (a.username == "ada" && a.acct == "ada@example.social");
    assert (a.name () == "Ada :blobcat: Lovelace");
    assert (a.handle () == "@ada@example.social");
    assert (a.avatar == "https://files.example.social/avatars/ada.png");
    assert (a.locked && !a.bot);
    assert (a.followers_count == 12450 && a.following_count == 310 && a.statuses_count == 999);
    assert (a.created_at != null && a.created_at.get_year () == 2022);
    assert (a.emojis.size == 1 && a.emojis[0].url == "https://files.example.social/emoji/blobcat.png");
    assert (a.fields.size == 2);
    assert (a.fields[0].verified && !a.fields[1].verified);
    assert (Content.parse (a.fields[0].value).plain () == "ada.example");
    var note = Content.parse (a.note, a.emojis);
    assert (note.plain () == "Engines & notes. Posts about #math");
    var local = new Account ();
    local.acct = "bob";
    local.username = "bob";
    local.url = "https://example.social/@bob";
    assert (local.handle () == "@bob@example.social");
    assert (local.handle ("home.example") == "@bob@home.example");
    assert (local.name () == "bob");
    assert (Account.parse (null) == null);
}

void test_timeline () {
    var list = Status.parse_list (load ("timeline.json"));
    assert (list.size == 2);
    var boost = list[0];
    assert (boost.reblog != null);
    assert (boost.account.username == "bob");
    assert (boost.url == boost.uri);
    var s = boost.shown ();
    assert (s.id == "112999");
    assert (s.account.name () == "carol");
    assert (s.account.handle () == "@carol@other.example");
    assert (s.visibility == Visibility.UNLISTED);
    assert (s.sensitive && s.spoiler_text == "Spoilers for the book");
    assert (s.in_reply_to_id == "112900" && s.in_reply_to_account_id == "7");
    assert (s.replies_count == 4 && s.reblogs_count == 12 && s.favourites_count == 1530);
    assert (s.favourited && s.reblogged && s.bookmarked);
    assert (s.edited_at != null);
    assert (s.media.size == 3);
    assert (s.media[0].kind == MediaType.IMAGE && s.media[0].description == "A book cover");
    assert (s.media[0].preview_url == "https://other.example/m1_small.jpg");
    assert (Math.fabs (s.media[0].aspect - 1.3333) < 1e-6);
    assert (s.media[1].kind == MediaType.GIFV && s.media[1].description == "");
    assert (Math.fabs (s.media[1].aspect - 640.0 / 480.0) < 1e-6);
    assert (s.media[2].kind == MediaType.UNKNOWN && s.media[2].url == "https://far.example/m3.bin" && s.media[2].preview_url == s.media[2].url);
    assert (s.mentions.size == 1 && s.mentions[0].id == "55");
    var body = s.body ();
    assert (body.plain () == "@dave The ending :blobcat: was great!");
    bool mention = false, emoji = false;
    foreach (var sp in body.spans) {
        if (sp.kind == SpanKind.MENTION && sp.target == "55") mention = true;
        if (sp.kind == SpanKind.EMOJI && sp.href == "https://other.example/e/blobcat.png") emoji = true;
    }
    assert (mention && emoji);
    var poll = s.poll;
    assert (poll != null && poll.multiple && poll.voted && !poll.expired);
    assert (poll.options.size == 2 && poll.options[1].title == "No :blobcat:");
    assert (poll.own_votes.size == 1 && poll.own_votes[0] == 1);
    assert (Math.fabs (poll.share (0) - 0.75) < 1e-9);
    assert (Math.fabs (poll.share (1) - 0.5) < 1e-9);
    assert (poll.share (5) == 0);
    var gts = list[1];
    assert (gts.reblog == null && gts.shown () == gts);
    assert (gts.visibility == Visibility.PRIVATE);
    assert (gts.account.emojis.size == 0 && gts.account.fields.size == 0);
    assert (gts.body ().plain () == "Hello from GoToSocial\nsecond line & more\n\nVisit https://gotosocial.org");
    assert (gts.poll == null);
    assert (gts.created_at != null && gts.created_at.get_hour () == 9);
}

void test_visibility () {
    assert (Visibility.parse ("direct") == Visibility.DIRECT);
    assert (Visibility.parse ("private") == Visibility.PRIVATE);
    assert (Visibility.parse ("unlisted") == Visibility.UNLISTED);
    assert (Visibility.parse ("public") == Visibility.PUBLIC);
    assert (Visibility.parse ("local") == Visibility.PUBLIC);
    assert (Visibility.DIRECT.to_api () == "direct");
    assert (Visibility.UNLISTED.to_api () == "unlisted");
    assert (MediaType.parse ("audio") == MediaType.AUDIO);
    assert (MediaType.parse ("video") == MediaType.VIDEO);
}

void test_notifications () {
    var list = Notice.parse_list (load ("notifications.json"));
    assert (list.size == 4);
    assert (list[0].kind == NotificationKind.FAVOURITE && list[0].status != null && list[0].status.id == "500");
    assert (list[0].summary () == "Carol liked your post");
    assert (list[1].kind == NotificationKind.FOLLOW && list[1].status == null);
    assert (list[1].summary () == "Frank followed you");
    assert (list[2].kind == NotificationKind.MENTION);
    assert (list[2].status.visibility == Visibility.DIRECT);
    assert (list[2].summary () == "gil mentioned you");
    assert (list[3].kind == NotificationKind.OTHER && list[3].raw_kind == "admin.sign_up");
    assert (NotificationKind.parse ("follow_request") == NotificationKind.FOLLOW_REQUEST);
    assert (NotificationKind.parse ("update") == NotificationKind.UPDATE);
    assert (NotificationKind.parse ("poll") == NotificationKind.POLL);
    assert (NotificationKind.parse ("reblog") == NotificationKind.REBLOG);
}

void test_context_search () {
    var c = Context.parse (load ("context.json"));
    assert (c.ancestors.size == 1 && c.ancestors[0].id == "10");
    assert (c.descendants.size == 2 && c.descendants[1].in_reply_to_id == "12");
    assert (Context.parse (null).ancestors.size == 0);
    var r = SearchResults.parse (load ("search.json"));
    assert (r.accounts.size == 1 && r.accounts[0].acct == "carol@other.example");
    assert (r.statuses.size == 1 && r.statuses[0].id == "600");
    assert (r.hashtags.size == 2 && r.hashtags[0] == "Vala" && r.hashtags[1] == "legacy");
    var rel = Relationship.parse (load ("relationships.json"));
    assert (rel != null && rel.following && !rel.followed_by && rel.id == "7");
    assert (Relationship.parse (new Json.Node (Json.NodeType.ARRAY).init_array (new Json.Array ())) == null);
}

void test_instance () {
    var v2 = InstanceInfo.parse (load ("instance_v2.json"));
    assert (v2.title == "Example Social");
    assert (v2.max_characters == 5000 && v2.max_media == 6 && v2.max_poll_options == 8 && v2.url_length == 23);
    assert (v2.streaming == "wss://streaming.example.social");
    var ak = InstanceInfo.parse (load ("instance_akkoma.json"));
    assert (ak.max_characters == 20000 && ak.max_media == 4);
    assert (ak.streaming == "wss://akkoma.example");
    var none = InstanceInfo.parse (null);
    assert (none.max_characters == 500 && none.streaming == "");
}

void test_stream () {
    var ev = StreamEvent.parse (read_fixture ("stream_update.json"));
    assert (ev != null && ev.event == "update");
    var s = Status.parse (ev.payload.get_object ());
    assert (s != null && s.id == "777" && s.body ().plain () == "live");
    var del = StreamEvent.parse ("{\"stream\":[\"user\"],\"event\":\"delete\",\"payload\":\"113\"}");
    assert (del.event == "delete" && del.payload_text == "113");
    assert (StreamEvent.parse ("not json") == null);
    assert (StreamEvent.parse ("{\"payload\":\"x\"}") == null);
}

void test_link_header () {
    string h = "<https://example.social/api/v1/bookmarks?max_id=7>; rel=\"next\", <https://example.social/api/v1/bookmarks?min_id=9>; rel=\"prev\"";
    assert (Text.next_link (h) == "https://example.social/api/v1/bookmarks?max_id=7");
    assert (Text.next_link ("<https://a/prev>; rel=\"prev\"") == null);
    assert (Text.next_link ("<https://a/n?x=1>;rel=next") == "https://a/n?x=1");
    assert (Text.next_link (null) == null);
    assert (Text.next_link ("garbage") == null);
}

void test_counter () {
    assert (Text.count_chars ("hello") == 5);
    assert (Text.count_chars ("héllo wörld") == 11);
    assert (Text.count_chars ("see https://example.com/a/very/long/path/that/goes/on") == 4 + 23);
    assert (Text.count_chars ("x https://a.example y https://b.example/zz", "", 23) == 2 + 23 + 3 + 23);
    assert (Text.count_chars ("hi @someone@very.long.example.social there") == 3 + 8 + 6);
    assert (Text.count_chars ("hi @local there") == 15);
    assert (Text.count_chars ("body", "warn") == 8);
    assert (Text.count_chars ("mail me@example.com") == 19);
    assert (Text.count_chars ("", "") == 0);
}

void test_text () {
    var now = new DateTime.utc (2026, 9, 25, 12, 0, 0);
    assert (Text.relative_time (new DateTime.utc (2026, 9, 25, 11, 59, 30), now) == "now");
    assert (Text.relative_time (new DateTime.utc (2026, 9, 25, 11, 45, 0), now) == "15m");
    assert (Text.relative_time (new DateTime.utc (2026, 9, 25, 9, 0, 0), now) == "3h");
    assert (Text.relative_time (new DateTime.utc (2026, 9, 22, 12, 0, 0), now) == "3d");
    assert (Text.relative_time (null, now) == "");
    assert (Text.compact (999) == "999");
    assert (Text.compact (1530) == "1.5K");
    assert (Text.compact (2000) == "2K");
    assert (Text.compact (12450) == "12K");
    assert (Text.compact (2300000) == "2.3M");
}


void test_filters () {
    var list = Filter.parse_list (load ("filters.json"));
    assert (list.size == 3);
    var spoil = list[0];
    assert (spoil.id == "11" && spoil.title == "Spoilers" && !spoil.hides ());
    assert (spoil.context.size == 3 && spoil.applies ("home") && spoil.applies ("thread") && !spoil.applies ("notifications") && !spoil.applies (""));
    assert (spoil.keywords.size == 2 && spoil.keywords[0].id == "101" && spoil.keywords[0].whole_word && !spoil.keywords[1].whole_word);
    assert (spoil.expires_at == null && spoil.statuses == 0);
    assert (spoil.summary () == "Warns about posts with finale, ending");
    var crypto = list[1];
    assert (crypto.hides () && crypto.statuses == 1 && crypto.expires_at.get_year () == 2030);
    assert (!crypto.expired (new DateTime.utc (2029, 1, 1, 0, 0, 0)) && crypto.expired (new DateTime.utc (2030, 1, 1, 0, 0, 0)));
    assert (crypto.summary () == "Hides posts with nft");
    var legacy = list[2];
    assert (legacy.title == "legacy words" && legacy.hides () && legacy.keywords.size == 1 && !legacy.keywords[0].whole_word);
    assert (Filter.parse_list (null).size == 0);
}

void test_filtered_statuses () {
    var list = Status.parse_list (load ("timeline_filtered.json"));
    assert (list.size == 4);
    var now = new DateTime.utc (2026, 9, 26, 0, 0, 0);
    string titles;
    assert (list[0].filtered.size == 1 && list[0].filtered[0].keywords[0] == "finale");
    assert (Filters.verdict (list[0], "home", out titles, now) == FilterVerdict.WARN && titles == "Spoilers");
    assert (Filters.verdict (list[0], "notifications", out titles, now) == FilterVerdict.SHOW && titles == "");
    assert (Filters.verdict (list[0], "", out titles, now) == FilterVerdict.SHOW);
    assert (Filters.verdict (list[1], "home", out titles, now) == FilterVerdict.HIDE);
    assert (Filters.verdict (list[1], "public", out titles, now) == FilterVerdict.SHOW);
    assert (Filters.verdict (list[2], "home", out titles, now) == FilterVerdict.WARN && titles == "Spoilers");
    assert (Filters.verdict (list[2], "thread", out titles, now) == FilterVerdict.SHOW);
    assert (Filters.verdict (list[3], "home", out titles, now) == FilterVerdict.SHOW);
}

void test_filter_requests () {
    var kws = new Gee.ArrayList<FilterKeyword> ();
    var keep = new FilterKeyword ("finale", true);
    keep.id = "101";
    kws.add (keep);
    var gone = new FilterKeyword ("ending", false);
    gone.id = "102";
    gone.destroy = true;
    kws.add (gone);
    kws.add (new FilterKeyword ("season 2", false));
    kws.add (new FilterKeyword ("  ", true));
    var dropped = new FilterKeyword ("never sent", true);
    dropped.destroy = true;
    kws.add (dropped);
    var ctx = new Gee.ArrayList<string> ();
    ctx.add ("home");
    ctx.add ("public");
    var p = Requests.filter (" Spoilers ", ctx, false, 86400, kws);
    assert (p.encode () == "title=Spoilers&context[]=home&context[]=public&filter_action=warn&expires_in=86400"
        + "&keywords_attributes[0][id]=101&keywords_attributes[0][keyword]=finale&keywords_attributes[0][whole_word]=true"
        + "&keywords_attributes[1][id]=102&keywords_attributes[1][_destroy]=true"
        + "&keywords_attributes[2][keyword]=season%202&keywords_attributes[2][whole_word]=false");
    var h = Requests.filter ("x", new Gee.ArrayList<string> (), true, 0, new Gee.ArrayList<FilterKeyword> ());
    assert (h.lookup ("filter_action") == "hide" && h.lookup ("expires_in") == "");
    var back = Params.decode (p.encode ());
    assert (back.size == p.size && back.lookup ("title") == "Spoilers");
}

void test_scheduled () {
    var list = ScheduledStatus.parse_list (load ("scheduled.json"));
    assert (list.size == 2);
    assert (list[0].id == "3220" && list[1].id == "3221");
    var a = list[1];
    assert (a.text == "Launch day!" && a.visibility == Visibility.UNLISTED && !a.sensitive && a.spoiler_text == "" && a.in_reply_to_id == "");
    assert (a.scheduled_at.equal (new DateTime.utc (2026, 10, 2, 9, 30, 0)));
    assert (a.media.size == 1 && a.media[0].description == "Poster");
    assert (a.media_ids.size == 2 && a.media_ids[0] == "44" && a.media_ids[1] == "45");
    var b = list[0];
    assert (b.spoiler_text == "cw" && b.sensitive && b.in_reply_to_id == "77" && b.visibility == Visibility.PRIVATE);
    assert (ScheduledStatus.parse (null) == null);
}

void test_status_requests () {
    TimeZone rome;
    try {
        rome = new TimeZone.identifier ("Europe/Rome");
    } catch (Error e) {
        assert_not_reached ();
    }
    var at = new DateTime (rome, 2026, 10, 2, 11, 30, 0);
    assert (Requests.scheduled_at_text (at) == "2026-10-02T09:30:00.000Z");
    var media = new Gee.ArrayList<string> ();
    media.add ("44");
    media.add ("45");
    var p = Requests.status ("  Launch day! ", "", Visibility.UNLISTED, true, "", media, at);
    assert (p.encode () == "status=Launch%20day%21&visibility=unlisted&sensitive=true&media_ids[]=44&media_ids[]=45&scheduled_at=2026-10-02T09%3A30%3A00.000Z");
    var r = Requests.status ("hi @bob", "spoiler", Visibility.DIRECT, false, "77", new Gee.ArrayList<string> (), null);
    assert (r.encode () == "status=hi%20%40bob&visibility=direct&spoiler_text=spoiler&sensitive=true&in_reply_to_id=77");
    assert (r.lookup ("scheduled_at") == null);
    var q = Requests.status ("text", "", Visibility.PUBLIC, true, "", new Gee.ArrayList<string> (), null, "it");
    assert (q.lookup ("sensitive") == null && q.lookup ("language") == "it");
    assert (Requests.reschedule (at).encode () == "scheduled_at=2026-10-02T09%3A30%3A00.000Z");
    var now = new DateTime.utc (2026, 10, 2, 9, 0, 0);
    assert (Requests.schedule_problem (now.add_minutes (4), now) != null);
    assert (Requests.schedule_problem (now.add_minutes (-10), now) != null);
    assert (Requests.schedule_problem (now.add_minutes (5), now) == null);
    assert (Requests.schedule_problem (now.add_days (30), now) == null);
}

void test_translation () {
    var info = InstanceInfo.parse (load ("instance_translate.json"));
    assert (info.translation);
    assert (!InstanceInfo.parse (load ("instance_v2.json")).translation);
    assert (!InstanceInfo.parse (load ("instance_akkoma.json")).translation);
    var t = PostTranslation.parse (load ("translation.json"));
    assert (t != null && t.detected == "en" && t.provider == "DeepL.com");
    assert (Content.parse (t.content).plain () == "Ciao mondo");
    assert (PostTranslation.parse (null) == null);
    assert (Requests.translate_path ("113/x") == "/api/v1/statuses/113%2Fx/translate");
    assert (Requests.language_code ("it_IT.UTF-8") == "it");
    assert (Requests.language_code ("de_DE@euro") == "de");
    assert (Requests.language_code ("pt_BR.UTF-8") == "pt-BR");
    assert (Requests.language_code ("zh_TW") == "zh-TW");
    assert (Requests.language_code ("C.UTF-8") == "en");
    assert (Requests.language_code (null) == "en");
    assert (Requests.same_language ("en", "en-GB") && !Requests.same_language ("en", "it") && !Requests.same_language ("", "it"));
}

void test_domains () {
    var d = BlockedDomain.parse_list (load ("domain_blocks.json"));
    assert (d.size == 3 && d[0].domain == "spam.example" && d[2].domain == "gts.example");
}

void test_merge () {
    var a = Status.parse_list (load ("timeline_filtered.json"));
    foreach (var s in a) s.tag_via ("ann@a.example");
    var b = Status.parse_list (load ("home_b.json"));
    foreach (var s in b) s.tag_via ("zed@b.example");
    assert (b[1].reblog.via == "zed@b.example");
    var sources = new Gee.ArrayList<Gee.List<Status>> ();
    sources.add (a);
    sources.add (b);
    var merged = Merge.timelines (sources);
    string[] ids = {};
    foreach (var s in merged) ids += s.id;
    assert (string.joinv (",", ids) == "900,200,901,201,202");
    assert (merged[2].via == "zed@b.example" && merged[2].merge_key () == "https://a.example/s/203");
    foreach (var s in merged) assert (s.merged);
    var seen = new Gee.HashSet<string> ();
    seen.add ("https://c.example/s/900");
    var again = Merge.timelines (sources, seen);
    assert (again.size == 4 && again[0].id == "200");
    var nouri = new Status ();
    nouri.id = "5";
    nouri.via = "x";
    assert (nouri.merge_key () == "x/5");
}

void test_drafts () {
    string path = Path.build_filename (Environment.get_tmp_dir (), "drafts-%d.json".printf (Random.int_range (0, 1000000)));
    var store = new DraftStore (path);
    assert (store.items.size == 0);
    var d = new Draft ();
    d.account = "ann@a.example";
    d.text = "Hello\nworld";
    d.visibility = Visibility.PRIVATE;
    d.reply_to_id = "77";
    d.reply_to_handle = "@bob@b.example";
    d.reply_snippet = "original";
    store.put (d, 100);
    var e = new Draft ();
    e.account = "ann@a.example";
    e.spoiler_text = "cw";
    e.sensitive = true;
    e.replaces_scheduled = "3221";
    store.put (e, 200);
    var other = new Draft ();
    other.account = "zed@b.example";
    other.text = "x";
    store.put (other, 150);
    var empty = new Draft ();
    empty.account = "ann@a.example";
    store.put (empty, 300);
    assert (store.items.size == 3 && store.count ("ann@a.example") == 2);
    var again = new DraftStore (path);
    var mine = again.for_account ("ann@a.example");
    assert (mine.size == 2 && mine[0].id == e.id && mine[1].id == d.id);
    assert (mine[1].text == "Hello\nworld" && mine[1].visibility == Visibility.PRIVATE && mine[1].reply_to_handle == "@bob@b.example" && mine[1].updated == 100);
    assert (mine[0].sensitive && mine[0].replaces_scheduled == "3221" && mine[0].preview () == "cw");
    assert (mine[1].preview () == "Hello world");
    d.text = "";
    store.put (d, 400);
    assert (store.find (d.id) == null);
    store.remove (e.id);
    assert (new DraftStore (path).items.size == 1);
    store.remove (other.id);
    FileUtils.remove (path);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Environment.set_variable ("TZ", "UTC", true);
    Test.init (ref args);
    Test.add_func ("/api/account", test_account);
    Test.add_func ("/api/timeline", test_timeline);
    Test.add_func ("/api/visibility", test_visibility);
    Test.add_func ("/api/notifications", test_notifications);
    Test.add_func ("/api/context-search", test_context_search);
    Test.add_func ("/api/instance", test_instance);
    Test.add_func ("/api/stream", test_stream);
    Test.add_func ("/api/link-header", test_link_header);
    Test.add_func ("/api/counter", test_counter);
    Test.add_func ("/api/text", test_text);
    Test.add_func ("/api/filters", test_filters);
    Test.add_func ("/api/filtered-statuses", test_filtered_statuses);
    Test.add_func ("/api/filter-requests", test_filter_requests);
    Test.add_func ("/api/scheduled", test_scheduled);
    Test.add_func ("/api/status-requests", test_status_requests);
    Test.add_func ("/api/translation", test_translation);
    Test.add_func ("/api/domains", test_domains);
    Test.add_func ("/api/merge", test_merge);
    Test.add_func ("/api/drafts", test_drafts);
    return Test.run ();
}
