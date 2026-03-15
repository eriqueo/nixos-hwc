{ lib, pkgs, config, ... }:
let
    common    = import ../../../mail/parts/common.nix { inherit lib; };
    accounts  = config.hwc.home.mail.accounts or {};
    accVals   = lib.attrValues accounts;
    themePart = import ./theme.nix { inherit lib config; };

    maildirBase =
        let nmRoot = config.hwc.home.mail.notmuch.maildirRoot or "";
            pathBase = config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail";
        in if nmRoot != "" then nmRoot else "${pathBase}/Maildir";

  queries = ''
    inbox     = tag:inbox AND NOT tag:trash
    unread    = tag:unread AND NOT tag:trash
    sent      = tag:sent
    drafts    = tag:draft
    Archive   = tag:archive AND NOT tag:trash
    trash     = tag:trash
    important = tag:important AND NOT tag:trash
${tagQueries}
  '';

  accountsConf = ''
    [unified]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    folders-exclude     = ~^\\..*,~^proton(/.*)?$,~^proton-hwc$,~^proton-personal$,~^gmail-business$,~^gmail-personal$,~^acc:,~^hwc_email$,~^proton-native$
    multi-file-strategy = act-one-delete-rest
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries
    from                = Eric <eric@iheartwoodcraft.com>
    outgoing            = ${pkgs.msmtp}/bin/msmtp
    default             = inbox
  '';

  accountsFile = pkgs.writeText "aerc-accounts.conf" accountsConf;
  stylesetConf = themePart.stylesetContent;

  # Import shared tag definitions
  tags = import ./tags.nix { inherit lib; };
  tagDefs = tags.allTags;

  # Derive the style name for a tag (uses display if set, else tag)
  tagStyle = tags.tagStyle;

  # Derive notmuch query-map entries from tagDefs (tags that aren't pure aliases)
  tagQueries = lib.concatStringsSep "\n" (
    lib.filter (s: s != "") (map (t:
      let name = tagStyle t;
          query = t.query or "tag:${t.tag} AND NOT tag:trash";
      in if name == "personal" && t.tag == "personal" then ""  # skip alias (gmail-personal covers it)
         else "    ${name}${lib.fixedWidthString (10 - builtins.stringLength name) " " ""} = ${query}"
    ) tagDefs)
  );

  # Derive the switch expression for column templates
  tagSwitch = let
    cases = map (t: ''(case `\b${t.tag}\b` "${tagStyle t}")'') tagDefs;
  in ''(switch (.Labels | join " ") ${lib.concatStringsSep " " cases} (default "default"))'';

  # Derive the .StyleMap cases for column-tags
  tagStyleMapCases = lib.concatStringsSep " " (
    map (t: ''(case "${t.tag}" "${tagStyle t}")'') tagDefs
  );

  # Derive [user] styleset section
  tagUserSection = let
    lines = map (t:
      let name = tagStyle t;
      in "    ${name}.fg = ${t.color}" + lib.optionalString (t ? extra) "\n    ${t.extra}"
    ) tagDefs;
  in ''

    [user]
${lib.concatStringsSep "\n" lines}
    default.fg = #6272A4
    default.dim = true
  '';

  # All bundled stylesets, each extended with the tag [user] section
  bundledStylesets = [ "blue" "catppuccin" "default" "dracula" "monochrome" "nord" "pink" "solarized" "solarized-dark" ];
  stylesetFiles = lib.listToAttrs (map (name: {
    name = ".config/aerc/stylesets/${name}";
    value.text = builtins.readFile "${pkgs.aerc}/share/aerc/stylesets/${name}" + tagUserSection;
  }) bundledStylesets);
in
{
  files = profileBase: {
    ".config/aerc/aerc.conf".text = ''
      [general]
      enable-osc8 = true

      [ui]
      index-columns = tags<16,date<12,sender<17,flags>4,subject<*
      threading-enabled = true
      confirm-quit = false
      styleset-name = dracula
      dirlist-tree = true
      dirlist-collapse = 1
      dirlist-exclude = ^\..*|^proton(/.*)?$|^gmail-business|^gmail-personal|^acc:|^hwc_email$
      mouse-enabled = true
      fuzzy-complete = true
      tab-title-account = {{.Account}}{{if .Unread}} ({{.Unread}}){{end}}

      # Live column templates (required for the index-columns line above)
      column-tags    = {{.StyleMap .Labels (exclude "inbox") (exclude "unread") (exclude "new") (exclude "sent") (exclude "draft") (exclude "trash") (exclude "spam") (exclude "archive") (exclude "flagged") (exclude "replied") (exclude "passed") (exclude "attachment") (exclude "signed") (exclude "encrypted") (exclude `^hwc`) (exclude `^proton`) (exclude `^gmail`) (exclude `^acc:`) (exclude "notifications") (exclude "notification") (exclude "action") (exclude `^aerc`) ${tagStyleMapCases} (default "default") | join " " }}
      column-date    = {{.Style (.DateAutoFormat .Date.Local) ${tagSwitch}}}
      column-sender  = {{.Style (index (.From | names) 0) ${tagSwitch}}}
      column-flags   = {{.Flags | join ""}}
      column-subject = {{.ThreadPrefix}}{{if .ThreadFolded}}{{printf "{%d}" .ThreadCount}}{{end}}{{.Style .Subject ${tagSwitch}}}
      column-separator = " | "

      [viewer]

      pager = ${pkgs.less}/bin/less -R
      alternatives = text/plain,text/html
      [compose]
      editor = ${pkgs.neovim}/bin/nvim
      lf-editor = true
      empty-subject-warning = true
      address-book-cmd = notmuch address --format=text --output=recipients "%s"
      [filters]
      text/html = ${pkgs.aerc}/libexec/aerc/filters/html
      text/plain = ${pkgs.aerc}/libexec/aerc/filters/wrap -w $(${pkgs.ncurses}/bin/tput cols) | ${pkgs.aerc}/libexec/aerc/filters/colorize
      text/calendar = ${pkgs.aerc}/libexec/aerc/filters/calendar
      text/* = cat -
      message/delivery-status = ${pkgs.aerc}/libexec/aerc/filters/colorize
      image/* = ${pkgs.bash}/bin/bash -lc 'if [ -n "$KITTY_WINDOW_ID" ]; then ${pkgs.kitty}/bin/kitty +kitten icat --stdin yes; else ${pkgs.chafa}/bin/chafa -f sixel -s $(${pkgs.ncurses}/bin/tput cols)x0 -; fi'
      application/pdf = ${pkgs.poppler-utils}/bin/pdftotext -layout - -
      application/json = ${pkgs.jq}/bin/jq -C . 2>/dev/null || cat -
      subject,~^\[PATCH = ${pkgs.aerc}/libexec/aerc/filters/hldiff

      [multipart-converters]
      text/html = ${pkgs.pandoc}/bin/pandoc -f markdown -t html --standalone
    '';

    ".config/aerc/notmuch-queries".text = queries;

            # ".config/aerc/templates/new_message".text = ''
            # {{- with .Signature }}
        #'';
    ".config/aerc/templates/quoted_reply".text = ''
      On {{.DateAutoFormat .OriginalDate.Local}}, {{index (.OriginalFrom | names) 0}} wrote:

      {{ if eq .OriginalMIMEType "text/html" -}}
      {{- trimSignature (exec `${pkgs.aerc}/libexec/aerc/filters/html` .OriginalText) | quote -}}
      {{- else -}}
      {{- trimSignature .OriginalText | quote -}}
      {{- end}}
      {{- with .Signature }}

      {{.}}
      {{- end }}
    '';
  } // stylesetFiles;

  packages = with pkgs; [
    aerc msmtp isync w3m notmuch urlscan ripgrep glow pandoc
    chafa poppler-utils jq mpv xdg-utils ov xclip
  ];

  inherit accountsFile;
}
