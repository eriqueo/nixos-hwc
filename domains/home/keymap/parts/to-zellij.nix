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

{ lib, grammar }:

let
  # target pane/app -> zellij tab INDEX (1-based). zellij 0.44 keybinds only
  # support GoToTab <index>, NOT GoToTabName. Indices MUST match the tab order in
  # domains/home/apps/zellij/parts/layout.nix:
  #   1 home (host) · 2 tasks (todui) · 3 cal (khalt) · 4 files · 5 mail · 6 edit
  tabFor = {
    workbench = 1; todui = 2; khalt = 3;
    files = 4; mail = 5; edit = 6;
  };

  # nav intent -> zellij action (tab jumps use GoToTab <index>, handled separately)
  navAction = {
    next-pane = ''FocusNextPane;'';
    prev-pane = ''FocusPreviousPane;'';
    next-tab  = ''GoToNextTab;'';
    prev-tab  = ''GoToPreviousTab;'';
    pane-picker = ''SwitchToMode "Pane";'';     # leaves you in pane mode to pick
    scroll = ''SwitchToMode "Scroll";'';        # leaves you in scroll mode to read
    zoom = ''ToggleFocusFullscreen;'';
    detach = ''Detach;'';
    kill = ''Quit;'';
  };

  # intents that ENTER another mode — must NOT append a return to Normal.
  modeSwitchIntents = [ "pane-picker" "scroll" ];

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

  keybinds = ''
    // ===========================================================================
    // INTER-APP META LAYER — generated from domains/home/keymap/grammar.nix.
    // clear-defaults strips zellij's default Ctrl-chords (they collided with
    // aerc/yazi). The meta-leader (${grammar.metaLeader}) is the only global key.
    // ===========================================================================
    keybinds clear-defaults=true {
        normal {
            bind "${grammar.metaLeader}" { SwitchToMode "Tmux"; }
        }
        // `tmux` mode is repurposed as the transient META (app-switch) mode.
        tmux {
            bind "${grammar.metaLeader}" { SwitchToMode "Normal"; }
            bind "Esc" { SwitchToMode "Normal"; }
    ${metaBinds}
        }
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
