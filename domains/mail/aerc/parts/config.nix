{ lib, pkgs, config, aercPkg, mailContract, grammar, ... }:
let
    keymap = import ../../../home/keymap/parts/to-aerc.nix {
      inherit lib grammar; commands = {}; menus = {};
    };
    common    = import ../../accounts/helpers.nix { inherit lib; };
    accounts  = config.hwc.mail.accounts or {};
    accVals   = lib.attrValues accounts;
    colors    = (config.hwc.home.theme or {}).colors or {};
    tags      = import ./tags.nix { inherit lib mailContract; inherit colors; };
    appearance = import ./appearance.nix { inherit lib colors tags; };

    maildirBase =
        let nmRoot = config.hwc.mail.notmuch.maildirRoot or "";
            pathBase = config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail";
        in if nmRoot != "" then nmRoot else "${pathBase}/Maildir";

    searchRegistry = import ../../notmuch/parts/searches.nix {
      inherit lib mailContract;
      cfg = config.hwc.mail.notmuch or {};
    };
    activeStateQuery = lib.concatStringsSep " OR "
      (map (state: searchRegistry.searches.${"state:${state}"}) mailContract.states);
    legacyBacklog = "tag:inbox AND NOT (${activeStateQuery}) AND NOT tag:${mailContract.completedTag} AND NOT tag:trash";
    domainDisplay = {
      hwc = "HWC"; datax = "DataX"; family = "Family";
      personal = "Personal"; other = "Other";
    };
    stateDisplay = { "do" = "DO"; did = "DID"; look = "LOOK"; junk = "JUNK"; };
    templateCases = prefix: items: display:
      lib.concatStringsSep " " (map (item:
        ''(case `^${prefix}${item}$` "${display.${item} or item}")''
      ) items);
    domainCases = templateCases mailContract.domainTagPrefix mailContract.domains domainDisplay + " (exclude `.*`)";
    stateCases = templateCases mailContract.stateTagPrefix mailContract.states stateDisplay + " (exclude `.*`)";
    manualFactTags = map (tag: tag.tag)
      (lib.filter (tag: !(lib.elem tag.tag [ "action" "pending" ])) tags.flagTags);
    # The header-backed unsubscribe trait describes an available mechanism,
    # not a decision or requested action. Keep it in the classifier contract
    # but omit it from the human-facing Tags column.
    visibleTraitTags = lib.filter (tag: tag != "unsubscribe") mailContract.factTags;
    traitCases = templateCases mailContract.traitTagPrefix visibleTraitTags {}
      + " " + templateCases "" manualFactTags {} + " (exclude `.*`)";
    # Final receivers that are allowed to attest Authentication-Results. Aerc's
    # RFC 8058 unsubscribe command rejects all other headers before acting; do
    # not replace this exact list with the documented debugging wildcard (`*`).
    trustedAuthResults = [ "^mail\\.protonmail\\.ch$" "^mx\\.google\\.com$" ];

  # Transport aliases retain the compact State sidebar and navigation keys.
  # Historical account/category searches remain explicit history:* entries.
  queryAliases = builtins.listToAttrs (map (state: {
    name = state; value = searchRegistry.searches.${"state:${state}"};
  }) mailContract.states) // {
    backlog = legacyBacklog;
    inbox_i = searchRegistry.searches.inbox;
    unread_u = searchRegistry.searches.unread;
    sent_s = searchRegistry.searches.sent;
    Archive_a = searchRegistry.searches.archive;
    trash_d = searchRegistry.searches.trash;
    spam_z = searchRegistry.searches.spam;
    hide_my_email = searchRegistry.searches."label:hide";
    finance = searchRegistry.searches."fact:finance";
  };
  queries = searchRegistry.aercText + lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: query: "${name}=${query}") queryAliases) + "\n";

  accountsConf = ''
    [unified]
    source              = notmuch://${maildirBase}
    maildir-store       = ${maildirBase}
    folders-exclude     = ~^\\..*,~^proton(/.*)?$,~^proton-hwc$,~^proton-personal$,~^gmail-business$,~^gmail-personal$,~^acc:,~^hwc_email$,~^proton-native$
    multi-file-strategy = act-dir
    query-map           = ${config.home.homeDirectory}/.config/aerc/notmuch-queries
    from                = Eric <eric@iheartwoodcraft.com>
    outgoing            = ${pkgs.msmtp}/bin/msmtp
    trusted-authres     = ${lib.concatStringsSep "," trustedAuthResults}
    folders             = do,did,look,junk
    default             = do
    enable-folders-sort = true
    folders-sort        = do,did,look,junk
  '';

  accountsFile = pkgs.writeText "aerc-accounts.conf" accountsConf;
  stylesetConf = appearance.stylesetContent;

  tagDefs = tags.allTags;

  # Derive the style name for a tag (uses display if set, else tag)
  tagStyle = tags.tagStyle;

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
      index-columns = from<20,subject<*,date<10,domain<9,state<5,tags<24
      # Column header row above the msglist (forked aerc feature), styled via the
      # msglist_header styleset object. Labels: from subject date domain state tags.
      index-headers = true
      threading-enabled = true
      sort = -r date
      confirm-quit = false
      # which-key leader popup (forked aerc feature). Pressing the Space leader
      # and pausing shows the possible next keys + annotations, narrowing as you
      # type. which-key-delay tuned a touch faster than the 500ms default.
      which-key = true
      which-key-delay = 350ms
      # Labels for group (prefix) keys in the popover, so <Space>g shows
      # "go: folders" not "+20". Mirrors domains/home/keymap/grammar.nix groups.
      which-key-groups = ${keymap.whichKeyGroups}
      styleset-name = hwc
      dirlist-left = {{.Style .Folder .Folder}}
      dirlist-right = {{if .Exists}}{{humanReadable .Exists}}{{end}}
      dirlist-tree = false
      mouse-enabled = true
      fuzzy-complete = true
      tab-title-account = mail{{if .Exists "do"}} ({{.Exists "do"}} DO){{end}}

      # Live column templates
      column-from    = {{index (.From | names) 0}}
      column-subject = {{.ThreadPrefix}}{{if .ThreadFolded}}{{printf "{%d}" .ThreadCount}}{{end}}{{.Subject}}
      column-date    = {{.DateAutoFormat .Date.Local}}
      column-domain  = {{map .Labels ${domainCases} | join ","}}
      column-state   = {{map .Labels ${stateCases} | join ","}}
      column-tags    = {{map .Labels ${traitCases} | join ","}}
      column-separator = " | "

      [viewer]

      # -~ keeps the unused area below a short message visually blank instead
      # of filling the whole viewer with Vim-like tilde markers.
      pager = ${pkgs.less}/bin/less -R -~
      # Sender-authored plain text is the calm default. HTML remains available
      # with h/l when its visual layout carries meaning.
      alternatives = text/plain,text/html
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
      # Preserve readable, network-isolated HTML and expose labeled action links
      # from the original source, including Google's table-based RSVP buttons.
      text/html = ${pkgs.python3}/bin/python3 ${./plain-text-filter.py} --html-renderer ${aercPkg}/libexec/aerc/filters/html
      text/plain = ${aercPkg}/libexec/aerc/filters/wrap -w 100 | ${pkgs.python3}/bin/python3 ${./plain-text-filter.py}
      text/calendar = ${aercPkg}/libexec/aerc/filters/calendar
      text/* = cat -
      message/delivery-status = ${aercPkg}/libexec/aerc/filters/colorize
      # No image filter: Vaxis selects native graphics or portable half blocks.
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
