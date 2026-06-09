# domains/home/apps/tuxedo/index.nix
#
# tuxedo — fast, keyboard-driven todo.txt TUI (webstonehq/tuxedo)
#
# NAMESPACE: hwc.home.apps.tuxedo.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.tuxedo.enable = true;
#
# Auto-imported by domains/home/apps/index.nix (readDir). Enabled in
# profiles/home-session.nix.

{ config, lib, pkgs, ... }:

let
  cfg       = config.hwc.home.apps.tuxedo;
  # Default: build from the upstream release binary (parts/package.nix), since
  # the todo.txt `tuxedo` is not in our pinned nixpkgs (only `tuxedo-rs`, the
  # unrelated hardware daemon). Override via cfg.package to use a nixpkgs attr
  # once/if it lands there.
  tuxedoPkg = if cfg.package != null then cfg.package else pkgs.callPackage ./parts/package.nix { };

  todoFile  = "${cfg.todoDir}/todo.txt";
  doneFile  = "${cfg.todoDir}/done.txt";

  seedConfig = import ./parts/config.nix { };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  imports = [ ./options.nix ];

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ tuxedoPkg ];

    # todo.txt-cli compatible environment. tuxedo reads these to locate files.
    home.sessionVariables = {
      TODO_DIR  = cfg.todoDir;
      TODO_FILE = todoFile;
      DONE_FILE = doneFile;
    };

    # Create the todo dir + files and seed a WRITABLE config.toml if absent.
    # home.activation (not xdg.configFile) because tuxedo rewrites config.toml
    # at runtime — a store symlink would break the app's own writes. This path
    # also works under both HM-as-module and HM-as-flake (mirrors mail/calendar).
    home.activation.tuxedoSetup = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${lib.escapeShellArg cfg.todoDir}
      touch ${lib.escapeShellArg todoFile} ${lib.escapeShellArg doneFile}

      cfgDir=${lib.escapeShellArg "${config.xdg.configHome}/tuxedo"}
      mkdir -p "$cfgDir"
      if [ ! -e "$cfgDir/config.toml" ]; then
        printf '%s' ${lib.escapeShellArg seedConfig} > "$cfgDir/config.toml"
      fi
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = tuxedoPkg != null;
        message   = "hwc.home.apps.tuxedo: package must be non-null "
          + "(set hwc.home.apps.tuxedo.package, or ensure pkgs.tuxedo exists).";
      }
    ];
  };
}
