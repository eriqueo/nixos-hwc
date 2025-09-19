# NeoMutt • Appearance (offline-first, HM-compliant)
{ lib, pkgs, config, ... }:

let
  cfg = config.features.neomutt or { };

 # Named palettes
    paletteMap = {
      deep-nord = ../../../theme/palettes/deep-nord.nix;
      gruv      = ../../../theme/palettes/gruv.nix;
    };
  
    # Load chosen palette (file or name), then apply overrides
    basePalette =
      if (cfg.theme or {}).useGlobal or false then
        (config.hwc.home.theme or {})                           # global fallback
      else if lib.isPath (cfg.theme.palette or null) then
        import cfg.theme.palette { inherit lib; }               # explicit file
      else
        import (paletteMap.${cfg.theme.palette}) { inherit lib; };  # named preset
  
    resolvedPalette =
      if (cfg.theme or {}).override or {} == {} then basePalette
      else { colors = (basePalette.colors or basePalette) // cfg.theme.override; };
      
 themeColorsRaw =
    import ../../../theme/adapters/neomutt.nix {
      inherit config lib;
      palette = resolvedPalette;   # <— key change
    };

  def = { fg = "default"; bg = "default"; };
  # safe get
  get = name: (themeColorsRaw.colors.${name} or def);

  # Helper: first account *value* (not just its name)
  accVals = lib.attrValues (cfg.accounts or { });
  firstAcc = lib.findFirst (a: a.primary or false) (lib.head accVals) accVals;
  
  # Folder-hooks: when you enter an account’s local Maildir, set identity
  accountHooks =
    lib.concatStringsSep "\n"
      (map (a:
        let
          maildir = a.maildirName or (a.name or "inbox");
          addr    = a.address;
          real    = a.realName or "User";
        in ''
          # Identity for ${maildir}
          folder-hook "=${maildir}/*" "set from=${addr}; set realname='${real}'; set use_envelope_from=yes"
        '') accVals);

in {
  files = profileBase: {
    # ===================== main config =====================
    ".config/neomutt/neomuttrc".text = ''
      # --- Storage (offline-first) ---
      set mbox_type = Maildir
      set folder    = "~/Maildir"
      ${lib.optionalString (firstAcc != null) ''
        set spoolfile = "=${firstAcc.maildirName or (firstAcc.name or "inbox")}/INBOX"
      ''}

      # --- Caches & UX ---
      set header_cache     = "~/.cache/neomutt/headers"
      set message_cachedir = "~/.cache/neomutt/bodies"
      set sort             = reverse-threads
      set sort_aux         = last-date-received
      set sort_re
      set uncollapse_jump
      
      set pager_context    = 3
      set pager_index_lines= 8
      set pager_stop
      set tilde
      

      # --- Auto-discover all local Maildirs for sidebar ---
      # Finds every Maildir folder by presence of 'cur', escapes spaces
      mailboxes `find ~/Maildir -type d -name cur -printf "%h\n" | sed -e 's/ /\\ /g' | sort -u | tr '\n' ' '`

      # --- Look & UI ---
      source "~/.config/neomutt/theme.muttrc"
      source "~/.config/neomutt/sidebar.muttrc"
      source "~/.config/neomutt/behavior.muttrc"

      # --- Sending: always via msmtp (system path), never smtp_url here ---
      unset smtp_url
      set   sendmail = "/run/current-system/sw/bin/msmtp"
      set   use_envelope_from = yes

      # --- abook integration + HTML handling ---
      set query_command = "abook --mutt-query '%s'"
      auto_view text/html
      bind editor <Tab> complete-query
      set mailcap_path = "~/.mailcap"
      alternative_order text/plain text/enriched text/html

      # --- Per-account identity when entering that Maildir ---
      ${accountHooks}
    '';

    # ===================== theme =====================
    # ===== Index defaults =====
    ".config/neomutt/theme.muttrc".text = ''
          ${line "index"        (get "index_default")} '.*'
          ${line "index_author" (get "index_author")} '.*'
          ${line "index_number" (get "index_number")}
          ${line "index_subject"(get "index_subject")} '.*'
    
          # New mail (~N)
          ${line "index"        (get "index_new_default")} "~N"
          ${line "index_author" (get "index_new_author")} "~N"
          ${line "index_subject"(get "index_new_subject")} "~N"
    
          # ===== Headers (pager) =====
          ${line "header" (get "hdr_default")} ".*"
          ${line "header" (get "hdr_from")}    "^(From)"
          ${line "header" (get "hdr_subject")} "^(Subject)"
          ${line "header" (get "hdr_ccbcc")}   "^(CC|BCC)"
    
          # ===== Mono / attributes =====
          mono bold       ${m.bold}
          mono underline  ${m.underline}
          mono indicator  ${m.indicator}
          mono error      ${m.error}
    
          # ===== Core UI =====
          ${line "normal"          (get "normal")}
          ${line "indicator"       (get "indicator")}
          ${line "sidebar_highlight" (get "sidebar_highlight")}
          ${line "sidebar_divider"   (get "sidebar_divider")}
          ${line "sidebar_flagged"   (get "sidebar_flagged")}
          ${line "sidebar_new"       (get "sidebar_new")}
          ${line "error"           (get "error")}
          ${line "tilde"           (get "tilde")}
          ${line "message"         (get "message")}
          ${line "markers"         (get "markers")}
          ${line "attachment"      (get "attachment")}
          ${line "search"          (get "search")}
          ${line "status"          (get "status")}
          ${line "hdrdefault"      (get "hdrdefault")}
    
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
    
          # ===== Body regex highlights =====
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
    
          # ===== Optional per-column colors (if used) =====
          color index_number  ${(get "col_number").fg}  ${(get "col_number").bg}
          color index_flags   ${(get "col_flags").fg}   ${(get "col_flags").bg}
          color index_date    ${(get "col_date").fg}    ${(get "col_date").bg}
          color index_author  ${(get "col_author").fg}  ${(get "col_author").bg}
          color index_size    ${(get "col_size").fg}    ${(get "col_size").bg}
          color index_subject ${(get "col_subject").fg} ${(get "col_subject").bg}
    
          # ===== Suggested index/status formatting =====
          set index_format="%Z %{%b %d} %-20.20F (%3cK) %s"
          set size_show_bytes=no
        '';
    
    

    # ===================== sidebar =====================
    ".config/neomutt/sidebar.muttrc".text = ''
      set sidebar_visible     = yes
      set sidebar_width       = 26
      set sidebar_short_path  = yes
      set mail_check_stats    = yes
    
      # Keep format simple (no unsupported %? ternaries)
      # %B name, %N new, %S size, %! flagged
      set sidebar_format = "%B %N/%S%!"
    
      # Sidebar colors from adapter
      color sidebar_ordinary  ${(get "sidebar_ordinary").fg}  ${(get "sidebar_ordinary").bg}
      color sidebar_highlight ${(get "sidebar_highlight").fg} ${(get "sidebar_highlight").bg}
      color sidebar_divider   ${(get "sidebar_divider").fg}   ${(get "sidebar_divider").bg}
      color sidebar_flagged   ${(get "sidebar_flagged").fg}   ${(get "sidebar_flagged").bg}
      color sidebar_new       ${(get "sidebar_new").fg}       ${(get "sidebar_new").bg}
    '';
    

  };
}
