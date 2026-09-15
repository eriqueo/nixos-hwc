{ lib, pkgs, config, ... }:
let
  tags = import ./tags.nix { inherit lib; };

  # A human disposition is a completed decision, not just a folder move.
  # Automatic arrival rules deliberately keep their existing unread semantics;
  # these commands are used only by interactive aerc bindings.
  archiveCmd = "+archive -inbox -unread";
  trashCmd = "+trash -inbox -unread";

  # Workbench/Zellij owns Ctrl navigation. Inside aerc, Alt+j/k moves through
  # the vertical folder list and Alt+h/l moves through the horizontal tab bar.
  # Keep both encodings of Alt+Shift+j/k as compatibility aliases: terminal
  # stacks can report the same physical chord as Alt+uppercase or as an
  # explicit Alt+Shift+lowercase key.
  tabBinds = ''
      <A-h> = :prev-tab<Enter> # previous aerc tab
      <A-l> = :next-tab<Enter> # next aerc tab
      <A-J> = :next-tab<Enter> # next aerc tab
      <A-K> = :prev-tab<Enter> # previous aerc tab
      <A-S-j> = :next-tab<Enter> # next aerc tab
      <A-S-k> = :prev-tab<Enter> # previous aerc tab
  '';

  # Keep the first mark popup bounded. Category bindings live one level deeper
  # under <Space>mc; action/pending remain automation tags but are deliberately
  # absent from the human workflow. Protected/custom flags live under mv.
  hiddenWorkflowFlags = [ "action" "pending" ];
  visibleFlagTags = lib.filter (t: !(lib.elem t.tag hiddenWorkflowFlags)) tags.flagTags;

  # Exclusive category bindings (adds tag, removes all other categories).
  # Trailing " # <tag>" is the aerc binding annotation shown in which-key.
  categoryBinds = lib.concatStringsSep "\n" (map (t:
    "      <Space>mc${t.spaceKey} = :modify-labels ${tags.exclusiveCmd t}<Enter> # ${t.tag}"
  ) tags.categoryTags);

  # Additive user-facing flags coexist with categories. The canonical taxonomy
  # still owns hidden automation flags and their query-map entries.
  flagBinds = lib.concatStringsSep "\n" (map (t:
    "      <Space>mv${t.spaceKey} = :modify-labels +${t.tag}<Enter> # +${t.tag}"
  ) visibleFlagTags);

  # ── Triage set-bucket bindings under <Space>t (t = toggle/triage group) ──
  # Replace-set semantics identical to the gateway's hwc_mail set-triage, so a
  # keypress here moves the same card on the workbench kanban. <Space>mt is
  # taken (tech category), hence the t group. Keys: first letter of bucket.
  triageBinds = lib.concatStringsSep "\n" (map (b:
    "      <Space>t${builtins.substring 0 1 b} = :modify-labels ${tags.setTriageCmd b}<Enter> # triage: ${b}"
  ) tags.triageBuckets);

  # Go-to triage folders: uppercase first letter (<Space>gt is tech's folder)
  triageGoBinds = lib.concatStringsSep "\n" (map (b:
    "      <Space>g${lib.toUpper (builtins.substring 0 1 b)} = :cf ${tags.triageTag b}<Enter> # ${tags.triageTag b}"
  ) tags.triageBuckets);

  # ── Leader cheat sheet (generated from the same tag data) ──
  catHelp  = lib.concatStringsSep "\n" (map (t: "    Space m c ${t.spaceKey}   ${t.tag}") tags.categoryTags);
  flagHelp = lib.concatStringsSep "\n" (map (t: "    Space m v ${t.spaceKey}   +${t.tag}") visibleFlagTags);
  leaderHelp = ''
    ════════ AERC LEADER MAP ════════   (Space = leader; Space ? shows this)

    NAVIGATE  -  Space g ...
    Space g i  now       Space g F  family    Space g D  datax
    Space g W  hwc       Space g B  backlog   Space g I  full inbox
    -- system destinations --
    Space g A  all mail  Space g a  archive   Space g s  sent
    Space g d  trash     Space g z  spam      Space g u  all unread

    MARK / CLASSIFY  -  Space m ...
    Space m a  archive   Space m d  trash     Space m u  unread
    Space m z  spam      Space m l  label...  Space m x  clear removable tags
    -- optional flags (additive; action/pending are automation-only) --
    ${flagHelp}
    -- categories (exclusive; Space m c ...) --
    ${catHelp}

    TRIAGE  -  Space t ... (mark)  /  Space g U|R|N (go to folder)
    Space t u  → urgent   Space t r  → review   Space t n  → noise
    (replace-set on the triage/* tags — moves the workbench kanban card too)

    FILTER / SORT / VIEW
    Space f t  filter current folder by tag (Tab completes)
    Space f T  find tag across all mail (Tab completes)
    Space f c  clear filter  Space f f  filter      Space f s  search
    Space f u  review unsubscribe
    Space s d  newest first  Space s f  sender  Space s s  subject
    Space r a  make sender rule   Space r m  manage sender rules
    Space t t  toggle threads
    Space t s  switch styleset            Space M    add new tag

    HAND OFF (open the message first; then archive with a)
    t  task → todui/phone    i  event → khalt/phone    p  record → Paperless

    MESSAGES (no leader)
    j / k  move      J / K  mark + move    V  visual-mark
    r  read          u  unread             a  archive     d  trash
    c  compose       C  reply-all          Enter  open    /  search

    AERC TABS
    Alt+H / Alt+L  previous / next tab
    Alt+Shift+J / K remain compatibility aliases

    (press q to close)
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
      <C-r> = :exec ${config.home.homeDirectory}/.local/bin/sync-mail<Enter>

      # Show your actual binds.conf instead of built-in defaults
      <semicolon> = :term ${pkgs.bash}/bin/bash -lc '${pkgs.less}/bin/less -R "$HOME/.config/aerc/binds.conf"'<Enter>

      # Leader cheat sheet (Space ?) — static which-key reference
      <Space>? = :term ${pkgs.bash}/bin/bash -lc '${pkgs.less}/bin/less -R "$HOME/.config/aerc/leader-cheatsheet.txt"'<Enter> # cheat sheet

      # Switch styleset on the fly
      <Space>ts = :reload -s<space> # reload styleset


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
      D = :delete<Enter>
      u = :unread<Enter>

      # Static system tags (single-key for speed)
      a = :modify-labels ${archiveCmd}<Enter>
      d = :modify-labels ${trashCmd}<Enter>

      c = :compose<Enter>
      C = :reply -aq<Enter>

      # Navigation (static folders + derived tag folders)
      # Trailing " # <label>" is the aerc annotation shown in the which-key popover.
      <Space>gi = :cf now<Enter> # now
      <Space>gF = :cf family<Enter> # family
      <Space>gD = :cf datax<Enter> # datax
      <Space>gW = :cf hwc<Enter> # hwc
      <Space>gB = :cf backlog<Enter> # backlog
      <Space>gI = :cf inbox_i<Enter> # all inbox
      <Space>gA = :cf all<Enter> # all mail
      <Space>gu = :cf unread_u<Enter> # unread
      <Space>ga = :cf Archive_a<Enter> # archive
      <Space>gs = :cf sent_s<Enter> # sent
      <Space>gd = :cf trash_d<Enter> # trash
      <Space>gz = :cf spam_z<Enter> # spam
      <Space>g_ = :cf hide_my_email<Enter> # hide-my-email

      # Triage folders (tag-backed buckets, shared with workbench kanban)
${triageGoBinds}

      # Flexible path
      X = :mv<space>
      Y = :cp<space>

      # Filter and Sort
      <Space>ff = :filter<space> # filter current folder
      <Space>fs = :search<space> # search current folder
      <Space>ft = :filter tag: # filter current folder by tag
      <Space>fT = :query -f -n tag-search tag: # find tag across all mail
      <Space>fc = :clear -s<Enter> # clear filter/search
      <Space>sd = :sort -r date<Enter> # sort by date
      <Space>sf = :sort from -r date<Enter> # sort by sender
      <Space>ss = :sort subject -r date<Enter> # sort by subject
      <Space>tt = :toggle-threads<Enter> # toggle threads

      # Reviewed exact-sender automation. A rule can assign a durable domain
      # tag and choose whether future mail enters now, archives, or trashes.
      <Space>ra = :pipe -m mail-rule review<Enter> # add sender rule
      <Space>rm = :term mail-rule manage<Enter> # manage sender rules

      # Triage bucket marking (replace-set, same semantics as workbench moves)
${triageBinds}

      # Use the sender's List-Unsubscribe header and skip straight to review
      # when the only available method is an email draft.
      <Space>fu = :unsubscribe -s<Enter> # review unsubscribe

      # === BOUNDED MARKING UNDER <Space>m LEADER ===
      <Space>mu = :modify-labels +unread<Enter> # mark unread
      <Space>ma = :modify-labels ${archiveCmd}<Enter> # archive
      <Space>md = :modify-labels ${trashCmd}<Enter> # trash
      <Space>mz = :modify-labels +spam -inbox<Enter> # spam
      <Space>ml = :modify-labels<space> # label…
      <Space>mx = :modify-labels ${tags.clearAllCmd}<Enter> # clear removable tags (keep protected)

      # Optional flags and categories are nested so the first popup stays calm.
${flagBinds}
${categoryBinds}

      # Add a new tag definition (edits tags-custom.json, runs hms)
      <Space>M = :term ${config.home.homeDirectory}/.local/bin/aerc-new-tag<Enter> # new tag…

      [view]
      $noinherit = true
${tabBinds}
      q = :close<Enter>
      J = :next<Enter>
      K = :prev<Enter>
      r = :reply<Enter>
      R = :reply -aq<Enter>
      f = :forward<Enter>
      a = :modify-labels ${archiveCmd}<Enter>:close<Enter>
      d = :modify-labels ${trashCmd}<Enter>:close<Enter>
      H = :toggle-headers<Enter>
      u = :open-link<Enter>
      / = :toggle-key-passthrough<Enter>/
      O = :open<Enter>
      S = :save<space>
      U = :pipe -m ${pkgs.urlscan}/bin/urlscan -c ${config.home.homeDirectory}/.local/bin/hwc-open<Enter>
      l = :next-part<Enter>
      h = :prev-part<Enter>
      o = :open<Enter>
      t = :pipe -m email-to-task<Enter>
      i = :pipe -m email-to-khal<Enter>
      p = :pipe -m email-to-paperless<Enter>
      <Space>ra = :pipe -m mail-rule review<Enter> # add sender rule
      <Space>rm = :term mail-rule manage<Enter> # manage sender rules

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
    '';

    ".config/aerc/leader-cheatsheet.txt".text = leaderHelp;

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
        echo "Type: (c)ategory or (f)lag?"
        read -rp "> " type_choice
        case "$type_choice" in
          c|C) tag_type="categories" ;;
          f|F) tag_type="flags" ;;
          *) echo "Invalid. Use c or f."; exit 1 ;;
        esac

        # Tag name
        read -rp "Tag name (lowercase, no spaces): " tag_name
        [[ -z "$tag_name" ]] && echo "Empty tag name." && exit 1

        # Keybind
        read -rp "Keybind key (single char for <Space>m<key>): " space_key
        [[ -z "$space_key" ]] && echo "Empty key." && exit 1
        case "$space_key" in
          '#'|'`'|'"'|'\') echo "Key '$space_key' breaks aerc INI config. Pick another."; exit 1 ;;
        esac

        # Group
        echo "Group: ''${TAG_GROUPS[*]}"
        read -rp "Group: " group_name
        if ! printf '%s\n' "''${TAG_GROUPS[@]}" | grep -qx "$group_name"; then
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
        echo "Added $tag_name to $tag_type (group: $group_name, key: <Space>m$space_key)"
        echo

        # Stage the file so nix flake can see it
        (cd "$HOME/.nixos" && git add "$TAGS_FILE")

        # Rebuild Home Manager
        echo "Running hms to apply..."
        pkg=$(nix build --no-link --print-out-paths "$HOME/.nixos#homeConfigurations.\"eric@$(hostname)\".activationPackage")
        "$pkg/activate"

        echo
        echo "Done! Restart aerc to pick up the new tag."
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
