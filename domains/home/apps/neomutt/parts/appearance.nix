# domains/home/apps/neomutt/parts/appearance.nix (drop-in)
{ lib, pkgs, config, theme, osConfig ? {}, ... }:

let
  # Accounts (now under hwc.home.mail.accounts)
  accVals   = lib.attrValues (config.hwc.home.mail.accounts or {});
  haveAccs  = accVals != [];

  # Theme tokens (t may be partial; m is optional mono attributes)
  t   = theme.tokens or {};
  m   = theme.mono   or {};
  get = name: (t.${name} or {});   # returns an attrset; colorLine defaults fg/bg

  # Safe color line builder; pattern is single-quoted when present
  colorLine = kind: spec: pattern:
    let
      fg  = spec.fg or "default";
      bg  = spec.bg or "default";
      pat = if pattern == null || pattern == "" then "" else " '" + pattern + "'";
    in "color ${kind} ${fg} ${bg}${pat}";

  # Primary account (prefer explicit primary; else first; else null)
  primary =
    let p = lib.filter (a: a.primary or false) accVals;
    in if p != [] then lib.head p else (if haveAccs then lib.head accVals else null);
in
{
  files = profileBase: {
    # -------------------- MAIN CONFIG (neomuttrc) --------------------
    ".config/neomutt/neomuttrc".text = ''
      ############################################
      # CORE: Storage / Mailboxes
      ############################################
      set mbox_type = Maildir
      set folder    = "~/400_mail/Maildir"
      ${lib.optionalString (primary != null) ''
        set spoolfile = "=${(primary.maildirName or (primary.name or "inbox"))}/INBOX"
      ''}

      # Discover all local Maildirs for sidebar (quote paths safely)
      mailboxes `find ~/400_mail/Maildir -type d -name cur -printf '"%h" ' | sort -u`

      # Human labels for each account's INBOX in the sidebar
      ${lib.concatStringsSep "\n" (map (a:
        let
          n = a.maildirName or (a.name or "inbox");
          d = a.sidebarLabel or a.label or a.name or n;
        in ''named-mailboxes "${d}" "=${n}/INBOX"'') accVals)}

      ############################################
      # UX: Caches / Pager / Threaded workflow
      ############################################
      set header_cache      = "~/.cache/neomuttrc/headers"
      set message_cachedir  = "~/.cache/neomuttrc/bodies"

      # Thread-first workflow
      set sort              = reverse-threads
      set sort_aux          = last-date-received
      set sort_re
      set uncollapse_jump

      # Pager
      set pager_context     = 3
      set pager_index_lines = 8
      set pager_stop
      set tilde

      ############################################
      # SIDEBAR: layout (colors come from theme.muttrc)
      ############################################
      set sidebar_visible     = yes
      set sidebar_width       = 26
      set sidebar_short_path  = yes
      set mail_check_stats    = yes
      # %B name, %N new, %S unread, %! flagged
      set sidebar_format      = "%D %N/%S%!"

      ############################################
      # LOOK & UI: color theme includes sidebar colors
      ############################################
      source "~/.config/neomutt/theme.muttrc"

      ############################################
      # INPUT: keybinds & macros
      ############################################
      source "~/.config/neomutt/behavior.muttrc"

      ############################################
      # SENDING: via msmtp (no smtp_url in mutt)
      ############################################
      unset smtp_url
      set   sendmail = "/run/current-system/sw/bin/msmtp"
      set   use_envelope_from = yes

      ############################################
      # CONTACTS / HTML / MAILCAP
      ############################################
      set query_command = "abook --mutt-query '%s'"
      auto_view text/html text/calendar application/pdf
      set implicit_autoview = yes
      set mime_forward = yes
      set mime_forward_decode = yes
      set mailcap_path = "~/.mailcap"
      alternative_order text/plain text/enriched text/html
      bind editor <Tab> complete-query

      # Enhanced attachment handling
      set attach_format = "%u%D%I %t%4n %T%.40d%> [%.7m/%.10M, %.6e%?C?, %C?, %s] "
      set attach_split  = yes
    '';

    # -------------------- THEME (safe defaults if tokens missing) --------------------
    ".config/neomutt/theme.muttrc".text = ''
      # ===== Index defaults =====
      ${colorLine "index"        (get "index_default")   ".*"}
      ${colorLine "index_author" (get "index_author")    ".*"}
      ${colorLine "index_number" (get "index_number")    ""}
      ${colorLine "index_subject"(get "index_subject")   ".*"}

      # ===== New mail (~N) =====
      ${colorLine "index"        (get "index_new_default")  "~N"}
      ${colorLine "index_author" (get "index_new_author")   "~N"}
      ${colorLine "index_subject"(get "index_new_subject")  "~N"}

      # ===== Headers (pager) =====
      ${colorLine "header" (get "hdr_default")  ".*"}
      ${colorLine "header" (get "hdr_from")     "^(From)"}
      ${colorLine "header" (get "hdr_subject")  "^(Subject)"}
      ${colorLine "header" (get "hdr_ccbcc")    "^(CC|BCC)"}

      # ===== Mono / attributes =====
      mono bold       ${m.bold      or "bold"}
      mono underline  ${m.underline or "underline"}
      mono indicator  ${m.indicator or "reverse"}
      mono error      ${m.error     or "bold"}

      # ===== Core UI =====
      ${colorLine "normal"            (get "normal")            ""}
      ${colorLine "indicator"         (get "indicator")         ""}
      ${colorLine "sidebar_ordinary"  (get "sidebar_ordinary")  ""}
      ${colorLine "sidebar_highlight" (get "sidebar_highlight") ""}
      ${colorLine "sidebar_divider"   (get "sidebar_divider")   ""}
      ${colorLine "sidebar_flagged"   (get "sidebar_flagged")   ""}
      ${colorLine "sidebar_new"       (get "sidebar_new")       ""}
      ${colorLine "error"             (get "error")             ""}
      ${colorLine "tilde"             (get "tilde")             ""}
      ${colorLine "message"           (get "message")           ""}
      ${colorLine "markers"           (get "markers")           ""}
      ${colorLine "attachment"        (get "attachment")        ""}
      ${colorLine "search"            (get "search")            ""}
      ${colorLine "status"            (get "status")            ""}
      ${colorLine "hdrdefault"        (get "hdrdefault")        ""}

      # ===== Quoting levels =====
      ${colorLine "quoted"  (get "quoted0") ""}
      ${colorLine "quoted1" (get "quoted1") ""}
      ${colorLine "quoted2" (get "quoted2") ""}
      ${colorLine "quoted3" (get "quoted3") ""}
      ${colorLine "quoted4" (get "quoted4") ""}
      ${colorLine "quoted5" (get "quoted5") ""}

      ${colorLine "signature" (get "signature") ""}
      ${colorLine "bold"      (get "boldTok")   ""}
      ${colorLine "underline" (get "underlineTok") ""}

      # ===== Body regex highlights =====
      ${colorLine "body" (get "body_email")     "[\\-\\.+_a-zA-Z0-9]+@[\\-\\.a-zA-Z0-9]+"}
      ${colorLine "body" (get "body_url")       "(https?|ftp)://[\\-\\.,/%~_:?&=\\#a-zA-Z0-9]+"}
      ${colorLine "body" (get "body_code")      "\\`[^\\`]*\\`"}

      ${colorLine "body" (get "body_h1")        "^# \\.*"}
      ${colorLine "body" (get "body_h2")        "^## \\.*"}
      ${colorLine "body" (get "body_h3")        "^### \\.*"}
      ${colorLine "body" (get "body_listitem")  "^(\\t| )*(-|\\*) \\.*"}

      ${colorLine "body" (get "body_emote")     "[;:][-o][)/(|]"}
      ${colorLine "body" (get "body_emote")     "[;:][)(|]"}
      ${colorLine "body" (get "body_emote")     "[ ][*][^*]*[*][ ]?"}
      ${colorLine "body" (get "body_emote")     "[ ]?[*][^*]*[*][ ]"}

      ${colorLine "body" (get "body_sig_bad")   "(BAD signature)"}
      ${colorLine "body" (get "body_sig_good")  "(Good signature)"}
      ${colorLine "body" (get "body_gpg_goodln") "^gpg: Good signature .*"}
      ${colorLine "body" (get "body_gpg_anyln")  "^gpg: "}
      ${colorLine "body" (get "body_gpg_badln")  "^gpg: BAD signature from.*"}

      # ===== Optional per-column colors =====
      ${colorLine "index_number"  (get "col_number")  ""}
      ${colorLine "index_flags"   (get "col_flags")   ""}
      ${colorLine "index_date"    (get "col_date")    ""}
      ${colorLine "index_author"  (get "col_author")  ""}
      ${colorLine "index_size"    (get "col_size")    ""}
      ${colorLine "index_subject" (get "col_subject") ""}

      # ===== Index / status formatting =====
      set index_format="%Z %{%b %d} %-20.20F (%3cK) %s"
      set size_show_bytes=no
    '';

    # -------------------- SIMPLE WORKING MAILCAP --------------------
    ".mailcap".text = ''
      # Enhanced NeoMutt Mailcap Configuration for Modern NixOS

      # HTML Content
      text/html; lynx -assume_charset=%{charset} -display_charset=utf-8 -dump -width=1024 %s; nametemplate=%s.html; copiousoutput
      text/html; xdg-open %s; test=test -n "$DISPLAY"; nametemplate=%s.html
      text/html; w3m -I %{charset} -T text/html -cols 140 -o display_link_number=1 -dump %s; copiousoutput; nametemplate=%s.html

      # Plain Text
      text/plain; cat %s; copiousoutput
      text/plain; $EDITOR %s; edit
      text/*; cat %s; copiousoutput

      # Calendar and Meeting Invites
      text/calendar; cat %s; copiousoutput
      application/ics; cat %s; copiousoutput

      # Images
      image/*; icat.sh '%s'; test=test "$TERM" = "xterm-kitty"; needsterminal
      image/*; xdg-open %s; test=test -n "$DISPLAY"
      image/*; file %s; copiousoutput

      # Audio and Video
      video/*; setsid mpv --quiet %s &; test=test -n "$DISPLAY"
      video/*; file %s; copiousoutput
      audio/*; setsid mpv --quiet %s &; test=test -n "$DISPLAY"
      audio/*; file %s; copiousoutput

      # PDF Documents
      application/pdf; xdg-open %s; test=test -n "$DISPLAY"; nametemplate=%s.pdf
      application/pdf; pdftotext -layout %s -; copiousoutput

      # Microsoft Office Documents (Legacy)
      application/msword; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.ms-excel; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.ms-powerpoint; xdg-open %s; test=test -n "$DISPLAY"
      application/msword; pandoc --from docx --to markdown %s; copiousoutput

      # Microsoft Office Documents (Modern OpenXML)
      application/vnd.openxmlformats-officedocument.wordprocessingml.document; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.openxmlformats-officedocument.presentationml.presentation; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.openxmlformats-officedocument.wordprocessingml.document; pandoc --from docx --to markdown %s; copiousoutput

      # LibreOffice/OpenDocument Formats
      application/vnd.oasis.opendocument.text; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.oasis.opendocument.spreadsheet; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.oasis.opendocument.presentation; xdg-open %s; test=test -n "$DISPLAY"
      application/vnd.oasis.opendocument.text; pandoc --from odt --to markdown %s; copiousoutput

      # Archives and Compressed Files
      application/zip; unzip -l %s; copiousoutput
      application/x-tar; tar -tf %s; copiousoutput
      application/x-gzip; file %s; copiousoutput
      application/gzip; file %s; copiousoutput
      application/x-bzip2; file %s; copiousoutput
      application/x-xz; file %s; copiousoutput

      # Programming and Text Files
      text/x-shellscript; cat %s; copiousoutput
      text/x-python; cat %s; copiousoutput
      text/x-perl; cat %s; copiousoutput
      text/x-ruby; cat %s; copiousoutput
      text/x-php; cat %s; copiousoutput
      application/json; cat %s; copiousoutput
      application/xml; cat %s; copiousoutput
      text/xml; cat %s; copiousoutput

      # Subtitle Files
      application/x-subrip; $EDITOR %s

      # Email Messages
      message/rfc822; cat %s; copiousoutput

      # Generic Binary Files
      application/octet-stream; xdg-open %s; test=test -n "$DISPLAY"
      application/octet-stream; file %s; copiousoutput

      # Catch-all for unknown application types
      application/*; xdg-open %s; test=test -n "$DISPLAY"
      application/*; file %s; copiousoutput
    '';
  };
}