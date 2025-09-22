# nixos-h../domains/services/vpn.nix
#
# VPN - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.vpn.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/vpn.nix
#
# USAGE:
#   hwc.services.vpn.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.vpn;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.services.vpn = {
    tailscale = {
      enable = lib.mkEnableOption "Tailscale VPN";

      authKeyFile = lib.mkOption {
        type = lib.types.path;
        description = "Path to auth key file";
      };

      exitNode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Act as exit node";
      };

      advertiseRoutes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Routes to advertise";
      };
    };

    wireguard = {
      enable = lib.mkEnableOption "WireGuard VPN";

      interfaces = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = {};
        description = "WireGuard interfaces";
      };
    };
  };


  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkMerge [
    (lib.mkIf cfg.tailscale.enable {
      services.tailscale = {
        enable = true;
        authKeyFile = cfg.tailscale.authKeyFile;
        useRoutingFeatures = if cfg.tailscale.exitNode then "both" else "client";
        extraUpFlags = cfg.tailscale.advertiseRoutes;
      };

      networking.firewall = {
        checkReversePath = "loose";
        trustedInterfaces = [ "tailscale0" ];
      };

      # Enable IP forwarding if exit node
      boot.kernel.sysctl = lib.mkIf cfg.tailscale.exitNode {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };
    })

    (lib.mkIf cfg.wireguard.enable {
      networking.wg-quick.interfaces = cfg.wireguard.interfaces;

      networking.firewall.allowedUDPPorts = [ 51820 ];
    })
  ];
}
