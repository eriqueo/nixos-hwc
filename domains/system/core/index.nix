# domains/system/core/index.nix — aggregates core system functionality
{ lib, ... }:
{
  #==========================================================================
  # OPTIONS
  #==========================================================================

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

  # Backward compat: hwc.system.core.shell.enable maps to packages
  options.hwc.system.core.shell.enable = lib.mkEnableOption "core shell (alias for packages.base)" // { default = true; };

  imports = [
    ./packages.nix
    ../../paths/paths.nix
    ./login.nix
    ./authentik/index.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = {};
}
