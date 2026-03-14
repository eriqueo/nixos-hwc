{ lib, pkgs, config, osConfig ? {}, ... }:
let
  common    = import ../../../mail/parts/common.nix { inherit lib; };
  accounts  = config.hwc.home.mail.accounts or {};
  accVals   = lib.attrValues accounts;
  themePart = import ./theme.nix { inherit lib config; };

  maildirBase =
    let nmRoot = config.hwc.home.mail.notmuch.maildirRoot or "";
        pathBase = config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail";
    in if nmRoot != "" then nmRoot else "${pathBase}/Maildir";

  queriesUnified = ''
    inbox     = tag:inbox AND NOT tag:trash
    unread    = tag:unread AND NOT tag:trash
    sent      = tag:sent
    drafts    = tag:draft
    trash     = tag:trash
    starred   = tag:starred AND NOT tag:trash
    important = tag:important AND NOT tag:trash
    action    = tag:action AND NOT tag:trash
    finance   = tag:finance AND NOT tag:trash
    work      = tag:work AND NOT tag:trash
    coaching  = tag:coaching AND NOT tag:trash
    tech      = tag:tech AND NOT tag:trash
    bank      = tag:bank AND NOT tag:trash
    insurance = tag:insurance AND NOT tag:trash
    personal  = tag:gmail-personal AND NOT tag:trash
    hwcmt     = tag:hwcmt AND NOT tag:trash
    hide      = tag:hide
  '';

  mkLabelQueries = label: ''
    inbox   = tag:${label} AND NOT tag:trash
    unread  = tag:${label} AND tag:unread AND NOT tag:trash
    sent    = tag:${label} AND tag:sent
    drafts  = tag:${label} AND tag:draft
    trash   = tag:${label} AND tag:trash
    starred = tag:${label} AND tag:starred AND NOT tag:trash
    all     = tag:${label}
  '';

  mkLabelAccount = { name, from, outgoing }:
    let qmPath = "${config.home.homeDirectory}/.config/aerc/notmuch-queries-${name}";
    in ''
      [${name}]
      source              = notmuch://${maildirBase}
      maildir-store       = ${maildirBase}
      folders-exclude     = ~^\\..*,~^proton$,~^gmail-business$,~^gmail-personal$
      multi-file-strategy = act-one-delete-rest
      query-map           = ${qmPath}
      from                = ${from}
      outgoing            = exec:msmtp -a ${outgoing}
      default             = inbox
    '';

  unifiedAccount = ''
    [unified]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    folders-exclude     = ~^\\..*,~^proton$,~^gmail-business$,~^gmail-personal$
    multi-file-strategy = act-one-delete-rest
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries-unified
    from                = Eric <eric@iheartwoodcraft.com>
    outgoing            = exec:msmtp -a proton-hwc
    default             = inbox
  '';
  workLabelAccount    = mkLabelAccount { name = "work";     from = "Eric <eric@iheartwoodcraft.com>";  outgoing = "proton-hwc"; };
  financeAccount      = mkLabelAccount { name = "finance";  from = "Eric <eric@iheartwoodcraft.com>";  outgoing = "proton-hwc"; };
  coachingAccount     = mkLabelAccount { name = "coaching"; from = "Eric <eric@iheartwoodcraft.com>";  outgoing = "proton-hwc"; };
  personalLabelAcct   = mkLabelAccount { name = "personal"; from = "Eric <eriqueo@proton.me>";         outgoing = "proton-personal"; };

  accountsConf = lib.concatStringsSep "\n" [ unifiedAccount workLabelAccount financeAccount coachingAccount personalLabelAcct ];
  accountsFile = pkgs.writeText "aerc-accounts.conf" accountsConf;

  # ── Clean styleset generation (already correct) ───────────────────────────
  stylesetConf = themePart.stylesetContent;

  # ── Modern aerc.conf (0.21+ best practices) ───────────────────────────────
  aercConf = ''
    [general]
    enable-osc8 = true
    # address-book-cmd = ${pkgs.abook}/bin/abook --mutt-query "%s"   # uncomment if you want abook

    [ui]
    index-columns = tags<16,date<12,sender<17,flags>4,subject<*
    threading-enabled = true
    confirm-quit = false
    styleset-name = hwc-theme
    dirlist-tree = true
    dirlist-collapse = 1
    dirlist-exclude = ^\..*
    mouse-enabled = true
    fuzzy-complete = true
    tab-title-account = {{.Account}}{{if .Unread}} ({{.Unread}}){{end}}

    # ── Powerful live templates ───────────────────────────────────────────
    column-tags    = {{.StyleMap .Labels (exclude "inbox") (exclude "unread") (exclude "new") (exclude "sent") (exclude "draft") (exclude "trash") (exclude "spam") (exclude "archive") (exclude "flagged") (exclude "replied") (exclude "passed") (case "finance" "finance") (case "bank" "bank") (case "insurance" "insurance") (case "work" "work") (case "coaching" "coaching") (case "hwcmt" "hwcmt") (case "personal" "personal") (case "gmail-personal" "personal") (case "tech" "tech") (case "hide" "hide") (case "action" "action") (case "starred" "starred") (default "default") | join " " }}
    column-date    = {{.DateAutoFormat .Date.Local}}
    column-sender  = {{index (.From | names) 0}}
    column-flags   = {{.Flags | join ""}}
    column-subject = {{.ThreadPrefix}}{{if .ThreadFolded}}{{printf "{%d}" .ThreadCount}}{{end}}{{.Subject}}
    column-separator = " | "

    [statusline]
    status-columns = left<*,center:*,right>*
    column-left    = [{{.Account}}] {{.StatusInfo}}
    column-center  = {{.PendingKeys}}
    column-right   = {{.TrayInfo}}

    [viewer]
    pager = ${pkgs.ov}/bin/ov -F --wrap --hscroll-width 10%
    alternatives = text/plain,text/html

    [compose]
    editor = ${pkgs.kitty}/bin/kitty -e ${pkgs.neovim}/bin/nvim
    # format = {{.Signature}}   # add templates/new_message later

    [filters]
    text/html = ${pkgs.pandoc}/bin/pandoc -f html -t markdown --wrap=none 2>/dev/null | ${pkgs.glow}/bin/glow -
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

    [hooks]
    new-email      = exec notify-send "New Email" "{{.From}} - {{.Subject}}"
    tag-modified   = exec notify-send "Tag changed" "{{.Subject}} → {{.AddedTags}}"

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
  files = profileBase: {
    ".config/aerc/aerc.conf".text = aercConf;
    ".config/aerc/stylesets/hwc-theme".text = stylesetConf;
    ".config/aerc/notmuch-queries-unified".text  = queriesUnified;
    ".config/aerc/notmuch-queries-work".text     = mkLabelQueries "work";
    ".config/aerc/notmuch-queries-finance".text  = mkLabelQueries "finance";
    ".config/aerc/notmuch-queries-coaching".text = mkLabelQueries "coaching";
    ".config/aerc/notmuch-queries-personal".text = mkLabelQueries "gmail-personal";

    # NEW: compose templates
    ".config/aerc/templates/new_message".text = ''
      {{.Signature}}
      -- 
      Sent from aerc (https://aerc-mail.org)
    '';
    ".config/aerc/templates/quoted_reply".text = ''
      On {{.DateAutoFormat .OriginalDate.Local}}, {{index (.OriginalFrom | names) 0}} wrote:

      {{quote .OriginalText}}
    '';
  };

  packages = with pkgs; [
    aerc msmtp isync notmuch urlscan abook ripgrep dante chafa poppler-utils
    jq libxml2 mpv unzip gnutar file xdg-utils w3m pandoc glow p7zip unrar
    util-linux ncurses ov xclip
  ];

  inherit accountsFile;
}
