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

{ config, lib, pkgs, inputs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.zellij;

  # The active system palette, flat token -> hex (no leading '#').
  colors = (config.hwc.home.theme or {}).colors or {};

  appearance = import ./parts/appearance.nix { inherit lib colors; };

  # Late binding: the mail pane runs the user's actual mail command, not an
  # assumed local `aerc`. Derived from the single declaration in the shell
  # domain (on the laptop: "ssh -t server aerc"; falls back to "aerc").
  mailCommand = (config.hwc.home.core.shell.aliases or {}).aerc or "aerc";
  layout      = import ./parts/layout.nix { inherit lib mailCommand; };

  # INTER-APP meta layer (Alt+Space). Generated from the unified keymap grammar
  # when it is present (profiles/desktop imports domains/home/keymap). Guarded:
  # if the keymap module is not imported, this is "" and zellij keeps its prior
  # default keybinds — so this wiring is safe whether or not keymap is enabled.
  km           = (config.hwc.home.keymap or {}).grammar or {};
  # The meta which-key is a custom zellij plugin (its own 600_apps repo, built to
  # wasm). The meta-leader launches it as a floating card instead of the subtle
  # status-bar mode; entries are generated from grammar.meta in to-zellij.nix.
  zellijWhichWasm = inputs.zellij-which.packages.${pkgs.system}.default;
  # Stable on-disk path (NOT the /nix/store path): zellij keys a plugin's
  # permission grant by its location string, and a store path's hash changes
  # every rebuild → it would re-prompt forever. Deploy the wasm to a fixed path
  # (below) and reference that, so the grant persists across rebuilds.
  zellijWhichPath = "${config.home.homeDirectory}/.config/zellij/plugins/zellij-which.wasm";
  metaKeybinds = lib.optionalString (km ? meta)
    (import ../../keymap/parts/to-zellij.nix {
      inherit lib colors;
      grammar = km;
      pluginWasm = zellijWhichPath;
    }).keybinds;
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
        // Intra-app Space leader lives in each app; zellij owns ONLY the
        // inter-app meta layer (Alt+Space), generated below from the unified
        // keymap grammar (domains/home/keymap). When that grammar is absent the
        // meta block is empty and zellij falls back to its defaults.
        theme "hwc"
        default_layout "${cfg.defaultLayout}"
        pane_frames true
        // Don't serialize/resurrect sessions. workbench is fully reconstructed
        // from the KDL layout on every open (it re-spawns its peer panes), so
        // there is nothing worth resurrecting — and a cached session could come
        // back STALE, defeating the whole point of wb-reload (SUPER+W). With
        // serialization off, an exited session can't linger to be resurrected;
        // every recreate is genuinely fresh. (on_force_close left at the default
        // "detach" on purpose: it keeps the reattach safety net for accidental
        // window-closes; wb-reload is the explicit, intentional clean restart.)
        session_serialization false
        ${appearance.themeBlock}
        ${metaKeybinds}
      '';

      # Stable path for the meta which-key plugin (see zellijWhichPath note).
      "zellij/plugins/zellij-which.wasm".source =
        "${zellijWhichWasm}/zellij-which.wasm";

      # The workbench pane grid. workbench spawns/focuses into these panes by
      # name via `zellij action new-pane`/`go-to-tab-name`; the layout just
      # gives a sane initial geometry so a cold `zellij` is usable too.
      "zellij/layouts/workbench.kdl".text = layout.workbenchKdl;
    };
  };
}
