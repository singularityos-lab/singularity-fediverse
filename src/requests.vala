namespace Singularity.Apps.Fediverse {

    namespace Requests {
        public const int MIN_SCHEDULE_MINUTES = 5;

        public string scheduled_at_text (DateTime at) {
            return at.to_utc ().format ("%Y-%m-%dT%H:%M:%S.000Z");
        }

        public string? schedule_problem (DateTime at, DateTime now) {
            if (at.difference (now) < MIN_SCHEDULE_MINUTES * TimeSpan.MINUTE) {
                return ngettext ("Choose a time at least %d minute from now.", "Choose a time at least %d minutes from now.", MIN_SCHEDULE_MINUTES).printf (MIN_SCHEDULE_MINUTES);
            }
            return null;
        }

        public Params status (string text, string spoiler, Visibility visibility, bool sensitive, string reply_to, Gee.List<string> media_ids, DateTime? scheduled_at, string language = "") {
            var p = new Params ();
            p.add ("status", text.strip ());
            p.add ("visibility", visibility.to_api ());
            if (spoiler.strip () != "") {
                p.add ("spoiler_text", spoiler.strip ());
                p.add ("sensitive", "true");
            } else if (sensitive && media_ids.size > 0) {
                p.add ("sensitive", "true");
            }
            if (reply_to != "") p.add ("in_reply_to_id", reply_to);
            foreach (string id in media_ids) p.add ("media_ids[]", id);
            if (language != "") p.add ("language", language);
            if (scheduled_at != null) p.add ("scheduled_at", scheduled_at_text (scheduled_at));
            return p;
        }

        public Params reschedule (DateTime at) {
            return new Params ().add ("scheduled_at", scheduled_at_text (at));
        }

        public Params filter (string title, Gee.List<string> contexts, bool hide, int expires_in, Gee.List<FilterKeyword> keywords) {
            var p = new Params ();
            p.add ("title", title.strip ());
            foreach (string c in contexts) p.add ("context[]", c);
            p.add ("filter_action", hide ? "hide" : "warn");
            p.add ("expires_in", expires_in > 0 ? expires_in.to_string () : "");
            int n = 0;
            foreach (var k in keywords) {
                if (k.id == "" && (k.destroy || k.keyword.strip () == "")) continue;
                string at = "keywords_attributes[%d]".printf (n++);
                if (k.id != "") p.add (at + "[id]", k.id);
                if (k.destroy) {
                    p.add (at + "[_destroy]", "true");
                    continue;
                }
                p.add (at + "[keyword]", k.keyword.strip ());
                p.add (at + "[whole_word]", k.whole_word ? "true" : "false");
            }
            return p;
        }

        public string translate_path (string status_id) {
            return "/api/v1/statuses/%s/translate".printf (Uri.escape_string (status_id, null, false));
        }

        public string language_code (string? locale) {
            if (locale == null || locale == "" || locale == "C" || locale == "POSIX" || locale.has_prefix ("C.")) return "en";
            string l = locale.split (".")[0].split ("@")[0];
            string[] parts = l.split ("_");
            string lang = parts[0].down ();
            if (lang == "zh" && parts.length > 1) return parts[1].up () == "TW" || parts[1].up () == "HK" ? "zh-TW" : "zh";
            if (lang == "pt" && parts.length > 1 && parts[1].up () == "BR") return "pt-BR";
            return lang;
        }

        public string user_language () {
            foreach (string name in Intl.get_language_names ()) {
                if (name == "C" || name.has_prefix ("C.")) continue;
                return language_code (name);
            }
            return "en";
        }

        public string language_name (string code) {
            string[] table = {
                "ar", _("Arabic"), "ca", _("Catalan"), "cs", _("Czech"), "da", _("Danish"), "de", _("German"),
                "el", _("Greek"), "en", _("English"), "eo", _("Esperanto"), "es", _("Spanish"), "eu", _("Basque"),
                "fa", _("Persian"), "fi", _("Finnish"), "fr", _("French"), "ga", _("Irish"), "gl", _("Galician"),
                "he", _("Hebrew"), "hi", _("Hindi"), "hu", _("Hungarian"), "id", _("Indonesian"), "it", _("Italian"),
                "ja", _("Japanese"), "ko", _("Korean"), "nl", _("Dutch"), "no", _("Norwegian"), "pl", _("Polish"),
                "pt", _("Portuguese"), "ro", _("Romanian"), "ru", _("Russian"), "sv", _("Swedish"), "th", _("Thai"),
                "tr", _("Turkish"), "uk", _("Ukrainian"), "vi", _("Vietnamese"), "zh", _("Chinese")
            };
            string base_code = code.down ().split ("-")[0].split ("_")[0];
            for (int i = 0; i + 1 < table.length; i += 2) if (table[i] == base_code) return table[i + 1];
            return code;
        }

        public bool same_language (string a, string b) {
            if (a == "" || b == "") return false;
            return a.down ().split ("-")[0] == b.down ().split ("-")[0];
        }
    }
}
