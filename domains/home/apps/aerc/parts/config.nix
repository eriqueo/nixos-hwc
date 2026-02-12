{ lib, pkgs, config, osConfig ? {}, ...}:
let
  common    = import ../../../mail/parts/common.nix { inherit lib; };
  accounts  = config.hwc.home.mail.accounts or {};
  accVals   = lib.attrValues accounts;
  themePart = import ./theme.nix { inherit lib config; };
  maildirBase   = "${config.home.homeDirectory}/Maildir";

  # Per-account views using maildir-account-path
  # Each account shows only its own folders within the unified Maildir
  accountBlock = a: ''
    [${a.name}]
    source               = notmuch://${maildirBase}
    maildir-store        = ${maildirBase}
    maildir-account-path = ${a.maildirName}
    multi-file-strategy  = act-one-delete-rest
    from                 = ${a.realName or ""} <${a.address}>
    outgoing             = exec:msmtp -a ${a.send.msmtpAccount}
    ${if a.primary or false then "default = inbox" else ""}
  '';

  # Saved searches shown as folders under the notmuch unified account
  notmuchQueries = ''
    inbox  = tag:inbox AND NOT tag:trash AND NOT tag:spam
    unread = tag:unread AND NOT tag:trash AND NOT tag:spam
    all    = NOT tag:trash AND NOT tag:spam

    hwc    = tag:acc:hwc   AND NOT tag:trash AND NOT tag:spam
    gbiz   = tag:acc:gbiz  AND NOT tag:trash AND NOT tag:spam
    pers   = tag:acc:pers  AND NOT tag:trash AND NOT tag:spam
    gpers  = tag:acc:gpers AND NOT tag:trash AND NOT tag:spam
  '';

  # Unified notmuch account (first) - shows all mail across all accounts
  unifiedAccount = ''
    [unified]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    multi-file-strategy = act-one-delete-rest
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries
    from                = Eric O'Keefe <eric@iheartwoodcraft.com>
    outgoing            = exec:msmtp -a iheartwoodcraft
    default             = inbox
  '';

  # Make unified FIRST, then the IMAP accounts
  accountsConf = unifiedAccount + "\n\n" + lib.concatStringsSep "\n\n" (map accountBlock accVals);

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
    # accounts.conf contains NO secrets (passwords are in msmtp config)
    ".config/aerc/accounts.conf" = {
      text = accountsConf;
      mode = "0600";
    };
    ".config/aerc/stylesets/hwc-theme".text = stylesetConf;
    ".config/aerc/notmuch-queries".text = notmuchQueries;
  };
  packages = with pkgs; [
    aerc msmtp isync notmuch urlscan abook ripgrep dante chafa poppler-utils
    jq libxml2 mpv unzip gnutar file xdg-utils w3m pandoc glow p7zip unrar
    util-linux ncurses ov xclip
  ];
}
