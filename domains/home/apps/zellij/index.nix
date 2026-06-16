# domains/home/apps/zellij/index.nix
#
# zellij — the multiplexer workbench drives. workbench orchestrates panes via
# `zellij action` (spawn/focus); this module installs zellij, emits a
# palette-driven theme, and ships the `workbench` KDL layout that lays out the
# pane grid (todui | khalt | aerc | yazi | nvim as PEER spawned panes — none
# mounted in-process).
#
# NAMESPACE: hwc.home.apps.zellij.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.zellij.enable = true;
#
# Auto-imported by domains/home/apps/index.nix (readDir). Enable in
# profiles/desktop/home.nix alongside hwc.home.apps.workbench.
#
# PALETTE CONSUME CONTRACT (mirrors yazi/tasq): the active system theme arrives
# as `config.hwc.home.theme.colors`; this module derives the zellij theme from
# it. Switch hwc.home.theme.palette → zellij + workbench restyle on rebuild.

{ config, lib, pkgs, osConfig ? {}, inputs ? {}, ... }:

let
  cfg = config.hwc.home.apps.zellij;

  # The active system palette, flat token -> hex (no leading '#').
  colors = (config.hwc.home.theme or {}).colors or {};

  appearance = import ./parts/appearance.nix { inherit lib colors; };

  # Late binding: the mail pane runs the user's actual mail command, not an
  # assumed local `aerc`. Derived from the single declaration in the shell
  # domain (on the laptop: "ssh -t server aerc"; falls back to "aerc").
  mailCommand = (config.hwc.home.core.shell.aliases or {}).aerc or "aerc";

  # True-powerline tab bar via the zjstatus plugin (the built-in zellij:tab-bar
  # can't do powerline segments). Themed from the active palette. Guarded: only
  # used when cfg.powerlineTabs AND the zjstatus input is present — otherwise the
  # layout falls back to its built-in tab-bar default, so this is safe even if
  # the input is removed.
  zjstatusWasm = lib.optionalString (inputs ? zjstatus)
    "${inputs.zjstatus.packages.${pkgs.system}.default}/bin/zjstatus.wasm";
  tabBar = lib.optionalString (cfg.powerlineTabs && inputs ? zjstatus)
    (import ./parts/zjstatus.nix { inherit lib colors; wasm = zjstatusWasm; });
  layout = import ./parts/layout.nix
    ({ inherit lib mailCommand; } // lib.optionalAttrs (tabBar != "") { inherit tabBar; });

  # INTER-APP meta layer (Alt+Space). Generated from the unified keymap grammar
  # when it is present (profiles/desktop imports domains/home/keymap). Guarded:
  # if the keymap module is not imported, this is "" and zellij keeps its prior
  # default keybinds — so this wiring is safe whether or not keymap is enabled.
  km           = (config.hwc.home.keymap or {}).grammar or {};
  metaKeybinds = lib.optionalString (km ? meta)
    (import ../../keymap/parts/to-zellij.nix { inherit lib; grammar = km; }).keybinds;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.zellij = {
    enable = lib.mkEnableOption "zellij — terminal multiplexer (workbench's pane host)";

    defaultLayout = lib.mkOption {
      type = lib.types.str;
      default = "workbench";
      description = "Layout zellij opens by default (the workbench KDL grid).";
    };

    powerlineTabs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use the zjstatus plugin for a themed true-powerline tab bar instead of
        the built-in zellij:tab-bar. Requires the `zjstatus` flake input; falls
        back to the built-in bar when off or the input is absent.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.zellij ];

    # zellij reads $XDG_CONFIG_HOME/zellij/config.kdl + layouts/*.kdl.
    # We DO NOT use programs.zellij.settings (it hardcodes its own theme path);
    # we write KDL directly so the theme is 100% palette-derived, matching the
    # yazi precedent (xdg.configFile + a pure appearance.nix function).
    xdg.configFile = {
      "zellij/config.kdl".text = ''
        // Auto-generated from the ${colors.name or "system"} palette.
        // Intra-app Space leader lives in each app; zellij owns ONLY the
        // inter-app meta layer (Alt+Space), generated below from the unified
        // keymap grammar (domains/home/keymap). When that grammar is absent the
        // meta block is empty and zellij falls back to its defaults.
        theme "hwc"
        default_layout "${cfg.defaultLayout}"
        pane_frames true
        ${appearance.themeBlock}
        ${metaKeybinds}
      '';

      # The workbench pane grid. workbench spawns/focuses into these panes by
      # name via `zellij action new-pane`/`go-to-tab-name`; the layout just
      # gives a sane initial geometry so a cold `zellij` is usable too.
      "zellij/layouts/workbench.kdl".text = layout.workbenchKdl;
    };
  };
}
