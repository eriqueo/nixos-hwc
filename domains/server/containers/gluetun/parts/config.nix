# gluetun container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.gluetun;
  cfgRoot = config.hwc.paths.hot.downloads;
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
        VPN_USERNAME=$(cat ${config.age.secrets.vpn-username.path})
        VPN_PASSWORD=$(cat ${config.age.secrets.vpn-password.path})
        cat > ${cfgRoot}/.env <<EOF
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=$VPN_USERNAME
OPENVPN_PASSWORD=$VPN_PASSWORD
SERVER_COUNTRIES=Netherlands
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
        "0.0.0.0:8080:8080"  # qBittorrent UI
        "0.0.0.0:8081:8085"  # SABnzbd (container uses 8085 internally)
      ];
      volumes = [ "${cfgRoot}/gluetun:/gluetun" ];
      environmentFiles = [ "${cfgRoot}/.env" ];
      environment = {
        TZ = config.time.timeZone or "America/Denver";
      };
    };

    # Service dependencies
    systemd.services."podman-gluetun".after = [ "network-online.target" "init-media-network.service" ];
    systemd.services."podman-gluetun".wants = [ "network-online.target" ];
  };
}
