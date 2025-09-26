# nixos-h../domains/system/services/vpn/index.nix
#
# VPN IMPLEMENTATION - ProtonVPN WireGuard service
# System domain module providing ProtonVPN connectivity via WireGuard
#
# DEPENDENCIES (Upstream):
#   - domains/system/services/vpn/options.nix (API definition)
#
# USED BY (Downstream):
#   - profiles/system.nix (imports this module)
#
# IMPORTS REQUIRED IN:
#   - profiles/system.nix: ../domains/system/services/vpn
#
# USAGE:
#   hwc.system.services.vpn.enable = true;
#   hwc.system.services.vpn.protonvpn.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.services.vpn;
in
{
  #============================================================================
  # IMPORTS - Module structure
  #============================================================================
  imports = [
    ./options.nix
  ];

  #============================================================================
  # IMPLEMENTATION - VPN service configuration
  #============================================================================
  config = lib.mkIf cfg.enable {
    
    # WireGuard kernel module and tools
    networking.wireguard.enable = true;
    
    # System packages for VPN management
    environment.systemPackages = with pkgs; [
      wireguard-tools
    ];

    # ProtonVPN WireGuard interface configuration
    networking.wg-quick.interfaces = lib.mkIf cfg.protonvpn.enable {
      protonvpn = {
        address = [ cfg.protonvpn.address ];
        dns = [ cfg.protonvpn.dns ];
        privateKey = cfg.protonvpn.privateKey;
        
        peers = [{
          publicKey = cfg.protonvpn.publicKey;
          endpoint = cfg.protonvpn.endpoint;
          allowedIPs = [ "0.0.0.0/0" "::/0" ];
          persistentKeepalive = cfg.protonvpn.persistentKeepalive;
        }];
      };
    };

    # Firewall configuration for WireGuard
    networking.firewall = lib.mkIf cfg.protonvpn.enable {
      allowedUDPPorts = [ 51820 ];
    };

    # Enable IP forwarding for VPN routing
    boot.kernel.sysctl = lib.mkIf cfg.protonvpn.enable {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # Passwordless sudo for VPN commands
    security.sudo.extraRules = lib.mkIf cfg.protonvpn.enable [{
      users = [ "eric" ];
      commands = [{
        command = "${pkgs.wireguard-tools}/bin/wg-quick";
        options = [ "NOPASSWD" ];
      } {
        command = "${pkgs.wireguard-tools}/bin/wg";
        options = [ "NOPASSWD" ];
      }];
    }];
  };

  #============================================================================
  # VALIDATION - Ensure proper configuration
  #============================================================================
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.protonvpn.enable -> (cfg.protonvpn.privateKey != "");
        message = "ProtonVPN private key must be configured when enabled";
      }
      {
        assertion = cfg.protonvpn.enable -> (cfg.protonvpn.endpoint != "");
        message = "ProtonVPN endpoint must be configured when enabled";
      }
    ];
  };
}