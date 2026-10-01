{ lib, pkgs, config, mailContract, aercPkg, grammar, ... }:
let
  tags = import ./tags.nix { inherit lib mailContract; };

  # A human disposition is a completed decision, not just a folder move.
  # Automatic arrival rules deliberately keep their existing unread semantics;
  # these commands are used only by interactive aerc bindings.
  archiveCmd = "mail-classifier transition --outcome done";
  trashCmd = "mail-classifier transition --outcome trash";
  # Native copy-link scans raw HTML and can retain &amp; in a target. Parse
  # the complete MIME message with urlscan for both viewer shortcuts instead.
  urlPicker = ":pipe -m ${pkgs.urlscan}/bin/urlscan --dedupe -f '${config.home.homeDirectory}/.local/bin/hwc-open {}'<Enter>";
  imageView = ":pipe -s -m ${pkgs.bash}/bin/bash -o pipefail -c '${pkgs.python3}/bin/python3 ${./plain-text-filter.py} --message-images ${aercPkg}/libexec/aerc/filters/html ${pkgs.chafa}/bin/chafa | ${pkgs.less}/bin/less -R -~'<Enter>";

  # Commands are realized here; keys and descriptions live in shared grammar.
  # Native choose dialogs avoid ambiguous nested which-key group names.
  quote = builtins.toJSON;
  choose = options: "choose " + lib.concatStringsSep " " (map (option:
    "-o ${quote option.key} ${quote option.desc} ${quote option.command}"
  ) options);
  hiddenWorkflowFlags = [ "action" "pending" ];
  visibleFlagTags = lib.filter (t: !(lib.elem t.tag hiddenWorkflowFlags)) tags.flagTags;
  stateKeys = grammar.aerc.stateKeys;
  domainKeys = grammar.aerc.domainKeys;
  menus = builtins.mapAttrs (_: choices: map (c: c // { command = native.${c.action}; }) choices)
    grammar.aerc.menus // {
    state = map (state: { key = stateKeys.${state}; desc = lib.toUpper state;
      command = "pipe -m mail-classifier correct --state ${state}"; }) mailContract.states;
    domain = map (domain: { key = domainKeys.${domain}; desc = domain;
      command = "pipe -m mail-classifier correct --domain ${domain}"; }) mailContract.domains;
    domain-filter = map (domain: { key = domainKeys.${domain}; desc = domain;
      command = "filter tag:${mailContract.domainTagPrefix}${domain}"; }) mailContract.domains;
    add-fact = map (t: { key = t.spaceKey; desc = "+${t.tag}";
      command = "modify-labels +${t.tag}"; }) visibleFlagTags;
  };
  native = {
    go-do = "cf do"; go-did = "cf did"; go-look = "cf look"; go-junk = "cf junk";
    go-backlog = "cf backlog"; go-inbox = "cf inbox_i"; go-all = "cf all";
    go-unread = "cf unread_u"; go-archive = "cf Archive_a"; go-sent = "cf sent_s";
    go-trash = "cf trash_d"; go-spam = "cf spam_z"; go-hide = "cf hide_my_email";
    clear = "clear -s";
    sort-date = "sort -r date"; sort-from = "sort from -r date";
    sort-subject = "sort subject -r date"; sort-alpha = "sort subject";
    tab-next = "next-tab"; tab-prev = "prev-tab"; tab-close = "close";
    headers = "toggle-headers"; fold = "fold -t"; fold-all = "fold -a";
    part-next = "next-part"; part-prev = "prev-part";
    task = "pipe -m email-to-task"; calendar = "pipe -m email-to-khal";
    paperless = "pipe -m email-to-paperless";
    compose = "compose"; forward = "forward"; reply = "reply"; reply-all = "reply -aq";
    archive = "pipe -m ${archiveCmd}"; trash = "pipe -m ${trashCmd}";
    unsubscribe = "unsubscribe -s"; read = "read"; unread = "unread";
    rule-create = "pipe -m mail-classifier route-review";
    rule-manage = "term mail-classifier route-manage";
    labels = ''prompt "Labels (+/-):" modify-labels'';
    clear-facts = "modify-labels ${tags.clearAllCmd}";
    new-tag = "term ${config.home.homeDirectory}/.local/bin/aerc-new-tag";
    sync = "exec ${pkgs.systemd}/bin/systemctl --user start --wait mbsync.service";
    reload = "reload"; quit = ''prompt "Quit aerc?" quit'';
    help = ''term ${pkgs.less}/bin/less -R "${config.home.homeDirectory}/.config/aerc/leader-cheatsheet.txt"'';
  } // builtins.mapAttrs (_: choices: choose choices) menus;
  commands = builtins.mapAttrs (_: cmd: ":${cmd}<Enter>") native // {
    filter = ":filter<space>"; search = ":search<space>";
    all-search = ":query -f -n mail-search<space>";
    tag-filter = ":filter tag:"; tag-search = ":query -f -n tag-search tag:";
    styleset = ":reload -s<space>"; move = ":mv<space>"; copy = ":cp<space>";
    images = imageView; links = urlPicker;
  };
  keymap = import ../../../home/keymap/parts/to-aerc.nix {
    inherit lib grammar commands menus;
  };
  # Workbench owns Ctrl navigation; Alt navigates aerc folders and tabs.
  tabBinds = ''
      <A-h> = :prev-tab<Enter> # previous aerc tab
      <A-l> = :next-tab<Enter> # next aerc tab
      <A-J> = :next-tab<Enter> # next aerc tab
      <A-K> = :prev-tab<Enter> # previous aerc tab
      <A-S-j> = :next-tab<Enter> # next aerc tab
      <A-S-k> = :prev-tab<Enter> # previous aerc tab
  '';

in
{
  files = profileBase: {
    ".config/aerc/binds.conf".text = ''
      # =============================================
      # Aerc — Single Proton + Notmuch (2026 best practice)
      # =============================================

      # Global
${tabBinds}
      <C-q> = :prompt 'Quit aerc?' quit<Enter>
      <C-t> = :term<Enter>
      <A-j> = :next-folder<Enter>
      <A-k> = :prev-folder<Enter>
      <C-p> = :next-account<Enter>
      <C-n> = :prev-account<Enter>
      <C-r> = :exec ${pkgs.systemd}/bin/systemctl --user start --wait mbsync.service<Enter>

      # Show your actual binds.conf instead of built-in defaults
      <semicolon> = :term ${pkgs.bash}/bin/bash -lc '${pkgs.less}/bin/less -R "$HOME/.config/aerc/binds.conf"'<Enter>

      [messages]
      j = :next<Enter>
      k = :prev<Enter>
      g = :select 0<Enter>
      G = :select -1<Enter>
      <C-d> = :next 50%<Enter>
      <C-u> = :prev 50%<Enter>
      <Enter> = :view<Enter>
      q = :quit<Enter>
      J = :mark -t<Enter>:next<Enter>
      K = :mark -t<Enter>:prev<Enter>
      V = :mark -v<Enter>
      r = :read<Enter>
      D = :pipe -m ${trashCmd}<Enter> # Trash (record outcome)
      u = :unread<Enter>

      # Static system tags (single-key for speed)
      # Native marked-or-selected semantics preserve J/K bulk selections.
      # A selected folded row expands to its complete thread.
      a = :pipe -m ${archiveCmd}<Enter>
      d = :pipe -m ${trashCmd}<Enter>

      c = :compose<Enter>
      C = :reply -aq<Enter>

      X = :mv<space>
      Y = :cp<space>
      / = :filter<space> # filter folder by words…
${keymap.bindsFor "messages"}

      [view]
      $noinherit = true
${tabBinds}
      q = :close<Enter>
      J = :next<Enter>
      K = :prev<Enter>
      r = :reply<Enter>
      R = :reply -aq<Enter>
      f = :forward<Enter>
      a = :pipe -m ${archiveCmd}<Enter>:close<Enter>
      d = :pipe -m ${trashCmd}<Enter>:close<Enter>
      H = :toggle-headers<Enter>
      u = ${urlPicker}
      / = :toggle-key-passthrough<Enter>/
      O = :open<Enter>
      S = :save<space>
      U = ${urlPicker}
      l = :next-part<Enter>
      h = :prev-part<Enter>
      o = :open<Enter>
      t = :pipe -m email-to-task<Enter>
      p = :pipe -m email-to-paperless<Enter>
${keymap.bindsFor "view"}

      [view::passthrough]
      $noinherit = true
      <Esc> = :toggle-key-passthrough<Enter>

      [compose]
      $noinherit = true
      $ex = <C-x>
${tabBinds}
      <Tab> = :next-field<Enter>
      <S-Tab> = :prev-field<Enter>
      <C-s> = :send<Enter>

      [compose::editor]
      $noinherit = true
      $ex = <C-x>

      [compose::review]
      y = :send<Enter>
      n = :abort<Enter>
      e = :edit<Enter>
      p = :postpone<Enter>
      a = :attach<Enter>
      A = :attach<space>
      H = :multipart text/html<Enter>

      [terminal]
      $noinherit = true
      $ex = <C-x>
${tabBinds}
${keymap.bindsFor "terminal"}
    '';

    ".config/aerc/leader-cheatsheet.txt".text = keymap.leaderHelp;

    ".local/bin/hwc-open" = {
      text = ''
        #!/usr/bin/env bash
        # hwc-open: context-aware URL/file opener.
        # On Wayland/X11: delegates to xdg-open.
        # On headless/SSH: OSC52 clipboard write (passes straight through plain SSH
        # to the outer kitty terminal) + prints the URL so kitty hint mode can pick it up.
        url="''${1:-}"
        [ -z "$url" ] && exit 1
        if [ -n "$WAYLAND_DISPLAY" ] || [ -n "$DISPLAY" ]; then
            exec ${pkgs.xdg-utils}/bin/xdg-open "$url"
        fi
        # urlscan redirects its opener's stdout/stderr to /dev/null. Clipboard
        # escapes must reach the controlling terminal, not inherited stdout.
        exec > /dev/tty
        # OSC52: base64-encode the URL and write clipboard escape to the terminal
        printf '\033]52;c;%s\a' \
          "$(printf '%s' "$url" | ${pkgs.coreutils}/bin/base64 | ${pkgs.coreutils}/bin/tr -d '\n')"
        # Belt-and-suspenders: also stash in tmux buffer if inside tmux
        if [ -n "$TMUX" ]; then
            ${pkgs.tmux}/bin/tmux set-buffer -- "$url"
        fi
        printf '\n\033[0;32m→ %s\033[0m\n' "$url"
      '';
      executable = true;
    };

    ".local/bin/aerc-new-tag" = {
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail

        TAGS_FILE="$HOME/.nixos/domains/mail/aerc/parts/tags-custom.json"
        TAG_GROUPS=(business money personal growth system urgent waiting)

        echo "=== Add New Aerc Tag ==="
        echo

        # Type
        echo "New tags are additive facts. They do not create a Domain or State."
        tag_type="flags"

        # Tag name
        read -rp "Tag name (lowercase, no spaces): " tag_name
        [[ -z "$tag_name" ]] && echo "Empty tag name." && exit 1

        # Keybind
        read -rp "Keybind key (single char for Space m t a <key>): " space_key
        [[ -z "$space_key" ]] && echo "Empty key." && exit 1
        case "$space_key" in
          '#'|'`'|'"'|'\') echo "Key '$space_key' breaks aerc INI config. Pick another."; exit 1 ;;
        esac

        # Group
        echo "Group: ''${TAG_GROUPS[*]}"
        read -rp "Group: " group_name
        if ! printf '%s\n' "''${TAG_GROUPS[@]}" | ${pkgs.ripgrep}/bin/rg -Fxq -- "$group_name"; then
          echo "Unknown group: $group_name"
          exit 1
        fi

        # Display name — use uppercase key if the raw key would break aerc config
        safe_display_key="$space_key"
        case "$safe_display_key" in
          '#'|'`'|'"'|'\') safe_display_key=$(echo "$space_key" | tr '#`"\\' 'HGQB') ;;
        esac
        display="''${tag_name}_''${safe_display_key}"

        # Build the new entry
        new_entry=$(${pkgs.jq}/bin/jq -n \
          --arg tag "$tag_name" \
          --arg display "$display" \
          --arg spaceKey "$space_key" \
          --arg group "$group_name" \
          '{tag: $tag, display: $display, spaceKey: $spaceKey, group: $group}')

        # Add to JSON file
        ${pkgs.jq}/bin/jq --argjson entry "$new_entry" \
          ".''${tag_type} += [\$entry]" \
          "$TAGS_FILE" > "''${TAGS_FILE}.tmp" \
          && mv "''${TAGS_FILE}.tmp" "$TAGS_FILE"

        echo
        echo "Added $tag_name to $tag_type (group: $group_name, key: Space m t a $space_key)"
        echo

        # Saving a custom fact is separate from deployment. An agent commits
        # this change and uses the correct lane; never activate an uncommitted
        # Home Manager generation from the shared main checkout.
        echo "Saved the fact definition. Ask the agent to commit and deploy it."
        echo "Use :modify-labels +$tag_name now to apply the fact to this message."
        echo "The new shortcut appears after deployment and aerc :reload."
        read -rp "Press Enter to close..."
      '';
      executable = true;
    };

    ".config/ov/config.yaml".text = ''

        # This is the official less-compatible config for ov
        # j/k now scroll, no "jump target" prompt ever

        General:
          TabWidth: 4
          Header: 0
          AlternateRows: false
          ColumnMode: false
          LineNumMode: false
          WrapMode: true
          ColumnDelimiter: ","
          MarkStyleWidth: 1
          HScrollWidth: "10%"
          DisableMouse: true

          Prompt:
            Normal: {}
            Input: {}

          Style:
            Alternate:
              Background: "gray"
            Header:
              Bold: true
            SearchHighlight:
              Reverse: true
            ColumnHighlight:
              Reverse: true
            MarkLine:
              Background: "darkgoldenrod"
            SectionLine:
              Background: "slateblue"
            Ruler:
              Background: "#333333"
              Foreground: "#CCCCCC"
              Bold: true
            JumpTargetLine:
              Underline: true

        KeyBind:
          exit:
            - "Escape"
            - "q"
          down:
            - "j"
            - "J"
            - "Enter"
            - "Down"
          up:
            - "k"
            - "K"
            - "Up"
          top:
            - "g"
            - "<"
            - "Home"
          bottom:
            - "G"
            - ">"
            - "End"
          page_down:
            - "Space"
            - "f"
            - "PageDown"
          page_up:
            - "b"
            - "PageUp"
          page_half_down:
            - "d"
            - "ctrl+d"
          page_half_up:
            - "u"
            - "ctrl+u"
          search:
            - "/"
          backsearch:
            - "?"
          next_search:
            - "n"
          next_backsearch:
            - "N"
          help:
            - "h"
        '';   # <- end of the block
    };
}
