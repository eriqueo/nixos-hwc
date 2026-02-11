{ lib, pkgs, config, osConfig ? {}, ...}:
let
  common    = import ../../../mail/parts/common.nix { inherit lib; };
  accounts  = config.hwc.home.mail.accounts or {};
  accVals   = lib.attrValues accounts;
  themePart = import ./theme.nix { inherit lib config; };
  # Keep aerc in lockstep with the notmuch maildir root
  maildirBase =
    let nmRoot = config.hwc.home.mail.notmuch.maildirRoot or "";
        pathBase = config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail";
    in if nmRoot != "" then nmRoot else "${pathBase}/Maildir";

  # Query maps per account (minimal, no per-account prefixes)
  queriesUnified = ''
    inbox = tag:inbox AND NOT tag:trash
    unread = tag:unread AND NOT tag:trash
    sent = tag:sent
    drafts = tag:draft
    trash = tag:trash
    starred = tag:starred AND NOT tag:trash
    important = tag:important AND NOT tag:trash
  '';

  queriesWork = ''
    inbox = tag:hwc AND tag:inbox AND NOT tag:trash
    unread = tag:hwc AND tag:unread AND NOT tag:trash
    sent = tag:hwc AND tag:sent
    drafts = tag:hwc AND tag:draft
    trash = tag:hwc AND tag:trash
    starred = tag:hwc AND tag:starred AND NOT tag:trash
    important = tag:hwc AND tag:important AND NOT tag:trash
  '';

  queriesPersonal = ''
    inbox = tag:personal AND tag:inbox AND NOT tag:trash
    unread = tag:personal AND tag:unread AND NOT tag:trash
    sent = tag:personal AND tag:sent
    drafts = tag:personal AND tag:draft
    trash = tag:personal AND tag:trash
    starred = tag:personal AND tag:starred AND NOT tag:trash
    important = tag:personal AND tag:important AND NOT tag:trash
  '';

  # Unified notmuch account (first) - shows all mail across all accounts
  unifiedAccount = ''
    [unified]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    # Hide per-account Maildirs (dot-prefixed) and noisy server folders
    folders-exclude     = ~^\\.,[Gmail]/All Mail,spam,trash
    multi-file-strategy = act-one-delete-rest
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries-unified
    from                = Eric O'Keefe <eric@iheartwoodcraft.com>
    outgoing            = exec:msmtp -a iheartwoodcraft
    default             = inbox
  '';

  workAccount = ''
    [work]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    folders-exclude     = ~^\\.,[Gmail]/All Mail,spam,trash
    exclude-tags        = personal
    multi-file-strategy = act-one-delete-rest
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries-work
    from                = Eric O'Keefe <eric@iheartwoodcraft.com>
    outgoing            = exec:msmtp -a proton-hwc
    default             = inbox
  '';

  personalAccount = ''
    [personal]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    folders-exclude     = ~^\\.,[Gmail]/All Mail,spam,trash
    exclude-tags        = hwc
    multi-file-strategy = act-one-delete-rest
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries-personal
    from                = Eric O'Keefe <eriqueokeefe@gmail.com>
    outgoing            = exec:msmtp -a gmail-personal
    default             = inbox
  '';

  # Tag-based unified inbox: Only the unified notmuch account with virtual folders
  # Plus per-account tabs for work/personal
  accountsConf = lib.concatStringsSep "\n" [
    unifiedAccount
    workAccount
    personalAccount
  ];
  accountsFile = pkgs.writeText "aerc-accounts.conf" accountsConf;

  stylesetConf = let
    tokens = themePart.tokens;
    viewerTokens = themePart.viewerTokens;
    renderStyle = name: style:
      "${name}.fg = ${style.fg}\n${name}.bg = ${style.bg}\n${name}.bold = ${if style.bold then "true" else "false"}";

    # Separate tag-based styles from regular styles for proper ordering
    tagStyles = lib.filterAttrs (name: _: lib.hasPrefix "[messages].Tag:" name) tokens;
    regularStyles = lib.filterAttrs (name: _: !(lib.hasPrefix "[messages].Tag:" name)) tokens;

    # Render in order: regular styles first, then tag styles (for highest precedence)
    regularStyleLines = lib.mapAttrsToList renderStyle regularStyles;
    tagStyleLines = lib.mapAttrsToList renderStyle tagStyles;
    mainSection = lib.concatStringsSep "\n" (regularStyleLines ++ tagStyleLines);

    viewerStyleLines = lib.mapAttrsToList renderStyle viewerTokens;
    viewerSection = "[viewer]\n" + (lib.concatStringsSep "\n" viewerStyleLines);
  in mainSection + "\n\n" + viewerSection;

  aercConf = ''
    [general]
    enable-osc8 = true

    [ui]
    index-columns=date<20,name<17,flags>4,subject<*
    threading-enabled=true
    confirm-quit=false
    styleset-name=hwc-theme
    dirlist-tree=true
    dirlist-collapse=1
    dirlist-exclude = ^\..*
    column-date = {{.DateAutoFormat .Date.Local}}
    column-name = {{index (.From | names) 0}}
    column-flags = {{.Flags | join ""}}
    column-subject = {{.ThreadPrefix}}{{.Subject}}
    mouse-enabled = true

    [notmuch]
    # Include tags (%T) in the index format; adjust other fields to taste
    index-format=%D %-20.20F %Z %s %T


    [compose]
    editor=${pkgs.kitty}/bin/kitty -e ${pkgs.neovim}/bin/nvim

    [viewer]
    pager = ${pkgs.ov}/bin/ov -F --wrap --hscroll-width 10%
    alternatives = text/plain,text/html

    [filters]
    text/html = ! html
    text/plain = ${pkgs.aerc}/libexec/aerc/filters/wrap -w $(${pkgs.ncurses}/bin/tput cols) | ${pkgs.aerc}/libexec/aerc/filters/colorize
    text/* = cat -
    text/calendar = calendar
    application/ics = calendar
    image/* = ${pkgs.bash}/bin/bash -lc 'if [ -n "$KITTY_WINDOW_ID" ]; then ${pkgs.kitty}/bin/kitty +kitten icat --stdin yes; elif [ "$TERM_PROGRAM" = "WezTerm" ]; then ${pkgs.chafa}/bin/chafa -f sixel -s $(${pkgs.ncurses}/bin/tput cols)x0 -; else ${pkgs.chafa}/bin/chafa -f symbols -s $(${pkgs.ncurses}/bin/tput cols)x0 -; fi'
          
    application/pdf = ${pkgs.poppler-utils}/bin/pdftotext -layout - -
    application/json = ${pkgs.jq}/bin/jq -C . 2>/dev/null || cat -
    application/xml  = ${pkgs.libxml2}/bin/xmllint --format - 2>/dev/null || cat -
    text/xml         = ${pkgs.libxml2}/bin/xmllint --format - 2>/dev/null || cat -
    message/rfc822 = cat -
    message/delivery-status = cat -
    message/disposition-notification = cat -
    text/csv = cat -
    application/rtf = ${pkgs.pandoc}/bin/pandoc -f rtf -t plain - 2>/dev/null || cat -
    text/rtf = ${pkgs.pandoc}/bin/pandoc -f rtf -t plain - 2>/dev/null || cat -
    text/markdown = ${pkgs.glow}/bin/glow - 2>/dev/null || cat -
    application/pgp-signature = cat -
    application/pgp-encrypted = cat -
    application/pkcs7-signature = cat -
    application/pkcs7-mime = cat -

    [triggers]
    new-email = exec notify-send "New Email" "{{.From}} - {{.Subject}}"

    [openers]
    text/html = xdg-open {}
    application/pdf = xdg-open {}
    image/* = xdg-open {}
    video/* = setsid -f ${pkgs.mpv}/bin/mpv --quiet {}
    audio/* = setsid -f ${pkgs.mpv}/bin/mpv --quiet {}
    application/msword = xdg-open {}
    application/vnd.ms-excel = xdg-open {}
    application/vnd.ms-powerpoint = xdg-open {}
    application/vnd.openxmlformats-officedocument.wordprocessingml.document = xdg-open {}
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet = xdg-open {}
    application/vnd.openxmlformats-officedocument.presentationml.presentation = xdg-open {}
    application/vnd.oasis.opendocument.text = xdg-open {}
    application/vnd.oasis.opendocument.spreadsheet = xdg-open {}
    application/vnd.oasis.opendocument.presentation = xdg-open {}
    application/zip   = ${pkgs.unzip}/bin/unzip -l {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/x-tar = ${pkgs.gnutar}/bin/tar -tf {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/gzip  = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/x-gzip = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/x-bzip2 = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/x-xz    = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/x-7z-compressed = ${pkgs.p7zip}/bin/7z l {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/x-rar-compressed = ${pkgs.unrar}/bin/unrar l {} | ${pkgs.less}/bin/less -R --mouse -+S -X
    application/vnd.apple.pages = xdg-open {}
    application/vnd.apple.numbers = xdg-open {}
    application/vnd.apple.keynote = xdg-open {}
    application/rtf = xdg-open {}
    text/rtf = xdg-open {}
    text/csv = xdg-open {}
    application/octet-stream = xdg-open {}
    application/* = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R --mouse -+S -X
  '';
in
{
  files = profileBase:{
    ".config/aerc/aerc.conf".text = aercConf;
    ".config/aerc/stylesets/hwc-theme".text = stylesetConf;
    ".config/aerc/notmuch-queries-unified".text = queriesUnified;
    ".config/aerc/notmuch-queries-work".text = queriesWork;
    ".config/aerc/notmuch-queries-personal".text = queriesPersonal;
  };
  packages = with pkgs; [
    aerc msmtp isync notmuch urlscan abook ripgrep dante chafa poppler-utils
    jq libxml2 mpv unzip gnutar file xdg-utils w3m pandoc glow p7zip unrar
    util-linux ncurses ov xclip
  ];
  inherit accountsFile;
}
