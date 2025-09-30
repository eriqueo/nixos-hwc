# domains/infrastructure/session/options.nix
#
# Consolidated options for infrastructure session subdomain
# Charter-compliant: ALL session options defined here, implementations in parts/

{ lib, config, ... }:

{
  options.hwc.infrastructure.session = {

    #==========================================================================
    # SERVICES - User system services
    #==========================================================================
    services = {
      enable = lib.mkEnableOption "user system services (home-manager integration, SSH setup)";

      username = lib.mkOption {
        type = lib.types.str;
        default = config.hwc.system.users.user.name or "eric";
        description = "Username for user services";
      };
    };

    #==========================================================================
    # COMMANDS - Shared CLI commands
    #==========================================================================
    commands = {
      enable = lib.mkEnableOption "shared CLI commands for cross-app integration";
      gpuLaunch = lib.mkEnableOption "gpu-launch command for GPU-accelerated app launching";
    };
  };
}