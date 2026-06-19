# domains/home/apps/workbench/index.nix
#
# THIN TRANSLATOR — wires the standalone `workbench` flake's HM module into the
# HWC namespace and feeds it the system theme palette + the MCP gateway URL +
# the Nix-generated hubs dir. Same model as the khalt/todui translators:
# the app ships a generic `programs.workbench` module; HWC supplies the values.
#
# NAMESPACE: hwc.home.apps.workbench.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.workbench.enable = true;
#
# Auto-imported by domains/home/apps/index.nix (readDir). `inputs` arrives via
# extraSpecialArgs (see flake.nix mkNixos/mkHome).

{ config, lib, pkgs, inputs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.workbench;

  # Active system palette -> flat token map, string values only, handed to the
  # app as JSON via the generic module's `palette` option (which sets
  # WORKBENCH_PALETTE). Identical contract to tasq's paletteJson.
  colors = lib.filterAttrs (_: v: builtins.isString v)
    (((config.hwc.home.theme or {}).colors or {}));

  # Late binding: the mail peer is NOT assumed to be a local binary. Derive its
  # launch command from the single declaration in the shell domain — on the
  # laptop mail lives on the server, so this is "ssh -t server aerc"; elsewhere
  # it falls back to a bare "aerc". Same fact the zellij layout derives.
  aercCmd = (config.hwc.home.core.shell.aliases or {}).aerc or "aerc";

  # Standing-tab map (navigate-to-tab, not spawn-duplicate): launch-target ->
  # tab name, the TOOL tabs only. Imported from the SAME source the zellij layout
  # emits its tab names from, so the host can never navigate to a tab name the
  # layout doesn't use. `hubs` is dropped — hub-pages are their own tabs, not
  # tool launch targets.
  layoutTabs = removeAttrs (import ../zellij/parts/tabs.nix) [ "hubs" ];

  # Unified keymap grammar → staged as ~/.config/workbench/keymap.json. The host
  # has a real chord state machine but its grammar is still hard-coded; the
  # app-side reader (feed Keymap.from_actions globals + DROP the Space t/c/m
  # jumps, which become Alt+Space owned by zellij) is the staged prerequisite —
  # see domains/home/keymap/README.md. Writing the file now is harmless.
  km   = (config.hwc.home.keymap or {}).grammar or {};
  kmWb = lib.optionalString (km ? meta)
    (import ../../keymap/parts/to-workbench.nix { inherit lib; grammar = km; }).json;
in
{
  imports = [ inputs.workbench.homeManagerModules.workbench ];

  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.workbench = {
    enable = lib.mkEnableOption "workbench — Textual TUI ops host (zellij-orchestrated)";

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:6200";
      description = "MCP gateway URL workbench talks to (offline fixtures fallback if unreachable).";
    };

    offline = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Force fixtures, never contact the gateway.";
    };

    hubsDir = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Directory of Nix-generated hub manifests (*.toml). Empty = the packaged
        hubs/ in the workbench flake. Set this to a generated path once hubs are
        produced from Nix data.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Drive the generic standalone module. It builds a wrapped `workbench` with
    # WORKBENCH_* baked in (palette JSON, gateway URL, hubs dir) and puts the
    # peer TUIs on its PATH so `zellij action` can spawn them.
    programs.workbench = {
      enable = true;
      palette = colors;
      gatewayUrl = cfg.gatewayUrl;
      offline = cfg.offline;
      hubsDir = cfg.hubsDir;
      defaultHub = "hwc";   # land on the HWC (woodcraft) hub, not DataX (alpha-first)
      tabs = layoutTabs;    # plain jumps navigate to the tool's standing tab

      # Peer launch overrides (late binding). Mail runs wherever the shell alias
      # says — on the laptop that's the server over ssh, so DON'T bake a local
      # aerc onto PATH; the launcher invokes `ssh -t server aerc` instead.
      launchers.aerc = aercCmd;
      # `opens = "url:…"` (e.g. the DataX SR2 dashboard on Enter) opens in the GUI
      # browser. Use `chromium-hwc-workbench`, NOT the SUPER+B `chromium-hwc`: it
      # carries the same GPU/ANGLE/WebGL flags but a DEDICATED --user-data-dir, so
      # workbench windows run in their own profile + singleton and never contend
      # with the interactive chromium for the Default profile's SQLite locks. Two
      # live instances over one profile (after a suspend/resume singleton race) is
      # what stacked the "couldn't open profile" dialogs. gpu-launch is on the
      # session PATH (same as the Hyprland keybind in apps/hyprland/parts/behavior.nix).
      launchers.browser = "gpu-launch chromium-hwc-workbench";
      extraRuntimePackages = with pkgs; [
        zellij        # the multiplexer workbench drives
        yazi          # peer pane: files
        neovim        # peer pane: editor (nvim --listen)
        # mail (aerc) is NOT a local binary here — see launchers.aerc above.
        # Only bake a local aerc when no remote alias redirects it.
        # todui + khalt come from their own HM modules already on PATH.
      ] ++ lib.optional (aercCmd == "aerc") aerc;
    };

    # Staged unified-keymap data (see let-block note). Harmless until the
    # app-side reader lands; written only when the keymap module is imported.
    xdg.configFile = lib.optionalAttrs (kmWb != "") {
      "workbench/keymap.json".text = kmWb;
    };
  };
}
