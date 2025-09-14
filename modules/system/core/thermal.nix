# nixos-hwc/modules/system/core/thermal.nix
#
# THERMAL - System thermal management and power profile configuration
# Provides thermal management configuration suitable for different hardware platforms
#
# DEPENDENCIES (Upstream):
#   - None (base system services)
#
# USED BY (Downstream):
#   - profiles/workstation.nix (enables via hwc.system.core.thermal.enable)
#
# IMPORTS REQUIRED IN:
#   - Automatically imported via modules/system/core/index.nix
#
# USAGE:
#   hwc.system.core.thermal.enable = true;
#   hwc.system.core.thermal.disableIncompatibleServices = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.core.thermal;
in {
  #============================================================================
  # OPTIONS - What can be configured
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
      default = [ "spd5118" ];  # DDR5 SPD sensor with resume issues
      description = "Kernel modules to blacklist for hardware compatibility";
    };
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================

  config = lib.mkIf cfg.enable {
    
    # Disable thermald (Intel-specific, causes issues on ThinkPads with unsupported ACPI)
    services.thermald.enable = lib.mkIf cfg.disableIncompatibleServices (lib.mkForce false);
    
    # Enable power profile management
    services.power-profiles-daemon.enable = lib.mkIf (cfg.powerManagement.enable && cfg.powerManagement.service == "power-profiles-daemon") true;
    services.tlp.enable = lib.mkIf (cfg.powerManagement.enable && cfg.powerManagement.service == "tlp") true;
    
    # Blacklist problematic kernel modules
    boot.blacklistedKernelModules = cfg.blacklistedModules;
    
    # Assertions to prevent conflicting services
    assertions = [
      {
        assertion = !(cfg.powerManagement.enable && cfg.powerManagement.service == "power-profiles-daemon" && config.services.tlp.enable);
        message = "Cannot enable both power-profiles-daemon and TLP simultaneously";
      }
      {
        assertion = !(cfg.powerManagement.enable && cfg.powerManagement.service == "tlp" && config.services.power-profiles-daemon.enable);
        message = "Cannot enable both TLP and power-profiles-daemon simultaneously";
      }
    ];
  };
}