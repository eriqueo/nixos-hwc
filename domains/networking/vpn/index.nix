# domains/networking/vpn/index.nix
#
# ProtonVPN via declarative WireGuard.
# Replaces the old protonvpn-cli flow (removed upstream in nixpkgs).
#
# Namespace: hwc.networking.vpn.*
# Private key: the agenix secret named by protonvpn.privateKeySecret. Each
# host needs its OWN Proton key: Proton allows one active session per key, so a
# key shared with another tunnel (e.g. hwc-server's gluetun) knocks one off.
# Peer info (server pubkey, endpoint, client address) comes from the Proton
# WireGuard config you download at account.protonvpn.com/downloads.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.networking.vpn;
  proton = cfg.protonvpn;
  privateKeyFile = config.hwc.secrets.api.${proton.privateKeySecret} or null;

  # Tailscale bypass rules. wg-quick installs `not fwmark 0xca6c lookup 51820`
  # just below Tailscale's lowest rule (5210), i.e. ahead of Tailscale's
  # `lookup 52` (5270). Without these, tailnet traffic and tailscaled's own
  # fwmarked underlay packets go into the Proton tunnel and the tailnet is
  # unreachable while the VPN is up. Priorities 5200/5201 sit below both.
  ip = "${pkgs.iproute2}/bin/ip";
  tailnetRules = [
    "-4 rule %s priority 5200 to 100.64.0.0/10 lookup 52"
    "-6 rule %s priority 5200 to fd7a:115c:a1e0::/48 lookup 52"
    "-4 rule %s priority 5201 fwmark 0x80000/0xff0000 lookup main"
    "-6 rule %s priority 5201 fwmark 0x80000/0xff0000 lookup main"
  ];
  ruleCmds = verb: map (r: "${ip} ${lib.replaceStrings [ "%s" ] [ verb ] r}") tailnetRules;
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

      bypassTailscale = lib.mkOption {
        type = lib.types.bool;
        default = config.services.tailscale.enable;
        defaultText = lib.literalExpression "config.services.tailscale.enable";
        description = ''
          Keep tailnet traffic (100.64.0.0/10, fd7a:115c:a1e0::/48) and
          tailscaled's own packets off the tunnel, so the tailnet stays
          reachable while the VPN is up. All other traffic still uses Proton.
        '';
      };

      privateKeySecret = lib.mkOption {
        type = lib.types.str;
        default = "vpn-wireguard-private-key";
        description = ''
          Name of the agenix secret holding this host's WireGuard private key
          (the attribute under hwc.secrets.api, not a path). Give each host its
          own key: Proton allows one active session per key.
        '';
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
      postUp = lib.optionals proton.bypassTailscale (ruleCmds "add");
      postDown = lib.optionals proton.bypassTailscale (map (c: "${c} || true") (ruleCmds "del"));
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
        message = "hwc.networking.vpn.protonvpn enabled but agenix secret '${proton.privateKeySecret}' (protonvpn.privateKeySecret) is not available.";
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
