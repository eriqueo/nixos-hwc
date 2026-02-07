# domains/system/core/options.nix
#
# Consolidated options for system core subdomain
# Charter-compliant: ALL core options defined here

{ lib, ... }:

{
  #============================================================================
  # THERMAL OPTIONS
  #============================================================================
  options.hwc.system.core.thermal = {
    enable = lib.mkEnableOption "thermal management configuration";

    powerManagement = {
      enable = lib.mkEnableOption "power profile management";

      service = lib.mkOption {
        type = lib.types.enum [ "power-profiles-daemon" "tlp" ];
        default = "power-profiles-daemon";
        description = "Power management service to use";
      };
    };

    disableIncompatibleServices = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable thermal services that are incompatible with this hardware platform";
    };

    blacklistedModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "spd5118" ];
      description = "Kernel modules to blacklist for hardware compatibility";
    };
  };

  #============================================================================
  # FILESYSTEM OPTIONS (alias: hwc.filesystem)
  #============================================================================
  options.hwc.system.core.filesystem = {
    enable = lib.mkEnableOption "filesystem scaffolding (tmpfiles) driven by hwc.paths" // { default = true; };

    structure.dirs = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule ({ lib, ... }: {
        options = {
          path  = lib.mkOption { type = lib.types.str; };
          mode  = lib.mkOption { type = lib.types.str; default = "0755"; };
          user  = lib.mkOption { type = lib.types.str; default = "root"; };
          group = lib.mkOption { type = lib.types.str; default = "root"; };
        };
      }));
      default = [];
      description = "Extra directories to create via tmpfiles.d (alias available at hwc.filesystem.structure.dirs).";
    };
  };

  #============================================================================
  # PACKAGES OPTIONS
  #============================================================================
  options.hwc.system.core.packages = {
    enable = lib.mkEnableOption "core package bundles" // { default = true; };

    base.enable = lib.mkEnableOption "essential system packages for all machines" // { default = true; };

    server.enable = lib.mkEnableOption "server-focused system packages";

    security = {
      enable = lib.mkEnableOption "backup/security tooling bundle";

      protonDrive.enable = lib.mkEnableOption "Proton Drive integration helpers";

      extraTools = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = "Additional security/backup packages to install";
      };

      monitoring.enable = lib.mkEnableOption "security/backup monitoring helpers";
    };
  };

  #============================================================================
  # VALIDATION OPTIONS
  #============================================================================
  options.hwc.system.core.validation = {
    enable = lib.mkEnableOption "permission model validation service" // { default = true; };
  };
}
