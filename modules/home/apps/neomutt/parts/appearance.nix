# modules/home/apps/neomutt/parts/appearance.nix
# Renders theme + sidebar + main muttrc (offline-first)
{ lib, pkgs, config, theme, ... }:

let
    accVals = lib.attrValues (config.features.mail.accounts or {});


  t    = theme.tokens;
  m    = theme.mono or {};
  get  = name: t.${name};
  line = nm: c: "color ${nm} ${c.fg} ${c.bg}";

  # First account (for default spoolfile)
  accVals  = lib.attrValues (cfg.accounts or {});
  firstAcc = lib.findFirst (a: a.primary or false) (lib.head accVals) accVals;

in {
  files = profileBase: {
    # ----------- main config -----------
    ".config/neomutt/neomuttrc".text = ''
      # Storage (offline-first Maildir)
      set mbox_type = Maildir
      set folder    = "~/Maildir"
      ${lib.optionalString (firstAcc != null) ''
        set spoolfile = "=${firstAcc.maildirName or (firstAcc.name or "inbox")}/INBOX"
      ''}

      # Caches & UX / thread-first workflow
      set header_cache      = "~/.cache/neomutt/headers"
      set message_cachedir  = "~/.cache/neomutt/bodies"
      set sort              = reverse-threads
      set sort_aux          = last-date-received
      set sort_re
      set uncollapse_jump

      set pager_context     = 3
      set pager_index_lines = 8
      set pager_stop
      set tilde

      # Discover all local Maildirs for sidebar
      mailboxes `find ~/Maildir -type d -name cur -printf "%h\n" | sed -e 's/ /\\ /g' | sort -u | tr '\n' ' '`

      # Look & UI
      source "~/.config/neomutt/theme.muttrc"
      source "~/.config/neomutt/sidebar.muttrc"
      source "~/.config/neomutt/behavior.muttrc"

      # Sending via msmtp (never smtp_url here)
      unset smtp_url
      set   sendmail = "/run/current-system/sw/bin/msmtp"
      set   use_envelope_from = yes

      # Contacts + HTML
      set query_command = "abook --mutt-query '%s'"
      auto_view text/html
      bind editor <Tab> complete-query
      set mailcap_path = "~/.mailcap"
      alternative_order text/plain text/enriched text/html
    '';

    # ----------- theme only (colors) -----------
    ".config/neomutt/theme.muttrc".text = ''
      # Index defaults
      ${line "index"        (get "index_default")} '.*'
      ${line "index_author" (get "index_author")} '.*'
      ${line "index_number" (get "index_number")}
      ${line "index_subject"(get "index_subject")} '.*'

      # New mail (~N)
      ${line "index"        (get "index_new_default")} "~N"
      ${line "index_author" (get "index_new_author")} "~N"
      ${line "index_subject"(get "index_new_subject")} "~N"

      # Headers
      ${line "header" (get "hdr_default")} ".*"
      ${line "header" (get "hdr_from")}    "^(From)"
      ${line "header" (get "hdr_subject")} "^(Subject)"
      ${line "header" (get "hdr_ccbcc")}   "^(CC|BCC)"

      # Mono/attributes
      mono bold       ${m.bold}
      mono underline  ${m.underline}
      mono indicator  ${m.indicator}
      mono error      ${m.error}

      # Core UI
      ${line "normal"            (get "normal")}
      ${line "indicator"         (get "indicator")}
      ${line "sidebar_ordinary"  (get "sidebar_ordinary")}
      ${line "sidebar_highlight" (get "sidebar_highlight")}
      ${line "sidebar_divider"   (get "sidebar_divider")}
      ${line "sidebar_flagged"   (get "sidebar_flagged")}
      ${line "sidebar_new"       (get "sidebar_new")}
      ${line "error"             (get "error")}
      ${line "tilde"             (get "tilde")}
      ${line "message"           (get "message")}
      ${line "markers"           (get "markers")}
      ${line "attachment"        (get "attachment")}
      ${line "search"            (get "search")}
      ${line "status"            (get "status")}
      ${line "hdrdefault"        (get "hdrdefault")}

      # Quoting levels
      ${line "quoted"  (get "quoted0")}
      ${line "quoted1" (get "quoted1")}
      ${line "quoted2" (get "quoted2")}
      ${line "quoted3" (get "quoted3")}
      ${line "quoted4" (get "quoted4")}
      ${line "quoted5" (get "quoted5")}

      ${line "signature" (get "signature")}
      ${line "bold"      (get "boldTok")}
      ${line "underline" (get "underlineTok")}

      # Body regex highlights
      ${line "body" (get "body_email")}     "[\\-\\.+_a-zA-Z0-9]+@[\\-\\.a-zA-Z0-9]+"
      ${line "body" (get "body_url")}       "(https?|ftp)://[\\-\\.,/%~_:?&=\\#a-zA-Z0-9]+"
      ${line "body" (get "body_code")}      "\\`[^\\`]*\\`"

      ${line "body" (get "body_h1")}        "^# \\.*"
      ${line "body" (get "body_h2")}        "^## \\.*"
      ${line "body" (get "body_h3")}        "^### \\.*"
      ${line "body" (get "body_listitem")}  "^(\\t| )*(-|\\*) \\.*"

      ${line "body" (get "body_emote")}     "[;:][-o][)/(|]"
      ${line "body" (get "body_emote")}     "[;:][)(|]"
      ${line "body" (get "body_emote")}     "[ ][*][^*]*[*][ ]?"
      ${line "body" (get "body_emote")}     "[ ]?[*][^*]*[*][ ]"

      ${line "body" (get "body_sig_bad")}   "(BAD signature)"
      ${line "body" (get "body_sig_good")}  "(Good signature)"
      ${line "body" (get "body_gpg_goodln")} "^gpg: Good signature .*"
      ${line "body" (get "body_gpg_anyln")}  "^gpg: "
      ${line "body" (get "body_gpg_badln")}  "^gpg: BAD signature from.*"

      # Optional per-column colors
      color index_number  ${(get "col_number").fg}  ${(get "col_number").bg}
      color index_flags   ${(get "col_flags").fg}   ${(get "col_flags").bg}
      color index_date    ${(get "col_date").fg}    ${(get "col_date").bg}
      color index_author  ${(get "col_author").fg}  ${(get "col_author").bg}
      color index_size    ${(get "col_size").fg}    ${(get "col_size").bg}
      color index_subject ${(get "col_subject").fg} ${(get "col_subject").bg}

      # Index/status formatting
      set index_format="%Z %{%b %d} %-20.20F (%3cK) %s"
      set size_show_bytes=no
    '';

    # Sidebar layout/format (colors come from theme.muttrc above)
    ".config/neomutt/sidebar.muttrc".text = ''
      set sidebar_visible     = yes
      set sidebar_width       = 26
      set sidebar_short_path  = yes
      set mail_check_stats    = yes
      set sidebar_format      = "%B %N/%S%!"
    '';
  };
}
