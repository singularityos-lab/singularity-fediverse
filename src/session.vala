namespace Singularity.Apps.Fediverse {

    public class Session : Object {
        public SavedAccount saved;
        public Client client;
        public InstanceInfo info = new InstanceInfo ();
        public Account? me;

        public Session (SavedAccount saved, string token) {
            this.saved = saved;
            client = new Client (saved.instance, token);
        }

        public string host () {
            return Oauth.host_of (saved.instance) ?? saved.instance;
        }

        public bool is_me (Account a) {
            return a.id == saved.id && (a.acct == saved.acct || a.acct == saved.username);
        }
    }

    public interface Navigator : Object {
        public abstract Session? session { get; }
        public abstract void open_status (Status s);
        public abstract void open_account (Account a);
        public abstract void open_mention (string account_id, string url);
        public abstract void open_tag (string tag);
        public abstract void open_link (string url);
        public abstract void reply (Status s);
        public abstract void view_media (Gee.List<Attachment> media, int index);
        public abstract void show_error (string text);
        public abstract void status_deleted (string id);
        public abstract void signed_out ();
        public abstract Session? session_for (Status s);
        public abstract SavedAccount? saved_account (string key);
        public abstract void open_draft (Draft d);
        public abstract void delete_draft (Draft d);
        public abstract void edit_scheduled (ScheduledStatus s);
        public abstract void reschedule (ScheduledStatus s);
        public abstract void cancel_scheduled (ScheduledStatus s);
        public abstract void moderate (Status s, string verb);
    }
}
