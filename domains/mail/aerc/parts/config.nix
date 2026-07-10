{ lib, pkgs, config, aercPkg, ... }:
let
    common    = import ../../accounts/helpers.nix { inherit lib; };
    accounts  = config.hwc.mail.accounts or {};
    accVals   = lib.attrValues accounts;
    colors    = (config.hwc.home.theme or {}).colors or {};
    tags      = import ./tags.nix { inherit lib; inherit colors; };
    appearance = import ./appearance.nix { inherit lib colors tags; };

    maildirBase =
        let nmRoot = config.hwc.mail.notmuch.maildirRoot or "";
            pathBase = config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail";
        in if nmRoot != "" then nmRoot else "${pathBase}/Maildir";

  queries = ''
    # ── Focus: the manageable daily views ──
    focus          = tag:inbox AND tag:unread AND NOT tag:notification AND NOT tag:newsletter AND NOT tag:trash
    today          = tag:inbox AND date:1d.. AND NOT tag:trash
    week           = tag:inbox AND date:1w.. AND NOT tag:trash
    people         = tag:inbox AND NOT tag:notification AND NOT tag:newsletter AND NOT tag:sent AND NOT tag:trash

    # ── Relationships ──
    family         = tag:family AND NOT tag:trash
    keep           = tag:keep

    # ── Family aggregates (colour-grouped) ──
    business       = tag:inbox AND (tag:work OR tag:office OR tag:hwcmt) AND NOT tag:trash
    money          = tag:inbox AND (tag:finance OR tag:bank OR tag:insurance) AND NOT tag:trash
    growth         = tag:inbox AND (tag:admin OR tag:coaching) AND NOT tag:trash
    system         = tag:inbox AND (tag:tech OR tag:website) AND NOT tag:trash

    # ── Triage buckets (tag-backed; shared with the workbench kanban and the
    # morning briefing — placement IS the live triage/* tag) ──
${triageQueries}

    # ── Bulk / review ──
    all            = tag:inbox AND NOT tag:trash
    newsletters    = tag:inbox AND tag:newsletter AND NOT tag:trash
    notifications  = tag:inbox AND tag:notification AND NOT tag:trash

    # ── System + per-tag drill-down ──
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
    default             = focus
    enable-folders-sort = true
    folders-sort        = focus,today,week,people,${lib.concatMapStringsSep "," tags.triageTag tags.triageBuckets},action_!,pending_?,family,keep,business,money,growth,system,all,newsletters,notifications,inbox_i,unread_u,important,drafts,sent_s,Archive_a,trash_d,spam_z
  '';

  accountsFile = pkgs.writeText "aerc-accounts.conf" accountsConf;
  stylesetConf = appearance.stylesetContent;

  tagDefs = tags.allTags;

  # Derive the style name for a tag (uses display if set, else tag)
  tagStyle = tags.tagStyle;

  # Category tag names for inbox-scoped queries
  categoryNames = builtins.listToAttrs (map (t: { name = t.tag; value = true; }) tags.categoryTags);
  isCategoryTag = t: categoryNames ? ${t.tag};

  # Triage bucket folders — names contain "/" so dirlist-tree nests them under
  # one "triage" node. Inbox-scoped to mirror the workbench board's window.
  triageQueries = lib.concatStringsSep "\n" (map (b:
    let name = tags.triageTag b;
        n = 18 - builtins.stringLength name;
        pad = if n > 0 then lib.fixedWidthString n " " "" else "";
    in "    ${name}${pad} = tag:${tags.triageTag b} AND tag:inbox AND NOT tag:trash"
  ) tags.triageBuckets);

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

  # Derive [user] styleset section from tag group colors
  tagUserSection = ''

[user]
${tags.tagStyleLines}
hide.fg = #${colors.fg3 or "50626f"}
starred.fg = #${colors.errorBright or "d08080"}
starred.bold = true
default.fg = #${colors.fg3 or "50626f"}
default.dim = true
  '';

  # All bundled stylesets, each extended with the tag [user] section
  bundledStylesets = [ "blue" "catppuccin" "default" "dracula" "monochrome" "nord" "pink" "solarized" "solarized-dark" ];
  stylesetFiles = lib.listToAttrs (map (name: {
    name = ".config/aerc/stylesets/${name}";
    value.text = builtins.readFile "${aercPkg}/share/aerc/stylesets/${name}" + tagUserSection;
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
      index-columns = flags<6,tags<12,date<10,from<16,subject<*
      # Column header row above the msglist (forked aerc feature), styled via the
      # msglist_header styleset object. Labels: tags date from flags subject.
      index-headers = true
      threading-enabled = true
      confirm-quit = false
      # which-key leader popup (forked aerc feature). Pressing the Space leader
      # and pausing shows the possible next keys + annotations, narrowing as you
      # type. which-key-delay tuned a touch faster than the 500ms default.
      which-key = true
      which-key-delay = 350ms
      # Labels for group (prefix) keys in the popover, so <Space>g shows
      # "go: folders" not "+20". Mirrors domains/home/keymap/grammar.nix groups.
      which-key-groups = g:go (folders), m:mark (tags), f:find, s:sort, t:toggle/triage, b:buffer, y:yank, d:delete, w:window, p:project, o:open, q:quit
      styleset-name = hwc
      dirlist-left = {{.Style .Folder .Folder}}
      dirlist-tree = true
      dirlist-collapse = 1
      dirlist-exclude = ^\..*|^proton(/.*)?$|^gmail-business|^gmail-personal|^acc:|^hwc_email$
      mouse-enabled = true
      fuzzy-complete = true
      tab-title-account = {{.Account}}{{if .Unread}} ({{.Unread}}){{end}}

      # Live column templates
      column-tags    = {{.StyleMap .Labels (exclude "inbox") (exclude "unread") (exclude "new") (exclude "sent") (exclude "draft") (exclude "trash") (exclude "spam") (exclude "archive") (exclude "flagged") (exclude "replied") (exclude "passed") (exclude "attachment") (exclude "signed") (exclude "encrypted") (exclude `^hwc`) (exclude `^proton`) (exclude `^gmail`) (exclude `^acc:`) (exclude `^personal_`) (exclude `_google$`) (exclude `_proton$`) (exclude "newsletter") (exclude "notifications") (exclude "notification") (exclude "aerc-notes") (exclude "action") (exclude "hide_my_email") (exclude "starred") (exclude "important") ${tagStyleMapCases} (default "default") | join " " }}
      column-date    = {{.Style (.DateAutoFormat .Date.Local) ${rowStyle}}}
      column-from    = {{.Style (index (.From | names) 0) ${rowStyle}}}
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
      text/html = ${aercPkg}/libexec/aerc/filters/html
      text/plain = ${aercPkg}/libexec/aerc/filters/wrap -w $(${pkgs.ncurses}/bin/tput cols) | ${aercPkg}/libexec/aerc/filters/colorize
      text/calendar = ${aercPkg}/libexec/aerc/filters/calendar
      text/* = cat -
      message/delivery-status = ${aercPkg}/libexec/aerc/filters/colorize
      image/* = ${pkgs.bash}/bin/bash -lc 'if [ -n "$KITTY_WINDOW_ID" ]; then ${pkgs.kitty}/bin/kitty +kitten icat --stdin yes; else ${pkgs.chafa}/bin/chafa -f sixel -s $(${pkgs.ncurses}/bin/tput cols)x0 -; fi'
      application/pdf = ${pkgs.poppler-utils}/bin/pdftotext -layout - -
      application/json = ${pkgs.jq}/bin/jq -C . 2>/dev/null || cat -
      subject,~^\[PATCH = ${aercPkg}/libexec/aerc/filters/hldiff

      [openers]
      text/html = ${config.home.homeDirectory}/.local/bin/hwc-open
      text/* = ${pkgs.neovim}/bin/nvim
      image/* = ${config.home.homeDirectory}/.local/bin/hwc-open

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
      {{- trimSignature (exec `${aercPkg}/libexec/aerc/filters/html` .OriginalText) | quote -}}
      {{- else -}}
      {{- trimSignature .OriginalText | quote -}}
      {{- end}}
      {{- with .Signature }}

      {{.}}
      {{- end }}
    '';
  } // stylesetFiles;

  packages = with pkgs; [
    aercPkg msmtp isync w3m notmuch urlscan ripgrep glow pandoc
    chafa poppler-utils jq mpv xdg-utils ov xclip
  ];

  inherit accountsFile;
}
