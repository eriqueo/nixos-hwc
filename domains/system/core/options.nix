# domains/system/core/options.nix
#
# Consolidated options for system core subdomain
# Charter-compliant: ALL core options defined here

{ lib, ... }:

{
  #============================================================================
  # POLKIT OPTIONS
  #============================================================================
  options.hwc.system.core.polkit = {
    enable = lib.mkEnableOption "polkit directory management";

    createMissingDirectories = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create missing polkit rule directories to silence warnings";
    };
  };

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
  # NETWORKING OPTIONS
  #============================================================================
  options.hwc.networking = {
    vlans = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "VLAN configurations";
      example = {
        management = { id = 10; interface = "eth0"; };
        storage = { id = 20; interface = "eth0"; };
      };
    };

    bridges = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "Bridge configurations";
    };

    staticRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Static routes";
    };

    dnsServers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "1.1.1.1" "8.8.8.8" ];
      description = "DNS servers";
    };

    search = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "local" ];
      description = "DNS search domains";
    };

    mtu = lib.mkOption {
      type = lib.types.int;
      default = 1500;
      description = "Default MTU";
    };
  };
}