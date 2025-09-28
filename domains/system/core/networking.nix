# HWC Charter Module/domains/infrastructure/networking.nix
#
# NETWORKING - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.infrastructure.networking.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/infrastructure/networking.nix
#
# USAGE:
#   hwc.infrastructure.networking.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.networking;
in {
  #============================================================================
  # OPTIONS - What can be configured
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


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = {
    # VLAN configuration
    networking.vlans = lib.mapAttrs (name: vlan: {
      id = vlan.id;
      interface = vlan.interface;
    }) cfg.vlans;

    # Bridge configuration
    networking.bridges = cfg.bridges;

    # DNS configuration
    networking = {
      nameservers = cfg.dnsServers;
      search = cfg.search;

      # Static routes
      interfaces.eth0.ipv4.routes = cfg.staticRoutes;
    };

    # Network optimization
    boot.kernel.sysctl = {
      # TCP optimization
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 87380 134217728";
      "net.ipv4.tcp_wmem" = "4096 65536 134217728";

      # Connection tracking
      "net.netfilter.nf_conntrack_max" = 262144;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 86400;
    };
  };
}
