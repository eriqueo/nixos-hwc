{ lib, pkgs, config, ... }:
let
    common    = import ../../accounts/helpers.nix { inherit lib; };
    accounts  = config.hwc.home.mail.accounts or {};
    accVals   = lib.attrValues accounts;
    colors    = (config.hwc.home.theme or {}).colors or {};
    appearance = import ./appearance.nix { inherit lib colors; };

    maildirBase =
        let nmRoot = config.hwc.home.mail.notmuch.maildirRoot or "";
            pathBase = config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail";
        in if nmRoot != "" then nmRoot else "${pathBase}/Maildir";

  queries = ''
    inbox_i        = tag:inbox AND NOT tag:trash
    unread_u       = tag:unread AND NOT tag:trash
    sent_s         = tag:sent
    drafts         = tag:draft
    Archive_a      = tag:archive AND NOT tag:trash
    trash_d        = tag:trash
    spam_z         = tag:spam
    important      = tag:important AND NOT tag:trash
    hide_my_email  = tag:hide
${tagQueries}
  '';

  accountsConf = ''
    [unified]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    folders-exclude     = ~^\\..*,~^proton(/.*)?$,~^proton-hwc$,~^proton-personal$,~^gmail-business$,~^gmail-personal$,~^acc:,~^hwc_email$,~^proton-native$
    multi-file-strategy = act-dir
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries
    from                = Eric <eric@iheartwoodcraft.com>
    outgoing            = ${pkgs.msmtp}/bin/msmtp
    default             = inbox_i
    enable-folders-sort = true
    folders-sort        = inbox_i,unread_u,action_!,pending_?,important,drafts,sent_s,Archive_a,trash_d,spam_z
  '';

  accountsFile = pkgs.writeText "aerc-accounts.conf" accountsConf;
  stylesetConf = appearance.stylesetContent;

  # Import shared tag definitions
  tags = import ./tags.nix { inherit lib; };
  tagDefs = tags.allTags;

  # Derive the style name for a tag (uses display if set, else tag)
  tagStyle = tags.tagStyle;

  # Category tag names for inbox-scoped queries
  categoryNames = builtins.listToAttrs (map (t: { name = t.tag; value = true; }) tags.categoryTags);
  isCategoryTag = t: categoryNames ? ${t.tag};

  # Derive notmuch query-map entries from tagDefs
  # Category tags are inbox-scoped (only show active items); flag tags show all
  tagQueries = lib.concatStringsSep "\n" (
    lib.filter (s: s != "") (map (t:
      let name = tagStyle t;
          baseQuery = t.query or "tag:${t.tag} AND NOT tag:trash";
          # Category tags and workflow flags are inbox-scoped (active items only)
          inboxScoped = isCategoryTag t || t.tag == "action" || t.tag == "pending";
          query = if inboxScoped then "(${baseQuery}) AND tag:inbox"
                  else baseQuery;
          n = 18 - builtins.stringLength name;
          pad = if n > 0 then lib.fixedWidthString n " " "" else "";
      in "    ${name}${pad} = ${query}"
    ) tagDefs)
  );

  # Derive the switch expression for column templates
  tagSwitch = let
    cases = map (t: ''(case `\b${t.tag}\b` "${tagStyle t}")'') tagDefs;
  in ''(switch (.Labels | join " ") ${lib.concatStringsSep " " cases} (default "default"))'';

  rowStyle = let
      cases = map (t: ''(case `\b${t.tag}\b` "${tagStyle t}")'') tags.categoryTags;
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
  }) bundledStylesets) // {
    ".config/aerc/stylesets/hwc".text = stylesetConf;
  };
in
{
  files = profileBase: {
    ".config/aerc/aerc.conf".text = ''
      [general]
      enable-osc8 = true

      [ui]
      index-columns = tags<12,date<10,from<16,to<14,flags>4,subject<*
      threading-enabled = true
      confirm-quit = false
      styleset-name = hwc
      dirlist-tree = true
      dirlist-collapse = 1
      dirlist-exclude = ^\..*|^proton(/.*)?$|^gmail-business|^gmail-personal|^acc:|^hwc_email$
      mouse-enabled = true
      fuzzy-complete = true
      tab-title-account = {{.Account}}{{if .Unread}} ({{.Unread}}){{end}}

      # Live column templates
      column-tags    = {{.StyleMap .Labels (exclude "inbox") (exclude "unread") (exclude "new") (exclude "sent") (exclude "draft") (exclude "trash") (exclude "spam") (exclude "archive") (exclude "flagged") (exclude "replied") (exclude "passed") (exclude "attachment") (exclude "signed") (exclude "encrypted") (exclude `^hwc`) (exclude `^proton`) (exclude `^gmail`) (exclude `^acc:`) (exclude "notifications") (exclude "notification") (exclude "aerc-notes") (exclude "action") (exclude "hide_my_email") (exclude "website") (exclude "starred") (exclude "important") ${tagStyleMapCases} (default "default") | join " " }}
      column-date    = {{.Style (.DateAutoFormat .Date.Local) ${rowStyle}}}
      column-from    = {{.Style (index (.From | names) 0) ${rowStyle}}}
      column-to      = {{.Style (index (.To | names) 0) ${rowStyle}}}
      column-flags   = {{.Flags | join "" }}
      column-subject = {{.ThreadPrefix}}{{if .ThreadFolded}}{{printf "{%d}" .ThreadCount}}{{end}}{{.Style .Subject ${rowStyle}}}
      column-separator = " | "

      [viewer]

      pager = ${pkgs.less}/bin/less -R
      alternatives = text/html,text/plain
      [compose]
      editor = ${pkgs.neovim}/bin/nvim
      lf-editor = true
      empty-subject-warning = true
      address-book-cmd = notmuch address --format=text --output=recipients "%s"
      file-picker-cmd = ${pkgs.yazi}/bin/yazi --chooser-file %s
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

      [openers]
      text/html = ${pkgs.xdg-utils}/bin/xdg-open
      text/* = ${pkgs.kitty}/bin/kitty ${pkgs.neovim}/bin/nvim
      application/pdf = ${pkgs.zathura}/bin/zathura
      image/* = ${pkgs.xdg-utils}/bin/xdg-open

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
