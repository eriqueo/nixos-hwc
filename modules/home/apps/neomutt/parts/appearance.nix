# NeoMutt • Appearance (offline-first, HM-compliant)
{ lib, pkgs, config, ... }:

let
  cfg = config.features.neomutt or { };
  themeColors = import ../../../theme/adapters/neomutt.nix { inherit config lib; };

  # Folder-hooks per local account Maildir (proton, gmail-personal, gmail-business, …)
  accountHooks =
    lib.concatStringsSep "\n"
      (lib.mapAttrsToList (_name: account:
        let
          accName = account.name or (lib.replaceStrings ["@" "."] ["-" "-"] account.email);
          addr    = account.email;
          real    = account.realName or "User";
          # Maildir root: ~/Maildir/<accName> (matches your mbsync config)
          pat     = "^=\\Q${accName}\\E/";
        in ''
          # Identity for ${accName}
          folder-hook ${pat} "set from=${addr}; set realname='${real}'; set envelope_from_address=${addr}; my_hdr Return-Path: ${addr}"
        '') (cfg.accounts or { }));

in {
  files = profileBase: {

    # Main config: LOCAL Maildir only; no remote IMAP/SMTP here.
    ".config/neomutt/neomuttrc".text = ''
      set mbox_type=Maildir
      set folder="~/Maildir"                 # top-level for all accounts
      ${lib.optionalString (cfg.accounts or {} != {})
        (let first = lib.head (lib.attrNames cfg.accounts); in
          ''set spoolfile="=${first}/INBOX"'')
      }

      set header_cache="~/.cache/neomutt/headers"
      set message_cachedir="~/.cache/neomutt/bodies"
      set sort=reverse-date
      set menu_scroll=yes
      set pager_context=3
      set pager_index_lines=8

      # Auto-discover all Maildir boxes for sidebar (proton + gmail-*)
      mailboxes `find ~/Maildir -type d -name cur -printf "%h\n" | sed -e 's/ /\\ /g' | sort -u | tr '\n' ' '`

      # Source look & UI
      source "~/.config/neomutt/theme.muttrc"
      source "~/.config/neomutt/sidebar.muttrc"
      source "~/.config/neomutt/behavior.muttrc"

      # Use msmtp to send; ignore any smtp_url from other snippets
      unset smtp_url
      set sendmail="/run/current-system/sw/bin/msmtp"
      set use_envelope_from=yes

      # abook + inline HTML
      set query_command = "abook --mutt-query '%s'"
      auto_view text/html
      bind editor <Tab> complete-query
      set mailcap_path="~/.mailcap"
      alternative_order text/plain text/enriched text/html

      # Per-account identity when entering that Maildir
      ${accountHooks}
    '';

    # Theme (colors and compact index)
    ".config/neomutt/theme.muttrc".text = ''
      color status        ${themeColors.colors.status.fg}   ${themeColors.colors.status.bg}
      color indicator     ${themeColors.colors.indicator.fg} ${themeColors.colors.indicator.bg}
      color tree          ${themeColors.colors.tree.fg}     ${themeColors.colors.tree.bg}
      color markers       ${themeColors.colors.markers.fg}  ${themeColors.colors.markers.bg}
      color search        ${themeColors.colors.search.fg}   ${themeColors.colors.search.bg}
      color index         ${themeColors.colors.indexNew.fg} ${themeColors.colors.indexNew.bg} "~N"
      color index         ${themeColors.colors.indexFlag.fg} ${themeColors.colors.indexFlag.bg} "~F"
      color index         ${themeColors.colors.indexDel.fg} ${themeColors.colors.indexDel.bg} "~D"
      color index         ${themeColors.colors.indexToMe.fg} ${themeColors.colors.indexToMe.bg} "~p"
      color index         ${themeColors.colors.indexFromMe.fg} ${themeColors.colors.indexFromMe.bg} "~P"

      # Sidebar base colors (specials)
      color sidebar_ordinary default default
      color sidebar_highlight black yellow
      color sidebar_divider  blue  default
      color sidebar_flagged  magenta default
      color sidebar_new      yellow default

      # Compact index line
      set index_format="%Z %{%b %d} %-20.20F (%3cK) %s"
      set size_show_bytes=no
    '';

    # Sidebar only (UI + binds). No mailboxes or account jumps hardcoded.
    ".config/neomutt/sidebar.muttrc".text = ''
      set sidebar_visible=yes
      set sidebar_width=26
      set sidebar_short_path=yes
      set mail_check_stats=yes
      set sidebar_format="%B %?N?%N/?%S?"

    '';


  };
}
