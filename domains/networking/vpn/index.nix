# domains/networking/vpn/index.nix
#
# ProtonVPN via declarative WireGuard.
# Replaces the old protonvpn-cli flow (removed upstream in nixpkgs).
#
# Namespace: hwc.networking.vpn.*
# Private key: agenix secret `vpn-wireguard-private-key`
# Peer info (server pubkey, endpoint, client address) comes from the Proton
# WireGuard config you download at account.protonvpn.com/downloads.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.networking.vpn;
  proton = cfg.protonvpn;
  privateKeyFile = config.hwc.secrets.api."vpn-wireguard-private-key" or null;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.networking.vpn = {
    enable = lib.mkEnableOption "Enable VPN services";

    protonvpn = {
      enable = lib.mkEnableOption "Enable ProtonVPN via declarative WireGuard";

      autostart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Auto-connect at boot (wg-quick-protonvpn.service wantedBy multi-user.target)";
      };

      address = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "10.2.0.2/32" ];
        description = "Client address(es) from the [Interface] Address line of your Proton WG config";
      };

      dns = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "10.2.0.1" ];
        description = "DNS server(s) used while the tunnel is up (Proton default 10.2.0.1)";
      };

      peer = {
        publicKey = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Proton server public key from [Peer] PublicKey";
        };

        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "198.51.100.42:51820";
          description = "Proton server endpoint (host:port) from [Peer] Endpoint";
        };

        allowedIPs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "0.0.0.0/0" "::/0" ];
          description = "Routes to send into the tunnel (default: everything)";
        };

        persistentKeepalive = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = 25;
          description = "Keepalive interval in seconds";
        };
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf (cfg.enable && proton.enable) {

    networking.wg-quick.interfaces.protonvpn = {
      autostart = proton.autostart;
      address = proton.address;
      dns = proton.dns;
      privateKeyFile = privateKeyFile;
      peers = [{
        publicKey = proton.peer.publicKey;
        allowedIPs = proton.peer.allowedIPs;
        endpoint = proton.peer.endpoint;
        persistentKeepalive = proton.peer.persistentKeepalive;
      }];
    };

    # CLI tools for managing the tunnel
    environment.systemPackages = with pkgs; [ wireguard-tools ];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = privateKeyFile != null;
        message = "hwc.networking.vpn.protonvpn enabled but agenix secret 'vpn-wireguard-private-key' is not available.";
      }
      {
        assertion = proton.peer.publicKey != "";
        message = "Set hwc.networking.vpn.protonvpn.peer.publicKey from your Proton WG config ([Peer] PublicKey).";
      }
      {
        assertion = proton.peer.endpoint != "";
        message = "Set hwc.networking.vpn.protonvpn.peer.endpoint from your Proton WG config ([Peer] Endpoint).";
      }
      {
        assertion = proton.address != [];
        message = "Set hwc.networking.vpn.protonvpn.address from your Proton WG config ([Interface] Address).";
      }
    ];
  };
}
