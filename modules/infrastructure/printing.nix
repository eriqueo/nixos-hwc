# nixos-hwc/modules/infrastructure/printing.nix
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
#   - profiles/profile.nix: ../modules/infrastructure/printing.nix
#
# USAGE:
#   hwc.infrastructure.printing.enable = true;
#   # TODO: Add specific usage examples

# nixos-hwc/modules/infrastructure/printing.nix
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
#   - profiles/workstation.nix: ../modules/infrastructure/printing.nix
#
# USAGE:
#   hwc.infrastructure.printing.enable = true;
#   hwc.infrastructure.printing.drivers = [ "hplip" "gutenprint" ];  # Override defaults
#   hwc.infrastructure.printing.avahi = true;  # Enable network printer discovery
#
# VALIDATION:
#   - Requires desktop environment for GUI printer management tools

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.printing;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  
  options.hwc.infrastructure.printing = {
    enable = lib.mkEnableOption "CUPS printing support with drivers";
    
    # Driver packages
    drivers = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        gutenprint     # High quality drivers for Canon, Epson, Lexmark, Sony, Olympus
        hplip          # HP Linux Imaging and Printing
        brlaser        # Brother laser printer driver
        brgenml1lpr    # Brother Generic LPR driver
        cnijfilter2    # Canon IJ Printer Driver
      ];
      description = "Printer driver packages to install";
    };
    
    # Network discovery
    avahi = lib.mkEnableOption "Avahi for network printer discovery";
    
    # GUI tools
    guiTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install GUI printer management tools";
    };
  };
  
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
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
    
    # Firewall rules for printing
    networking.firewall = {
      allowedTCPPorts = [ 631 ]; # CUPS web interface
      allowedUDPPorts = lib.optionals cfg.avahi [ 5353 ]; # mDNS
    };
  };
}