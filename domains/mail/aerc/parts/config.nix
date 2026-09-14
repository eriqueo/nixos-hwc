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

    # One bounded daily inbox, partitioned by context. DataX wins over Family
    # when signals overlap; HWC is the deliberate fallback so every message in
    # `now` appears in exactly one context folder.
    calmInbox = "tag:inbox AND tag:unread AND NOT tag:notification AND NOT tag:newsletter AND NOT tag:trash AND NOT tag:triage/noise";
    currentInbox = "${calmInbox} AND date:1w..";
    familySignal = "(tag:family OR tag:keep OR to:eriqueokeefe@gmail.com OR to:eriqueo@proton.me OR to:g_erique@proton.me)";

  queries = ''
    # ── Calm daily surface: one inbox plus three exact context partitions ──
    now            = ${currentInbox}
    family         = ${currentInbox} AND NOT tag:datax AND ${familySignal}
    datax          = ${currentInbox} AND tag:datax
    hwc            = ${currentInbox} AND NOT tag:datax AND NOT ${familySignal}
    backlog        = ${calmInbox} AND NOT date:1w..

    # ── Legacy drill-downs (hidden from the sidebar, still directly addressable) ──
    focus          = tag:inbox AND tag:unread AND NOT tag:notification AND NOT tag:newsletter AND NOT tag:trash
    today          = tag:inbox AND date:1d.. AND NOT tag:trash
    week           = tag:inbox AND date:1w.. AND NOT tag:trash
    people         = tag:inbox AND NOT tag:notification AND NOT tag:newsletter AND NOT tag:sent AND NOT tag:trash

    # ── Relationships ──
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
    folders             = now,family,datax,hwc
    default             = now
    enable-folders-sort = true
    folders-sort        = now,family,datax,hwc
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
      index-columns = state<3,date<10,from<22,subject<*
      # Column header row above the msglist (forked aerc feature), styled via the
      # msglist_header styleset object. Labels: state date from subject.
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
      dirlist-right = {{if eq .Folder "now"}}{{if .Unread}}{{humanReadable .Unread}}{{end}}{{end}}
      dirlist-tree = false
      mouse-enabled = true
      fuzzy-complete = true
      tab-title-account = mail{{if .Unread "now"}} ({{.Unread "now"}}){{end}}

      # Live column templates
      column-state   = {{if .IsUnread}}●{{else}} {{end}}{{if .IsFlagged}}★{{end}}
      column-date    = {{.DateAutoFormat .Date.Local}}
      column-from    = {{index (.From | names) 0}}
      column-subject = {{.ThreadPrefix}}{{if .ThreadFolded}}{{printf "{%d}" .ThreadCount}}{{end}}{{.Subject}}
      column-separator = " | "

      [viewer]

      pager = ${pkgs.less}/bin/less -R
      alternatives = text/html,text/plain
      [compose]
      editor = ${pkgs.neovim}/bin/nvim
      lf-editor = true
      empty-subject-warning = true
      # CRM rolodex completion when mail/contacts is on (khard + notmuch
      # history via mail-addresses); plain notmuch history otherwise.
      address-book-cmd = ${if (config.hwc.mail.contacts.enable or false)
        then ''mail-addresses "%s"''
        else ''notmuch address --format=text --output=recipients "%s"''}
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
