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

      # ONE BIND TO CLEAR THEM ALL
      <Space>m- = :modify-labels ${tags.clearCustomCmd}<Enter> 

      # Additive flag marking (coexists with categories)
${flagBinds}

      # Exclusive category marking (adds tag + removes all other categories)
${categoryBinds}


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
      U = :pipe -m urlscan<Enter>
      l = :next-part<Enter>
      h = :prev-part<Enter>
      o = :open<Enter>
      I = :pipe -p khal import<Enter>

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
