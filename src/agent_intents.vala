namespace Singularity.Apps.Fediverse {

    internal class FediverseIntents : Object {
        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key).strip () : "";
        }

        private static int number (Json.Object args, string key, int fallback, int max) {
            if (!args.has_member (key)) return fallback;
            return (int) args.get_int_member (key).clamp (1, max);
        }

        private static SavedAccount account (FediverseApp app, string wanted) throws Error {
            if (app.store.items.size == 0) throw new IOError.NOT_FOUND ("no Fediverse account is set up; the person adds one in Fediverse first");
            if (wanted == "") {
                var a = app.store.active ();
                if (a != null) return a;
                return app.store.items[0];
            }
            string w = wanted.casefold ().replace ("@", "");
            foreach (var a in app.store.items) {
                if (a.key () == wanted || a.handle ().casefold ().replace ("@", "") == w || a.acct.casefold () == w || a.username.casefold () == w) return a;
            }
            throw new IOError.NOT_FOUND ("no account %s; see fediverse_accounts", wanted);
        }

        private static async Session session (FediverseApp app, Json.Object args) throws Error {
            var a = account (app, text (args, "account"));
            string? token = yield AccountStore.lookup_token (a.key ());
            if (token == null || token == "") throw new IOError.PERMISSION_DENIED ("%s is signed out; the person signs in again in Fediverse", a.handle ());
            return new Session (a, token);
        }

        private static string plain (Status s) {
            return Content.parse (s.content, s.emojis, s.mentions).plain ().strip ();
        }

        private static void author (Json.Builder b, string member, Account a) {
            b.set_member_name (member).begin_object ();
            b.set_member_name ("id").add_string_value (a.id);
            b.set_member_name ("handle").add_string_value ("@" + a.acct);
            b.set_member_name ("name").add_string_value (a.name ());
            b.end_object ();
        }

        private static void status (Json.Builder b, Status raw) {
            var s = raw.shown ();
            b.begin_object ();
            b.set_member_name ("id").add_string_value (s.id);
            author (b, "author", s.account);
            if (raw.reblog != null) b.set_member_name ("boosted_by").add_string_value ("@" + raw.account.acct);
            if (s.spoiler_text != "") b.set_member_name ("content_warning").add_string_value (s.spoiler_text);
            b.set_member_name ("text").add_string_value (plain (s));
            if (s.created_at != null) b.set_member_name ("posted").add_string_value (s.created_at.to_local ().format_iso8601 ());
            b.set_member_name ("visibility").add_string_value (s.visibility.to_api ());
            if (s.in_reply_to_id != "") b.set_member_name ("reply_to").add_string_value (s.in_reply_to_id);
            if (s.media.size > 0) {
                b.set_member_name ("media").begin_array ();
                foreach (var m in s.media) b.add_string_value (m.description != "" ? m.description : "(no description)");
                b.end_array ();
            }
            if (s.poll != null) {
                b.set_member_name ("poll").begin_array ();
                foreach (var o in s.poll.options) b.add_string_value (o.votes >= 0 ? "%s (%lld)".printf (o.title, o.votes) : o.title);
                b.end_array ();
            }
            b.set_member_name ("replies").add_int_value (s.replies_count);
            b.set_member_name ("boosts").add_int_value (s.reblogs_count);
            b.set_member_name ("favourites").add_int_value (s.favourites_count);
            if (s.favourited) b.set_member_name ("favourited").add_boolean_value (true);
            if (s.reblogged) b.set_member_name ("boosted").add_boolean_value (true);
            if (s.bookmarked) b.set_member_name ("bookmarked").add_boolean_value (true);
            if (s.url != "") b.set_member_name ("url").add_string_value (s.url);
            b.end_object ();
        }

        private static void notification (Json.Builder b, Json.Object o) {
            b.begin_object ();
            b.set_member_name ("id").add_string_value (J.str (o, "id"));
            b.set_member_name ("type").add_string_value (J.str (o, "type"));
            var who = Account.parse (J.obj (o, "account"));
            if (who != null) author (b, "from", who);
            string when = J.str (o, "created_at");
            if (when != "") b.set_member_name ("when").add_string_value (when);
            var s = Status.parse (J.obj (o, "status"));
            if (s != null) {
                b.set_member_name ("post");
                status (b, s);
            }
            b.end_object ();
        }

        private static async Status read_back (Session s, string id) throws Error {
            return yield s.client.status (id);
        }

        private static string feed_path (string feed, string arg, Params p) throws Error {
            switch (feed) {
                case "":
                case "home": return "/api/v1/timelines/home";
                case "local":
                    p.add ("local", "true");
                    return "/api/v1/timelines/public";
                case "federated": return "/api/v1/timelines/public";
                case "notifications": return "/api/v1/notifications";
                case "bookmarks": return "/api/v1/bookmarks";
                case "favourites": return "/api/v1/favourites";
                case "hashtag":
                    if (arg == "") throw new IOError.INVALID_ARGUMENT ("give the hashtag");
                    return "/api/v1/timelines/tag/" + Uri.escape_string (arg.has_prefix ("#") ? arg.substring (1) : arg, null, false);
                default:
                    throw new IOError.INVALID_ARGUMENT ("feed is home, local, federated, notifications, bookmarks, favourites or hashtag");
            }
        }

        private static async Account find_account (Session s, string wanted) throws Error {
            if (wanted == "") throw new IOError.INVALID_ARGUMENT ("give the account handle, like @name@server");
            var r = yield s.client.search (wanted, true);
            string w = wanted.has_prefix ("@") ? wanted.substring (1) : wanted;
            foreach (var a in r.accounts) if (a.acct.casefold () == w.casefold () || a.id == wanted) return a;
            if (r.accounts.size == 1) return r.accounts[0];
            if (r.accounts.size == 0) throw new IOError.NOT_FOUND ("no account %s was found", wanted);
            throw new IOError.INVALID_ARGUMENT ("%s matches %d accounts; use the full @name@server handle", wanted, r.accounts.size);
        }

        private static async void dispatch (FediverseApp app, string name, Json.Object args, owned Singularity.AppIntentReply reply) {
            app.hold ();
            try {
                var b = new Json.Builder ();
                b.begin_object ();
                switch (name) {
                    case "timeline": yield timeline (app, args, b); break;
                    case "read": yield read_work (app, args, b); break;
                    case "search": yield search_work (app, args, b); break;
                    case "post": yield post_work (app, args, b); break;
                    case "delete": yield remove_work (app, args, b); break;
                    case "act": yield act_work (app, args, b); break;
                    default: yield follow_work (app, args, b); break;
                }
                b.end_object ();
                reply (b.get_root (), null);
            } catch (Error e) {
                reply (null, e);
            } finally {
                app.release ();
            }
        }

        internal static void install (FediverseApp app) {
            var agent = app.agent;
            agent.add_intent ("fediverse_accounts", "The Fediverse (Mastodon) accounts signed in to this app, and which one is in use.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("accounts").begin_array ();
                    var active = app.store.active ();
                    foreach (var a in app.store.items) {
                        b.begin_object ();
                        b.set_member_name ("handle").add_string_value (a.handle ());
                        b.set_member_name ("name").add_string_value (a.name ());
                        b.set_member_name ("server").add_string_value (a.instance);
                        if (active != null && active.key () == a.key ()) b.set_member_name ("in_use").add_boolean_value (true);
                        b.end_object ();
                    }
                    b.end_array ();
                    b.end_object ();
                    return b.get_root ();
                });
            agent.add_async_intent ("fediverse_timeline", "Read a Fediverse feed: home, local, federated, notifications, bookmarks, favourites or a hashtag, newest first.",
                "{\"type\":\"object\",\"properties\":{\"feed\":{\"type\":\"string\",\"enum\":[\"home\",\"local\",\"federated\",\"notifications\",\"bookmarks\",\"favourites\",\"hashtag\"]},\"hashtag\":{\"type\":\"string\"},\"limit\":{\"type\":\"integer\"},\"account\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    dispatch.begin (app, "timeline", args, (owned) reply);
                });
            agent.add_async_intent ("fediverse_read", "Read one post in full with the thread around it: the posts it answers and the replies.",
                "{\"type\":\"object\",\"properties\":{\"post\":{\"type\":\"string\",\"description\":\"post id\"},\"account\":{\"type\":\"string\"}},\"required\":[\"post\"]}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    dispatch.begin (app, "read", args, (owned) reply);
                });
            agent.add_async_intent ("fediverse_search", "Search the Fediverse for accounts, posts and hashtags.",
                "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},\"account\":{\"type\":\"string\"}},\"required\":[\"query\"]}",
                Singularity.AppIntentRisk.READ, (args, reply) => {
                    dispatch.begin (app, "search", args, (owned) reply);
                });
            agent.add_async_intent ("fediverse_post", "Publish a post, optionally as a reply, with a content warning, a visibility or at a later time. Others can see it as soon as it is sent.",
                "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"},\"visibility\":{\"type\":\"string\",\"enum\":[\"public\",\"unlisted\",\"private\",\"direct\"]},\"content_warning\":{\"type\":\"string\"},\"reply_to\":{\"type\":\"string\"},\"language\":{\"type\":\"string\"},\"at\":{\"type\":\"string\",\"description\":\"ISO 8601 time, at least 5 minutes ahead\"},\"account\":{\"type\":\"string\"}},\"required\":[\"text\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args, reply) => {
                    dispatch.begin (app, "post", args, (owned) reply);
                });
            agent.add_async_intent ("fediverse_delete", "Delete one of the person's own posts, or cancel one of their scheduled posts.",
                "{\"type\":\"object\",\"properties\":{\"post\":{\"type\":\"string\"},\"scheduled\":{\"type\":\"boolean\"},\"account\":{\"type\":\"string\"}},\"required\":[\"post\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args, reply) => {
                    dispatch.begin (app, "delete", args, (owned) reply);
                });
            agent.add_async_intent ("fediverse_act", "Favourite, boost or bookmark a post, or undo it.",
                "{\"type\":\"object\",\"properties\":{\"post\":{\"type\":\"string\"},\"action\":{\"type\":\"string\",\"enum\":[\"favourite\",\"unfavourite\",\"boost\",\"unboost\",\"bookmark\",\"unbookmark\"]},\"account\":{\"type\":\"string\"}},\"required\":[\"post\",\"action\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    dispatch.begin (app, "act", args, (owned) reply);
                });
            agent.add_async_intent ("fediverse_follow", "Follow or unfollow an account.",
                "{\"type\":\"object\",\"properties\":{\"handle\":{\"type\":\"string\"},\"follow\":{\"type\":\"boolean\"},\"account\":{\"type\":\"string\"}},\"required\":[\"handle\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args, reply) => {
                    dispatch.begin (app, "follow", args, (owned) reply);
                });
            agent.add_intent ("fediverse_compose", "Open the Fediverse post window with text already written, for the person to read, change and send themselves.",
                "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string t = text (args, "text");
                    if (t == "") throw new IOError.INVALID_ARGUMENT ("give the text of the post");
                    account (app, "");
                    app.activate_action ("compose-text", new Variant.string (t));
                    var b = new Json.Builder ();
                    b.begin_object ();
                    b.set_member_name ("opened").add_string_value ("post window");
                    b.set_member_name ("sent").add_boolean_value (false);
                    b.set_member_name ("undo").add_string_value ("the person closes the post window; nothing was published");
                    b.end_object ();
                    return b.get_root ();
                });
        }

        private static async void timeline (FediverseApp app, Json.Object args, Json.Builder b) throws Error {
            var p = new Params ();
            string feed = text (args, "feed");
            string path = feed_path (feed, text (args, "hashtag"), p);
            var s = yield session (app, args);
            p.add ("limit", number (args, "limit", 20, 40).to_string ());
            var root = yield s.client.call ("GET", path, p);
            b.set_member_name ("account").add_string_value (s.saved.handle ());
            b.set_member_name ("feed").add_string_value (feed == "" ? "home" : feed);
            b.set_member_name ("items").begin_array ();
            if (root != null && root.get_node_type () == Json.NodeType.ARRAY) {
                foreach (var n in root.get_array ().get_elements ()) {
                    if (n.get_node_type () != Json.NodeType.OBJECT) continue;
                    if (feed == "notifications") {
                        notification (b, n.get_object ());
                    } else {
                        var st = Status.parse (n.get_object ());
                        if (st != null) status (b, st);
                    }
                }
            }
            b.end_array ();
        }


        private static async void read_work (FediverseApp app, Json.Object args, Json.Builder b) throws Error {
            var s = yield session (app, args);
            string id = text (args, "post");
            if (id == "") throw new IOError.INVALID_ARGUMENT ("give the post id");
            var st = yield s.client.status (id);
            var ctx = yield s.client.context (id);
            b.set_member_name ("post");
            status (b, st);
            b.set_member_name ("answers").begin_array ();
            foreach (var a in ctx.ancestors) status (b, a);
            b.end_array ();
            b.set_member_name ("replies").begin_array ();
            foreach (var d in ctx.descendants) status (b, d);
            b.end_array ();
        }


        private static async void search_work (FediverseApp app, Json.Object args, Json.Builder b) throws Error {
            string q = text (args, "query");
            if (q == "") throw new IOError.INVALID_ARGUMENT ("give what to search for");
            var s = yield session (app, args);
            var r = yield s.client.search (q, true);
            b.set_member_name ("accounts").begin_array ();
            foreach (var a in r.accounts) {
                b.begin_object ();
                b.set_member_name ("handle").add_string_value ("@" + a.acct);
                b.set_member_name ("name").add_string_value (a.name ());
                b.set_member_name ("followers").add_int_value (a.followers_count);
                b.set_member_name ("about").add_string_value (Content.parse (a.note, a.emojis).plain ().strip ());
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("posts").begin_array ();
            foreach (var st in r.statuses) status (b, st);
            b.end_array ();
            b.set_member_name ("hashtags").begin_array ();
            foreach (string h in r.hashtags) b.add_string_value ("#" + h);
            b.end_array ();
        }


        private static async void post_work (FediverseApp app, Json.Object args, Json.Builder b) throws Error {
            string body = text (args, "text");
            if (body == "") throw new IOError.INVALID_ARGUMENT ("give the text of the post");
            string vis = text (args, "visibility");
            if (vis != "" && vis != "public" && vis != "unlisted" && vis != "private" && vis != "direct") throw new IOError.INVALID_ARGUMENT ("visibility is public, unlisted, private or direct");
            DateTime? at = null;
            if (text (args, "at") != "") {
                at = new DateTime.from_iso8601 (text (args, "at"), new TimeZone.local ());
                if (at == null) throw new IOError.INVALID_ARGUMENT ("%s is not an ISO 8601 time", text (args, "at"));
                string? problem = Requests.schedule_problem (at, new DateTime.now_local ());
                if (problem != null) throw new IOError.INVALID_ARGUMENT ("%s", problem);
            }
            var s = yield session (app, args);
            var p = Requests.status (body, text (args, "content_warning"), Visibility.parse (vis), false, text (args, "reply_to"), new Gee.ArrayList<string> (), at, text (args, "language"));
            string key = Uuid.string_random ();
            b.set_member_name ("account").add_string_value (s.saved.handle ());
            if (at != null) {
                var sch = yield s.client.post_scheduled (p, key);
                bool listed = false;
                foreach (var x in yield s.client.scheduled ()) if (x.id == sch.id) listed = true;
                if (!listed) throw new IOError.FAILED ("the server did not keep the scheduled post");
                b.set_member_name ("scheduled").add_string_value (sch.id);
                b.set_member_name ("at").add_string_value (sch.scheduled_at != null ? sch.scheduled_at.to_local ().format_iso8601 () : text (args, "at"));
                b.set_member_name ("undo").add_string_value ("fediverse_delete with post %s and scheduled true".printf (sch.id));
                return;
            }
            var sent = yield s.client.post (p, key);
            var check = yield read_back (s, sent.id);
            b.set_member_name ("posted");
            status (b, check);
            b.set_member_name ("undo").add_string_value ("fediverse_delete with post " + sent.id);
        }


        private static async void remove_work (FediverseApp app, Json.Object args, Json.Builder b) throws Error {
            string id = text (args, "post");
            if (id == "") throw new IOError.INVALID_ARGUMENT ("give the post id");
            var s = yield session (app, args);
            if (args.has_member ("scheduled") && args.get_boolean_member ("scheduled")) {
                yield s.client.cancel_scheduled (id);
                foreach (var x in yield s.client.scheduled ()) if (x.id == id) throw new IOError.FAILED ("the scheduled post %s is still there", id);
                b.set_member_name ("cancelled").add_string_value (id);
                return;
            }
            var st = yield s.client.status (id);
            var me = yield s.client.verify_credentials ();
            if (st.account.id != me.id) throw new IOError.PERMISSION_DENIED ("post %s belongs to @%s; only the person's own posts can be deleted", id, st.account.acct);
            string was = plain (st);
            yield s.client.delete_status (id);
            try {
                yield s.client.status (id);
                throw new IOError.FAILED ("post %s is still there", id);
            } catch (ApiError.NOT_FOUND e) {
            }
            b.set_member_name ("deleted").add_string_value (id);
            b.set_member_name ("text").add_string_value (was);
        }


        private static async void act_work (FediverseApp app, Json.Object args, Json.Builder b) throws Error {
            string id = text (args, "post");
            string action = text (args, "action");
            string verb;
            string undo;
            switch (action) {
                case "favourite": verb = "favourite"; undo = "unfavourite"; break;
                case "unfavourite": verb = "unfavourite"; undo = "favourite"; break;
                case "boost": verb = "reblog"; undo = "unboost"; break;
                case "unboost": verb = "unreblog"; undo = "boost"; break;
                case "bookmark": verb = "bookmark"; undo = "unbookmark"; break;
                case "unbookmark": verb = "unbookmark"; undo = "bookmark"; break;
                default: throw new IOError.INVALID_ARGUMENT ("action is favourite, unfavourite, boost, unboost, bookmark or unbookmark");
            }
            if (id == "") throw new IOError.INVALID_ARGUMENT ("give the post id");
            var s = yield session (app, args);
            yield s.client.act (id, verb);
            var check = (yield read_back (s, id)).shown ();
            bool want = !action.has_prefix ("un");
            bool now = action.has_suffix ("favourite") ? check.favourited : (action.has_suffix ("boost") ? check.reblogged : check.bookmarked);
            if (now != want) throw new IOError.FAILED ("the server did not %s post %s", action, id);
            b.set_member_name ("post");
            status (b, check);
            b.set_member_name ("undo").add_string_value ("fediverse_act with post %s and action %s".printf (id, undo));
        }


        private static async void follow_work (FediverseApp app, Json.Object args, Json.Builder b) throws Error {
            bool on = !args.has_member ("follow") || args.get_boolean_member ("follow");
            var s = yield session (app, args);
            var who = yield find_account (s, text (args, "handle"));
            yield s.client.follow (who.id, on);
            var rel = yield s.client.relationship (who.id);
            if (rel == null) throw new IOError.FAILED ("the server did not confirm the follow");
            bool following = rel.following || rel.requested;
            if (following != on) throw new IOError.FAILED ("the server did not %s @%s", on ? "follow" : "unfollow", who.acct);
            b.set_member_name ("handle").add_string_value ("@" + who.acct);
            b.set_member_name ("following").add_boolean_value (rel.following);
            if (rel.requested) b.set_member_name ("requested").add_boolean_value (true);
            b.set_member_name ("undo").add_string_value ("fediverse_follow with handle @%s and follow %s".printf (who.acct, on ? "false" : "true"));
        }
    }
}
