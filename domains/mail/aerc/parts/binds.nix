{ lib, pkgs, config, ... }:
let
  tags = import ./tags.nix { inherit lib; };

  # Exclusive category bindings under <Space>m leader (adds tag, removes all other categories)
  categoryBinds = lib.concatStringsSep "\n" (map (t:
    "      <Space>m${t.spaceKey} = :modify-labels ${tags.exclusiveCmd t}<Enter>"
  ) tags.categoryTags);

  # Additive flag bindings under <Space>m leader (coexist with categories)
  flagBinds = lib.concatStringsSep "\n" (map (t:
    "      <Space>m${t.spaceKey} = :modify-labels +${t.tag}<Enter>"
  ) tags.flagTags);

  # Space-leader go-to-folder bindings
  goToBinds = lib.concatStringsSep "\n" (
    lib.filter (s: s != "") (map (t:
      let
        name = tags.tagStyle t;
        goKey = t.spaceKey or (builtins.substring 0 1 t.tag);
      in if (t.noGoTo or false) then ""
         else "      <Space>g${goKey} = :cf ${name}<Enter>"
    ) tags.allTags)
  );
in
{
  files = profileBase: {
    ".config/aerc/binds.conf".text = ''
      # =============================================
      # Aerc — Single Proton + Notmuch (2026 best practice)
      # =============================================

      # Global
      <C-h> = :prev-tab<Enter>
      <C-l> = :next-tab<Enter>
      <C-q> = :prompt 'Quit aerc?' quit<Enter>
      <C-t> = :term<Enter>
      <C-j> = :next-folder<Enter>
      <C-k> = :prev-folder<Enter>
      <C-p> = :next-account<Enter>
      <C-n> = :prev-account<Enter>
      <C-r> = :exec ${config.home.homeDirectory}/.local/bin/sync-mail<Enter>

      # Show your actual binds.conf instead of built-in defaults
      <semicolon> = :term ${pkgs.bash}/bin/bash -lc '${pkgs.less}/bin/less -R "$HOME/.config/aerc/binds.conf"'<Enter>

      # Switch styleset on the fly
      <Space>ts = :reload -s<space>


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
      a = :modify-labels +archive -inbox<Enter>
      d = :modify-labels +trash -inbox<Enter>

      c = :compose<Enter>
      C = :reply -aq<Enter>

      # Navigation (static folders + derived tag folders)
      <Space>gi = :cf inbox_i<Enter>
      <Space>gu = :cf unread_u<Enter>
      <Space>ga = :cf Archive_a<Enter>
      <Space>gs = :cf sent_s<Enter>
      <Space>gd = :cf trash_d<Enter>
      <Space>gz = :cf spam_z<Enter>
      <Space>g_ = :cf hide_my_email<Enter>
${goToBinds}

      # Flexible path
      X = :mv<space>
      Y = :cp<space>

      # Filter and Sort
      <Space>ff = :filter<space>
      <Space>fs = :search<space>
      <Space>sd = :sort -r date<Enter>
      <Space>tt = :toggle-threads<Enter>

      # Auto-trash sender management
      <Space>ft = :pipe -b -m ${config.home.homeDirectory}/.local/bin/aerc-trash-sender<Enter>:modify-labels +trash -inbox -unread<Enter>
      <Space>; = :term ${config.home.homeDirectory}/.local/bin/aerc-show-trash-senders<Enter>

      # === ALL MARKING UNDER <Space>m LEADER ===
      <Space>mu = :modify-labels +unread<Enter>
      <Space>ma = :modify-labels +archive -inbox<Enter>
      <Space>md = :modify-labels +trash -inbox<Enter>
      <Space>mz = :modify-labels +spam -inbox<Enter>
      <Space>ml = :modify-labels<space>

      # Toggle flags off (keys avoid collision with flag add-binds below)
      <Space>mx = :modify-labels -action<Enter>
      <Space>m. = :modify-labels -pending<Enter>
      <Space>mr = :modify-labels -important<Enter>
      <Space>mF = :modify-labels -flagged<Enter>

      # Clear flags only (keeps category)
      <Space>m- = :modify-labels ${tags.clearFlagsCmd}<Enter>
      # Nuclear: clear ALL tags (flags + category)
      <Space>m0 = :modify-labels ${tags.clearAllCmd}<Enter> 

      # Additive flag marking (coexists with categories)
${flagBinds}

      # Exclusive category marking (adds tag + removes all other categories)
${categoryBinds}

      # Add a new tag definition (edits tags-custom.json, runs hms)
      <Space>M = :term ${config.home.homeDirectory}/.local/bin/aerc-new-tag<Enter>

      [view]
      $noinherit = true
      q = :close<Enter>
      J = :next<Enter>
      K = :prev<Enter>
      r = :reply<Enter>
      R = :reply -aq<Enter>
      f = :forward<Enter>
      a = :modify-labels +archive -inbox<Enter>:close<Enter>
      d = :modify-labels +trash -inbox<Enter>:close<Enter>
      H = :toggle-headers<Enter>
      u = :open-link<Enter>
      / = :toggle-key-passthrough<Enter>/
      O = :open<Enter>
      S = :save<space>
      U = :pipe -m ${pkgs.urlscan}/bin/urlscan -c ${config.home.homeDirectory}/.local/bin/hwc-open<Enter>
      l = :next-part<Enter>
      h = :prev-part<Enter>
      o = :open<Enter>
      i = :pipe -m email-to-khal<Enter>

      [view::passthrough]
      $noinherit = true
      <Esc> = :toggle-key-passthrough<Enter>

      [compose]
      $noinherit = true
      $ex = <C-x>
      <C-h> = :prev-tab<Enter>
      <C-l> = :next-tab<Enter>
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
    '';

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

    ".local/bin/aerc-trash-sender" = {
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        sender=$(sed -n 's/^From:.*<\([^>]*\)>.*/\1/p;s/^From: *\([^<]*\)$/\1/p' | head -n1)
        if [ -n "$sender" ]; then
          mkdir -p ~/.config/notmuch
          echo "$sender" >> ~/.config/notmuch/trash-senders
          echo "Sender added to auto-trash list: $sender"
        else
          echo "Could not extract sender address" >&2
          exit 1
        fi
      '';
      executable = true;
    };

    ".local/bin/aerc-show-trash-senders" = {
      text = ''
        #!/usr/bin/env bash
        echo "=== AUTO-TRASH SENDERS ==="
        if [ -f ~/.config/notmuch/trash-senders ]; then
          sort ~/.config/notmuch/trash-senders | column
        else
          echo "(none)"
        fi
        echo
        read -rp "Press Enter to close..."
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
