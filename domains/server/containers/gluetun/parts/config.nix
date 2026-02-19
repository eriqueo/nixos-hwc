# gluetun container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.gluetun;
  appsRoot = config.hwc.paths.apps.root;
  cfgRoot = "${appsRoot}/gluetun";
  mediaNetworkName = "media-network";
in
{
  config = lib.mkIf cfg.enable {
    # Gluetun environment file setup from agenix secrets
    systemd.services.gluetun-env-setup = {
      description = "Generate Gluetun env from agenix secrets";
      before   = [ "podman-gluetun.service" ];
      wantedBy = [ "podman-gluetun.service" ];
      wants    = [ "agenix.service" ];
      after    = [ "agenix.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        mkdir -p ${cfgRoot}
        WG_PRIVATE_KEY=$(cat ${config.age.secrets.vpn-wireguard-private-key.path})
        cat > ${cfgRoot}/.env <<EOF
# WireGuard config for ProtonVPN P2P server (US-UT#52)
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=$WG_PRIVATE_KEY
WIREGUARD_ADDRESSES=10.2.0.2/32
WIREGUARD_PUBLIC_KEY=fDSDNxB7yfHbaemo7cAFMWBsEm31bVAAradL4hbBEG0=
WIREGUARD_ENDPOINT_IP=74.63.204.210
WIREGUARD_ENDPOINT_PORT=51820
WIREGUARD_PERSISTENT_KEEPALIVE_INTERVAL=25s
HEALTH_VPN_DURATION_INITIAL=30s
HEALTH_TARGET_ADDRESS=1.1.1.1:443
EOF
        chmod 600 ${cfgRoot}/.env
        chown root:root ${cfgRoot}/.env
      '';
    };

    # Container definition
    virtualisation.oci-containers.containers.gluetun = {
      image = cfg.image;
      autoStart = true;
      extraOptions = [
        "--cap-add=NET_ADMIN"
        "--cap-add=SYS_MODULE"
        "--device=/dev/net/tun:/dev/net/tun"
        "--network=${mediaNetworkName}"
        "--network-alias=gluetun"
        "--privileged"
      ];
      ports = [
        "127.0.0.1:8080:8080"  # qBittorrent UI (Caddy proxies to localhost)
        "127.0.0.1:8081:8085"  # SABnzbd (container uses 8085 internally)
        "127.0.0.1:5010:5010"  # Mousehole (MAM IP updater)
      ];
      volumes = [ "${cfgRoot}:/gluetun" ];
      environmentFiles = [ "${cfgRoot}/.env" ];
      environment = {
        TZ = config.time.timeZone or "America/Denver";
        DOT = "off";  # Disable DNS over TLS - was causing timeouts and slow downloads
        DNS_ADDRESS = "1.1.1.1";  # Use Cloudflare DNS
      };
    };

    # Service dependencies
    systemd.services."podman-gluetun".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-gluetun".wants = [ "network-online.target" ];
  };
}
