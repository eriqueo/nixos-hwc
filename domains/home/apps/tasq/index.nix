# domains/home/apps/tasq/index.nix
#
# tasq — VTODO-native keyboard task TUI (Textual) over the Phase A vdir
#
# NAMESPACE: hwc.home.apps.tasq.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.tasq.enable = true;
#
# Auto-imported by domains/home/apps/index.nix (readDir). Enabled in
# profiles/desktop/home.nix. Source lives git-tracked in workspace/home/tasq/
# and is exec'd by absolute path (scraper precedent) — editing the .py files
# takes effect immediately; only env/module changes need a rebuild.

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.tasq;

  # Handshake protocol for standalone compatibility
  nixosPath = lib.attrByPath [ "hwc" "paths" "nixos" ] "/home/eric/.nixos" osConfig;

  # toPythonModule is the trick: nixpkgs only ships todoman as a top-level
  # application (no python3Packages.todoman), but its lib (todoman.model) is
  # the VTODO read/write engine tasq is built on.
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.textual
    ps.icalendar
    (ps.toPythonModule pkgs.todoman)
  ]);

  runner = pkgs.writeShellScriptBin "tasq" ''
    export TASQ_PATH="''${TASQ_PATH:-${cfg.tasksGlob}}"
    export TASQ_CACHE="''${TASQ_CACHE:-${cfg.cachePath}}"
    exec ${pythonEnv}/bin/python ${nixosPath}/workspace/home/tasq/app.py "$@"
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.tasq = {
    enable = lib.mkEnableOption "tasq — VTODO-native keyboard task TUI";

    tasksGlob = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/vdirsyncer/tasks/*";
      description = "Glob to the VTODO vdir list dirs (matches the Phase A tasks sync).";
    };

    cachePath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.cache/tasq/cache.sqlite3";
      description = "tasq's own todoman.model sqlite cache (separate from the todoman CLI's).";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ runner ];

    home.sessionVariables = {
      TASQ_PATH = cfg.tasksGlob;
      TASQ_CACHE = cfg.cachePath;
    };

    home.activation.tasqDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ${lib.escapeShellArg (builtins.dirOf cfg.cachePath)}
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    # Relative path so the check works under pure/restricted eval (an absolute
    # /home path here would break flake evaluation).
    assertions = [
      {
        assertion = builtins.pathExists ../../../../workspace/home/tasq/app.py;
        message = "hwc.home.apps.tasq: workspace/home/tasq/app.py is missing from the repo.";
      }
    ];
  };
}
