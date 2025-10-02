{ lib, pkgs, config, ... }:
let
  common    = import ../../../mail/parts/common.nix { inherit lib; };
  accounts  = config.hwc.home.mail.accounts or {};
  accVals   = lib.attrValues accounts;
  themePart = import ./theme.nix { inherit lib config; };
  notmuchSource = "notmuch://${config.home.homeDirectory}/Maildir";
  maildirBase   = "maildir://${config.home.homeDirectory}/Maildir";
  
  sentFolder    = a: let r = common.rolesFor a; in lib.head (r.sent);
  draftsFolder  = a: let r = common.rolesFor a; in lib.head (r.drafts);
  accountRoot   = a: common.md a;
  

  accountBlock = a: ''
    [${a.name}]
    from                 = ${a.realName or ""} <${a.address}>
    source               = ${maildirBase}/${accountRoot a}
    outgoing             = exec:msmtp -a ${a.send.msmtpAccount}
    postpone             = ${maildirBase}/${draftsFolder a}
    copy-to              = ${maildirBase}/${sentFolder a}
  '';
    
  accountsConf = lib.concatStringsSep "\n\n" (map accountBlock accVals);
  
  stylesetConf = let
    tokens = themePart.tokens;
    viewerTokens = themePart.viewerTokens;
    renderStyle = name: style:
      "${name}.fg = ${style.fg}\n${name}.bg = ${style.bg}\n${name}.bold = ${if style.bold then "true" else "false"}";
    mainStyleLines = lib.mapAttrsToList renderStyle tokens;
    mainSection = lib.concatStringsSep "\n" mainStyleLines;
    viewerStyleLines = lib.mapAttrsToList renderStyle viewerTokens;
    viewerSection = "[viewer]\n" + (lib.concatStringsSep "\n" viewerStyleLines);
  in mainSection + "\n\n" + viewerSection;
  
 aercConf = ''
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
    [compose]
    editor=${pkgs.kitty}/bin/kitty -e ${pkgs.neovim}/bin/nvim
    [viewer]
    # Non-interactive filter output is paged here
    pager = ${pkgs.less}/bin/less -R
    # Prefer plain, then HTML in multipart/alternative
    alternatives = text/plain,text/html
    
    [filters]
    # HTML (interactive; uses aerc's html helper: w3m + socks sandbox)
    # Requires: w3m and either dante (socksify) or util-linux (unshare)
    text/html = ! html
    
    # Plain text (wrap + colorize like mailcap’s copiousoutput)
    text/plain = wrap -w 100 | colorize
    text/*     = cat -
    
    # Calendar / invites (aerc has a built-in calendar filter)
    text/calendar = calendar
    application/ics = calendar
    
    # Images in TTY (fallback renderer). Use :open for GUI viewer.
    image/* = ${pkgs.chafa}/bin/chafa -f symbols -s $(tput cols)x0 -
    
    # PDF to text (inline)
    application/pdf = ${pkgs.poppler_utils}/bin/pdftotext -layout - -
    
    # Code-ish/texty things (pretty-print; fall back to cat on error)
    application/json = ${pkgs.jq}/bin/jq -C . 2>/dev/null || cat -
    application/xml  = ${pkgs.libxml2}/bin/xmllint --format - 2>/dev/null || cat -
    text/xml         = ${pkgs.libxml2}/bin/xmllint --format - 2>/dev/null || cat -
    
    # Raw .eml/rfc822 bodies
    message/rfc822 = cat -

    # Email delivery/status messages
    message/delivery-status = cat -
    message/disposition-notification = cat -

    # CSV files
    text/csv = cat -

    # Rich Text Format
    application/rtf = ${pkgs.pandoc}/bin/pandoc -f rtf -t plain - 2>/dev/null || cat -
    text/rtf = ${pkgs.pandoc}/bin/pandoc -f rtf -t plain - 2>/dev/null || cat -

    # Markdown
    text/markdown = ${pkgs.glow}/bin/glow - 2>/dev/null || cat -

    # PGP/MIME (aerc handles internally, but explicit for logging)
    application/pgp-signature = cat -
    application/pgp-encrypted = cat -
    application/pkcs7-signature = cat -
    application/pkcs7-mime = cat -

    [openers]
    # HTML / PDF / images: open in system handlers (GUI)
    text/html = xdg-open {}
    application/pdf = xdg-open {}
    image/* = xdg-open {}
    
    # Audio / Video
    video/* = setsid -f ${pkgs.mpv}/bin/mpv --quiet {}
    audio/* = setsid -f ${pkgs.mpv}/bin/mpv --quiet {}
    
    # Microsoft Office (legacy + OOXML)
    application/msword = xdg-open {}
    application/vnd.ms-excel = xdg-open {}
    application/vnd.ms-powerpoint = xdg-open {}
    application/vnd.openxmlformats-officedocument.wordprocessingml.document = xdg-open {}
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet = xdg-open {}
    application/vnd.openxmlformats-officedocument.presentationml.presentation = xdg-open {}
    
    # LibreOffice / OpenDocument
    application/vnd.oasis.opendocument.text = xdg-open {}
    application/vnd.oasis.opendocument.spreadsheet = xdg-open {}
    application/vnd.oasis.opendocument.presentation = xdg-open {}
    
    # Archives: list contents in a pager on :open
    application/zip   = ${pkgs.unzip}/bin/unzip -l {} | ${pkgs.less}/bin/less -R
    application/x-tar = ${pkgs.gnutar}/bin/tar -tf {} | ${pkgs.less}/bin/less -R
    application/gzip  = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R
    application/x-gzip = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R
    application/x-bzip2 = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R
    application/x-xz    = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R
    application/x-7z-compressed = ${pkgs.p7zip}/bin/7z l {} | ${pkgs.less}/bin/less -R
    application/x-rar-compressed = ${pkgs.unrar}/bin/unrar l {} | ${pkgs.less}/bin/less -R

    # Apple iWork
    application/vnd.apple.pages = xdg-open {}
    application/vnd.apple.numbers = xdg-open {}
    application/vnd.apple.keynote = xdg-open {}

    # Rich Text Format
    application/rtf = xdg-open {}
    text/rtf = xdg-open {}

    # CSV
    text/csv = xdg-open {}

    # Generic binaries / catch-alls
    application/octet-stream = xdg-open {}
    application/* = ${pkgs.file}/bin/file {} | ${pkgs.less}/bin/less -R
  '';
in
{
  files = profileBase:{ 
      ".config/aerc/aerc.conf".text = aercConf;
      ".config/aerc/accounts.conf.source".text = accountsConf;
      ".config/aerc/stylesets/hwc-theme".text = stylesetConf;
    };
  packages = with pkgs; [
    aerc msmtp isync notmuch urlscan abook ripgrep dante chafa poppler_utils
    jq libxml2 mpv unzip gnutar file xdg-utils w3m pandoc glow p7zip unrar
  ];
}
