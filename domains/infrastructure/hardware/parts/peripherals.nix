# HWC Charter Module/domains/infrastructure/printing.nix
#
# PRINTING - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.infrastructure.printing.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/printing.nix
#
# USAGE:
#   hwc.infrastructure.printing.enable = true;
#   # TODO: Add specific usage examples

# HWC Charter Module/domains/infrastructure/printing.nix
#
# CUPS Printing Infrastructure
# Provides printing support with comprehensive driver packages
#
# DEPENDENCIES:
#   Upstream: None (standalone infrastructure)
#
# USED BY:
#   Downstream: profiles/workstation.nix (enables for desktop environments)
#   Downstream: machines/laptop/config.nix (may override drivers)
#
# IMPORTS REQUIRED IN:
#   - profiles/workstation.nix: ../domains/infrastructure/printing.nix
#
# USAGE:
#   hwc.infrastructure.hardware.peripherals.enable = true;
#   hwc.infrastructure.hardware.peripherals.drivers = [ "hplip" "gutenprint" ];  # Override defaults
#   hwc.infrastructure.hardware.peripherals.avahi = true;  # Enable network printer discovery
#
# VALIDATION:
#   - Requires desktop environment for GUI printer management tools

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.hardware.peripherals;
in {
  #============================================================================
  # IMPLEMENTATION - CUPS printing support
  #============================================================================
  
  config = lib.mkIf cfg.enable {
    # CUPS printing service
    services.printing = {
      enable = true;
      drivers = cfg.drivers;
    };
    
    # Network printer discovery
    services.avahi = lib.mkIf cfg.avahi {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
    
    # GUI management tools
    environment.systemPackages = lib.optionals cfg.guiTools (with pkgs; [
      cups                    # CUPS command line tools
      system-config-printer   # GUI printer configuration
    ]);
    
    # Declare firewall requirements through networking module
    hwc.networking.firewall = {
      extraTcpPorts = [ 631 ]; # CUPS web interface
      extraUdpPorts = lib.optionals cfg.avahi [ 5353 ]; # mDNS
    };
  };
}