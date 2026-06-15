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
      # Peer launch overrides (late binding). Mail runs wherever the shell alias
      # says — on the laptop that's the server over ssh, so DON'T bake a local
      # aerc onto PATH; the launcher invokes `ssh -t server aerc` instead.
      launchers.aerc = aercCmd;
      extraRuntimePackages = with pkgs; [
        zellij        # the multiplexer workbench drives
        yazi          # peer pane: files
        neovim        # peer pane: editor (nvim --listen)
        # mail (aerc) is NOT a local binary here — see launchers.aerc above.
        # Only bake a local aerc when no remote alias redirects it.
        # todui + khalt come from their own HM modules already on PATH.
      ] ++ lib.optional (aercCmd == "aerc") aerc;
    };
  };
}
