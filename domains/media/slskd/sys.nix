{ lib, config, pkgs, ... }:
let
  # Import PURE helper library - no circular dependencies
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.slskd;
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Container definition using helper
    (helpers.mkContainer {
      name = "slskd";
      image = cfg.image;
      networkMode = cfg.network.mode;
      vpnContainer = cfg.vpnInstance;
      gpuEnable = false;  # slskd doesn't need GPU
      timeZone = config.time.timeZone or "UTC";
      # On the VPN, slskd has no interface of its own: the tunnel publishes its
      # web UI (see the instance's `ports`) and the Soulseek port arrives through
      # the tunnel's forwarded port, not through a host publish.
      ports = lib.optionals (cfg.network.mode != "vpn") [
        "127.0.0.1:5031:5030"                                       # Web UI (Caddy proxies to localhost)
        "0.0.0.0:${toString cfg.listenPort}:${toString cfg.listenPort}/tcp"  # P2P port
      ];
      volumes = [
        "${config.hwc.paths.hot.downloads}/incomplete:/downloads/incomplete"
        "${config.hwc.paths.hot.downloads}/music:/downloads/music"
        "${config.hwc.paths.media.music}:/music:ro"
        "/etc/slskd/slskd.yml:/app/slskd.yml:ro"
      ];
      environment = {};
      cmd = [ "--config" "/app/slskd.yml" ];
    })

    # Firewall for P2P — only meaningful off-VPN. Inside the tunnel the inbound
    # path is the forwarded port on the tunnel's own interface, and the host
    # firewall is not in it.
    {
      networking.firewall.allowedTCPPorts =
        lib.optionals (cfg.network.mode != "vpn") [ cfg.listenPort 5031 ];
    }

    # Service dependencies. bindsTo/partOf on the tunnel copies qBittorrent's
    # shape rather than slskd's old bare `after`: a container whose netns has
    # gone away must go away with it, not linger in an undefined network state.
    # It costs an slskd restart whenever the tunnel restarts, which is the right
    # trade — an in-flight transfer is worth less than a known egress.
    {
      systemd.services."podman-slskd" = {
        after = [ "network-online.target" "slskd-config-generator.service" "mnt-hot.mount" ]
          ++ (if cfg.network.mode == "vpn"
              then [ "podman-${cfg.vpnInstance}.service" ]
              else [ "init-media-network.service" ]);
        wants = [ "network-online.target" ]
          ++ lib.optional (cfg.network.mode == "vpn") "podman-${cfg.vpnInstance}.service";
        requires = [ "slskd-config-generator.service" "mnt-hot.mount" ];
        bindsTo = lib.optionals (cfg.network.mode == "vpn") [ "podman-${cfg.vpnInstance}.service" ];
        partOf = lib.optionals (cfg.network.mode == "vpn") [ "podman-${cfg.vpnInstance}.service" ];
      };
    }
  ]);
}
