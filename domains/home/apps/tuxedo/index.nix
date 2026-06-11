# domains/home/apps/tuxedo/index.nix
#
# tuxedo — fast, keyboard-driven todo.txt TUI (webstonehq/tuxedo)
#
# NAMESPACE: hwc.home.apps.tuxedo.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.tuxedo.enable = true;
#
# Auto-imported by domains/home/apps/index.nix (readDir). Enabled in
# profiles/desktop/home.nix.

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
  # Seed file installed copy-once (tuxedo rewrites config.toml at runtime)
  seedConfigFile = pkgs.writeText "tuxedo-config.toml" seedConfig;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.tuxedo = {
    enable = lib.mkEnableOption "tuxedo — fast, keyboard-driven todo.txt TUI";

    package = lib.mkOption {
      type        = lib.types.nullOr lib.types.package;
      default     = null;
      description = ''
        tuxedo package to use. If null, builds from the upstream release binary
        via parts/package.nix (the todo.txt `tuxedo` is not in nixpkgs; only the
        unrelated `tuxedo-rs` hardware daemon is). Override to point at a nixpkgs
        attribute if/when it lands there.
      '';
    };

    todoDir = lib.mkOption {
      type        = lib.types.str;
      default     = "${config.home.homeDirectory}/000_inbox/todo";
      description = ''
        Directory holding todo.txt and done.txt. Exported as TODO_DIR;
        TODO_FILE and DONE_FILE are derived from it. tuxedo and any todo.txt-cli
        compatible tool read these to locate the task files.
      '';
    };
  };

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
      run mkdir -p ${lib.escapeShellArg cfg.todoDir}
      run touch ${lib.escapeShellArg todoFile} ${lib.escapeShellArg doneFile}

      cfgDir=${lib.escapeShellArg "${config.xdg.configHome}/tuxedo"}
      run mkdir -p "$cfgDir"
      if [ ! -e "$cfgDir/config.toml" ]; then
        run install -m 0644 ${seedConfigFile} "$cfgDir/config.toml"
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
