using Singularity.Apps.Fediverse;

void test_normalize () {
    assert (Oauth.normalize_instance ("mastodon.social") == "https://mastodon.social");
    assert (Oauth.normalize_instance ("  Mastodon.Social/ ") == "https://mastodon.social");
    assert (Oauth.normalize_instance ("https://gts.example/@me") == "https://gts.example");
    assert (Oauth.normalize_instance ("@ada@example.social") == "https://example.social");
    assert (Oauth.normalize_instance ("ada@example.social") == "https://example.social");
    assert (Oauth.normalize_instance ("social.example:8443") == "https://social.example:8443");
    assert (Oauth.normalize_instance ("http://insecure.example") == null);
    assert (Oauth.normalize_instance ("ftp://x.example") == null);
    assert (Oauth.normalize_instance ("") == null);
    assert (Oauth.normalize_instance ("nodot") == null);
    assert (Oauth.normalize_instance ("bad host.example") == null);
    assert (Oauth.normalize_instance ("a..b") == null);
    assert (Oauth.normalize_instance ("evil.example?x=1") == null);
    assert (Oauth.host_of ("https://Example.Social/@x") == "example.social");
    assert (Oauth.host_of ("not a url") == null);
}

void test_params () {
    var p = new Params ().add ("q", "a b&c=d/é").add ("media_ids[]", "1").add ("media_ids[]", "2").add ("empty", "");
    string enc = p.encode ();
    assert (enc == "q=a%20b%26c%3Dd%2F%C3%A9&media_ids[]=1&media_ids[]=2&empty=");
    var back = Params.decode (enc);
    assert (back.size == 4);
    assert (back.lookup ("q") == "a b&c=d/é");
    assert (back.lookup ("empty") == "");
    assert (Params.decode ("a=1+2&b").lookup ("a") == "1 2");
    assert (Params.decode ("a=1+2&b").lookup ("b") == "");
    assert (Params.decode ("").size == 0);
}

void test_authorize_url () {
    string url = Oauth.authorize_url ("https://example.social", "cid 1", Oauth.REDIRECT, "st4te");
    assert (url == "https://example.social/oauth/authorize?response_type=code&client_id=cid%201&redirect_uri=sinty-fediverse%3A%2F%2Foauth&scope=read%20write&state=st4te");
    string oob = Oauth.authorize_url ("https://gts.example", "id", Oauth.OOB, "x");
    assert (oob == "https://gts.example/oauth/authorize?response_type=code&client_id=id&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob&scope=read%20write");
    var reg = Oauth.registration_params ();
    assert (reg.lookup ("redirect_uris") == "sinty-fediverse://oauth\nurn:ietf:wg:oauth:2.0:oob");
    assert (reg.lookup ("scopes") == "read write");
    assert (reg.lookup ("client_name") == "Singularity Fediverse");
    assert (Oauth.registration_params (false).lookup ("redirect_uris") == Oauth.REDIRECT);
    var tok = Oauth.token_params ("id", "secret", Oauth.REDIRECT, "code123");
    assert (tok.encode () == "grant_type=authorization_code&code=code123&client_id=id&client_secret=secret&redirect_uri=sinty-fediverse%3A%2F%2Foauth&scope=read%20write");
}

void test_redirect () {
    string code, state, err;
    assert (Oauth.parse_redirect ("sinty-fediverse://oauth?code=abc%2Bdef&state=xyz", out code, out state, out err));
    assert (code == "abc+def" && state == "xyz" && err == "");
    assert (Oauth.parse_redirect ("SINTY-FEDIVERSE://oauth?error=access_denied&error_description=The+user+said+no", out code, out state, out err));
    assert (code == "" && err == "The user said no");
    assert (!Oauth.parse_redirect ("https://evil.example/?code=1", out code, out state, out err));
    assert (!Oauth.parse_redirect ("sinty-fediverse://oauth", out code, out state, out err));
    assert (!Oauth.parse_redirect ("sinty-fediverse://oauth?foo=bar", out code, out state, out err));
    assert (Oauth.parse_redirect ("sinty-fediverse://oauth?code=c#frag", out code, out state, out err) && code == "c");
}

void test_state_and_stream () {
    string a = Oauth.new_state (), b = Oauth.new_state ();
    assert (a.length == 32 && a != b);
    assert (Oauth.streaming_url ("https://example.social", "", "user") == "wss://example.social/api/v1/streaming?stream=user");
    assert (Oauth.streaming_url ("https://example.social", "wss://streaming.example.social/", "public:local") == "wss://streaming.example.social/api/v1/streaming?stream=public%3Alocal");
    assert (Oauth.streaming_url ("https://x.example", "", "hashtag", "café") == "wss://x.example/api/v1/streaming?stream=hashtag&tag=caf%C3%A9");
}

void test_store () {
    string path = Path.build_filename (Environment.get_tmp_dir (), "fediverse-store-%d.json".printf (Random.int_range (0, 1000000)));
    var s = new AccountStore (path);
    assert (s.items.size == 0 && s.active () == null);
    var a = new SavedAccount ();
    a.instance = "https://example.social";
    a.id = "1";
    a.username = "ada";
    a.acct = "ada";
    a.display_name = "Ada";
    a.client_id = "cid";
    a.client_secret = "sec";
    s.put (a);
    var b = new SavedAccount ();
    b.instance = "https://gts.example";
    b.id = "01X";
    b.username = "ada";
    s.current = b.key ();
    s.put (b);
    var rc = new RegisteredClient ();
    rc.instance = "https://example.social";
    rc.client_id = "cid";
    rc.client_secret = "sec";
    rc.oob = false;
    s.clients[rc.instance] = rc;
    s.pending_instance = "https://example.social";
    s.pending_state = "abc";
    s.save ();
    var again = new AccountStore (path);
    assert (again.items.size == 2);
    assert (again.find ("ada@example.social") != null);
    assert (again.find ("ada@example.social").client_secret == "sec");
    assert (again.active ().key () == "ada@gts.example");
    assert (again.active ().handle () == "@ada@gts.example");
    assert (again.clients["https://example.social"].client_id == "cid");
    assert (!again.clients["https://example.social"].oob);
    assert (again.pending_instance == "https://example.social" && again.pending_state == "abc");
    var dup = new SavedAccount ();
    dup.instance = "https://example.social";
    dup.username = "ada";
    dup.display_name = "Ada 2";
    again.put (dup);
    assert (again.items.size == 2 && again.find ("ada@example.social").display_name == "Ada 2");
    Posix.Stat st;
    assert (Posix.stat (path, out st) == 0 && (st.st_mode & 0777) == 0600);
    try {
        FileUtils.set_contents (path, "{broken");
    } catch (Error e) {
        assert_not_reached ();
    }
    assert (new AccountStore (path).items.size == 0);
    FileUtils.remove (path);
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C");
    Test.init (ref args);
    Test.add_func ("/oauth/normalize", test_normalize);
    Test.add_func ("/oauth/params", test_params);
    Test.add_func ("/oauth/authorize-url", test_authorize_url);
    Test.add_func ("/oauth/redirect", test_redirect);
    Test.add_func ("/oauth/state-stream", test_state_and_stream);
    Test.add_func ("/oauth/store", test_store);
    return Test.run ();
}
