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
      # Colors (safe fallbacks if theme adapter lacks a key)
      color status        ${(get "status").fg}     ${(get "status").bg}
      color indicator     ${(get "indicator").fg}  ${(get "indicator").bg}
      color tree          ${(get "tree").fg}       ${(get "tree").bg}
      color markers       ${(get "markers").fg}    ${(get "markers").bg}
      color search        ${(get "search").fg}     ${(get "search").bg}
      color normal        ${(get "normal").fg}     ${(get "normal").bg}
      color quoted        ${(get "quoted").fg}     ${(get "quoted").bg}
      color signature     ${(get "signature").fg}  ${(get "signature").bg}
      color hdrdefault    ${(get "hdrdefault").fg} ${(get "hdrdefault").bg}

      # Index accents (fall back gracefully)
      color index         ${(get "indexNew").fg}   ${(get "indexNew").bg} "~N"
      color index         ${(get "indexFlag").fg}  ${(get "indexFlag").bg} "~F"
      color index         ${(get "indexDel").fg}   ${(get "indexDel").bg} "~D"
      color index         ${(get "indexToMe").fg}  ${(get "indexToMe").bg} "~p"
      color index         ${(get "indexFromMe").fg} ${(get "indexFromMe").bg} "~P"

      # Compact index line
      set index_format = "%Z %{%b %d} %-20.20F (%3cK) %s"
      set size_show_bytes = no
    '';

    # ===================== sidebar =====================
    ".config/neomutt/sidebar.muttrc".text = ''
      set sidebar_visible     = yes
      set sidebar_width       = 28
      set sidebar_short_path  = yes
      set sidebar_folder_indent = yes
      set mail_check_stats    = yes
      # %B name, %N new, %S size, %! flagged
      set sidebar_format      = "%B %?N?[%N]??"
      # Navigation bindings (vim-like)
      bind index,pager \Cj sidebar-next
      bind index,pager \Ck sidebar-prev
      bind index,pager \Co sidebar-open
      bind index,pager \Cn sidebar-next-new
      bind index,pager \Cp sidebar-prev-new
    '';

  };
}
