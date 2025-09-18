# NeoMutt • Appearance (offline-first, HM-compliant)
{ lib, pkgs, config, ... }:

let
  cfg = config.features.neomutt or { };

  # Theme adapter (fallbacks to 'default' if any color missing)
  themeColorsRaw =
    import ../../../theme/adapters/neomutt.nix { inherit config lib; };
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
      set sort             = reverse-date
      set menu_scroll      = yes
      set pager_context    = 3
      set pager_index_lines= 8

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
    ".config/neomutt/theme.muttrc".text = ''
      # Colors from theme adapter
      color status        ${(get "status").fg}        ${(get "status").bg}
      color indicator     ${(get "indicator").fg}     ${(get "indicator").bg}
      color tree          ${(get "tree").fg}          ${(get "tree").bg}
      color markers       ${(get "markers").fg}       ${(get "markers").bg}
      color search        ${(get "search").fg}        ${(get "search").bg}
      color normal        ${(get "normal").fg}        ${(get "normal").bg}
      color quoted        ${(get "quoted").fg}        ${(get "quoted").bg}
      color signature     ${(get "signature").fg}     ${(get "signature").bg}
      color hdrdefault    ${(get "hdrdefault").fg}    ${(get "hdrdefault").bg}
      color tilde         ${(get "tilde").fg}         ${(get "tilde").bg}
    
      # Accents (matchers)
      color index         ${(get "indexNew").fg}      ${(get "indexNew").bg} "~N"
      color index         ${(get "indexFlag").fg}     ${(get "indexFlag").bg} "~F"
      color index         ${(get "indexDel").fg}      ${(get "indexDel").bg} "~D"
      color index         ${(get "indexToMe").fg}     ${(get "indexToMe").bg} "~p"
      color index         ${(get "indexFromMe").fg}   ${(get "indexFromMe").bg} "~P"
    
      # Per-column colors (NeoMutt feature)
      color index_number  ${(get "index_number").fg}  ${(get "index_number").bg}
      color index_flags   ${(get "index_flags").fg}   ${(get "index_flags").bg}
      color index_date    ${(get "index_date").fg}    ${(get "index_date").bg}
      color index_author  ${(get "index_author").fg}  ${(get "index_author").bg}
      color index_size    ${(get "index_size").fg}    ${(get "index_size").bg}
      color index_subject ${(get "index_subject").fg} ${(get "index_subject").bg}
    
      # Compact index line that lines up with the columns above
      set index_format = "%4C %Z %{%b %d} %-20.20F %?l?%4l&%4c? %s"
      set size_show_bytes = no
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
