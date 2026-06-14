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

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.zellij;

  # The active system palette, flat token -> hex (no leading '#').
  colors = (config.hwc.home.theme or {}).colors or {};

  appearance = import ./parts/appearance.nix { inherit lib colors; };
  layout     = import ./parts/layout.nix { inherit lib; };
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
        // workbench drives panes via `zellij action`; keep keybinds out of its
        // way — the space-leader grammar lives in workbench, not here.
        theme "hwc"
        default_layout "${cfg.defaultLayout}"
        pane_frames true
        ${appearance.themeBlock}
      '';

      # The workbench pane grid. workbench spawns/focuses into these panes by
      # name via `zellij action new-pane`/`go-to-tab-name`; the layout just
      # gives a sane initial geometry so a cold `zellij` is usable too.
      "zellij/layouts/workbench.kdl".text = layout.workbenchKdl;
    };
  };
}
