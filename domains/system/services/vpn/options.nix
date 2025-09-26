# nixos-h../domains/system/services/vpn/options.nix
#
# VPN OPTIONS - ProtonVPN WireGuard configuration options
# Following HWC charter namespace pattern: domains/system/services/vpn/ → hwc.system.services.vpn.*
#
# DEPENDENCIES (Upstream):
#   - None (standalone module)
#
# USED BY (Downstream):
#   - domains/system/services/vpn/index.nix (implements these options)
#   - profiles/system.nix (enables via hwc.system.services.vpn.enable)
#
# NAMESPACE: hwc.system.services.vpn.*

{ lib, ... }:

{
  #============================================================================
  # OPTIONS - VPN Configuration API
  #============================================================================
  options.hwc.system.services.vpn = {
    enable = lib.mkEnableOption "ProtonVPN WireGuard service";

    protonvpn = {
      enable = lib.mkEnableOption "ProtonVPN WireGuard configuration";

      privateKey = lib.mkOption {
        type = lib.types.str;
        default = "MIRyjxQtMGac3PoK3cVyw2FhyZqtRqXxfnGbnJYTGmY=";
        description = "WireGuard private key for ProtonVPN";
      };

      address = lib.mkOption {
        type = lib.types.str;
        default = "10.2.0.2/32";
        description = "VPN interface IP address";
      };

      dns = lib.mkOption {
        type = lib.types.str;
        default = "10.2.0.1";
        description = "DNS server for VPN";
      };

      publicKey = lib.mkOption {
        type = lib.types.str;
        default = "9f0svvw50qgvHun/0tZnApsgyF1OQSgc2Xd/4K5Hbzs=";
        description = "ProtonVPN server public key";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "68.169.42.239:51820";
        description = "ProtonVPN server endpoint";
      };

      persistentKeepalive = lib.mkOption {
        type = lib.types.int;
        default = 25;
        description = "Persistent keepalive interval in seconds";
      };
    };

    aliases = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable shell aliases for VPN control (vpnon, vpnoff, vpnstatus)";
      };
    };
  };
}