# domains/home/keymap/parts/to-zellij.nix
#
# grammar.meta + grammar.metaLeader -> zellij `keybinds` KDL block.
#
# Implements the INTER-APP (meta) layer. `clear-defaults=true` strips zellij's
# entire default keymap — this is the fix for the silent collisions (default
# Ctrl+t/p/n/s were being eaten before aerc/yazi). The ONLY globally-intercepted
# chord becomes the meta-leader (Alt+Space), which switches zellij into the
# `tmux` mode (repurposed as our transient "meta" mode); a single key then jumps
# or navigates and drops back to Normal. Everything else flows to the focused
# pane untouched — so Space stays each app's intra-app leader and Ctrl+j/k reach
# todui/aerc for two-column nav.
#
# Pure function: returns { keybinds = "<kdl>"; }.

{ lib, grammar, pluginWasm ? null, colors ? {} }:

let
  # meta `target` -> zellij tab INDEX (1-based). zellij keybinds only support
  # GoToTab <index>, NOT GoToTabName, so the index MUST match the tab order in
  # domains/home/apps/zellij/parts/layout.nix. Derived from the SAME tabs.nix the
  # layout emits from (hubs first, then tools) so the two can never drift:
  #   1 hwc · 2 crm · 3 datax · 4 server · 5 brief · 6 tasks · 7 cal · 8 files · 9 mail · 10 edit
  tabs = import ../../apps/zellij/parts/tabs.nix;
  hubCount = builtins.length tabs.hubs;
  hubIndex = lib.listToAttrs (lib.imap1 (i: h: { name = h; value = i; }) tabs.hubs);
  # tool meta-targets, in the order layout.nix emits the tool tabs.
  toolTargets = [ "todui" "khalt" "files" "mail" "edit" ];
  toolIndex = lib.listToAttrs
    (lib.imap1 (i: t: { name = t; value = hubCount + i; }) toolTargets);
  tabFor = hubIndex // toolIndex;

  # nav intent -> zellij action (tab jumps use GoToTab <index>, handled separately)
  navAction = {
    next-pane = ''FocusNextPane;'';
    prev-pane = ''FocusPreviousPane;'';
    next-tab  = ''GoToNextTab;'';
    prev-tab  = ''GoToPreviousTab;'';
    # cycle-* move tabs but STAY in meta mode (see modeSwitchIntents) so j/k can
    # be pressed repeatedly to walk the tab bar; Esc / the leader exits.
    cycle-next = ''GoToNextTab;'';
    cycle-prev = ''GoToPreviousTab;'';
    pane-picker = ''SwitchToMode "Pane";'';     # leaves you in pane mode to pick
    scroll = ''SwitchToMode "Scroll";'';        # leaves you in scroll mode to read
    zoom = ''ToggleFocusFullscreen;'';
    detach = ''Detach;'';
    kill = ''Quit;'';
  };

  # intents that ENTER/STAY in another mode — must NOT append a return to Normal.
  modeSwitchIntents = [ "pane-picker" "scroll" "cycle-next" "cycle-prev" ];

  # zellij key tokens for the few non-letter keys in the meta map
  keyToken = k:
    if k == "bracketright" then "]"
    else if k == "bracketleft" then "["
    else k;

  bindLine = e:
    let tok = keyToken e.key; in
    if (e ? target) then
      ''        bind "${tok}" { GoToTab ${toString tabFor.${e.target}}; SwitchToMode "Normal"; }''
    # mode-switch intents LEAVE you in the target mode — do NOT return to Normal.
    else if lib.elem e.intent modeSwitchIntents then
      ''        bind "${tok}" { ${navAction.${e.intent}} }''
    else
      ''        bind "${tok}" { ${navAction.${e.intent}} SwitchToMode "Normal"; }'';

  metaBinds = lib.concatStringsSep "\n" (map bindLine grammar.meta);

  # ── zellij-which plugin entries (Model A) ────────────────────────────────
  # When a built plugin wasm is supplied, the meta-leader launches the
  # zellij-which floating card INSTEAD of the tmux-mode status-bar. Its entries
  # are generated from the SAME grammar.meta above (so they can never go stale),
  # mapping each meta intent to a plugin verb it can dispatch.
  intentVerb = {
    cycle-prev = "prev-tab"; cycle-next = "next-tab";
    next-tab = "next-tab";   prev-tab = "prev-tab";
    next-pane = "next-pane"; prev-pane = "prev-pane";
    pane-picker = "pane-mode"; zoom = "fullscreen";
    scroll = "scroll"; detach = "detach";
    # `kill` (Quit) has no plugin verb — omitted from the card on purpose.
  };
  entryFor = e:
    let tok = keyToken e.key; in
    if (e ? target) then "${tok}|goto-tab|${toString tabFor.${e.target}}|${e.desc}"
    else if intentVerb ? ${e.intent} then "${tok}|${intentVerb.${e.intent}}||${e.desc}"
    else null;
  pluginEntries = lib.concatStringsSep ";"
    (lib.filter (x: x != null) (map entryFor grammar.meta));

  # Distinct META accent (info/blue) so the outer/meta card reads differently
  # from the inner-app copper cards at a glance.
  hx = name: fallback: colors.${name} or fallback;
  # Ctrl is the workbench (meta) layer: Ctrl+j/k cycle tabs directly (no menu).
  # In-app side-column nav moved to Alt+j/k (apps), which passes through here.
  tabCycle = ''
            bind "Ctrl j" { GoToPreviousTab; }
            bind "Ctrl k" { GoToNextTab; }'';

  pluginNormalBlock = ''
        normal {
    ${tabCycle}
            bind "${grammar.metaLeader}" {
                LaunchOrFocusPlugin "file:${toString pluginWasm}" {
                    floating true
                    move_to_focused_tab true
                    title "META"
                    accent "${hx "info" "83a598"}"
                    fg "${hx "fg0" "ebdbb2"}"
                    title_bg "${hx "info" "83a598"}"
                    title_fg "${hx "bg0" "1d2021"}"
                    dim "${hx "fg3" "50626f"}"
                    entries "${pluginEntries}"
                }
            }
        }
  '';
  modeNormalBlock = ''
        normal {
    ${tabCycle}
            bind "${grammar.metaLeader}" { SwitchToMode "Tmux"; }
        }
        // `tmux` mode is repurposed as the transient META (app-switch) mode.
        tmux {
            bind "${grammar.metaLeader}" { SwitchToMode "Normal"; }
            bind "Esc" { SwitchToMode "Normal"; }
    ${metaBinds}
        }
  '';

  keybinds = ''
    // ===========================================================================
    // INTER-APP META LAYER — generated from domains/home/keymap/grammar.nix.
    // clear-defaults strips zellij's default Ctrl-chords (they collided with
    // aerc/yazi). The meta-leader (${grammar.metaLeader}) is the only global key.
    // ===========================================================================
    keybinds clear-defaults=true {
    ${if pluginWasm != null then pluginNormalBlock else modeNormalBlock}
        // Pane-picker drops you into a minimal Pane mode; Esc/leader returns.
        pane {
            bind "Esc" "${grammar.metaLeader}" { SwitchToMode "Normal"; }
            bind "Left" { MoveFocus "Left"; }
            bind "Right" { MoveFocus "Right"; }
            bind "Up" { MoveFocus "Up"; }
            bind "Down" { MoveFocus "Down"; }
            bind "Enter" { SwitchToMode "Normal"; }
        }
        // Scrollback reader (Ctrl+b s). clear-defaults strips zellij's own scroll
        // mode, so re-supply the essentials here — without it you cannot read
        // output that scrolled past. Esc/leader returns to Normal.
        scroll {
            bind "Esc" "${grammar.metaLeader}" { SwitchToMode "Normal"; }
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
            bind "PageDown" { PageScrollDown; }
            bind "PageUp" { PageScrollUp; }
            bind "G" { ScrollToBottom; }
        }
    }
  '';
in
{ inherit keybinds; }
