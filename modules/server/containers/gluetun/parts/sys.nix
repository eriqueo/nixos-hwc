{ lib, config, pkgs, ... }:
let
  shared = config.hwc.services.shared.lib;
  cfg = config.hwc.services.containers.gluetun;
  haveSecrets = (config.age.secrets ? vpn_user) && (config.age.secrets ? vpn_pass);
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (shared.mkContainer {
      name = "gluetun";
      image = cfg.image;
      networkMode = cfg.network.mode;
      gpuEnable = cfg.gpu.enable;
      ports = [];
      volumes = [ "/opt/downloads/gluetun:/gluetun" ];
      environment = { TZ = config.time.timeZone or "UTC"; };
      dependsOn = [];
      extraOptions = [ "--cap-add=NET_ADMIN" "--device=/dev/net/tun:/dev/net/tun" "--network=media-network" "--network-alias=gluetun" ];
    })

    (lib.mkIf haveSecrets {
      systemd.services.gluetun-env = {
        description = "Compose Gluetun .env from Agenix secrets";
        before = [ "podman-gluetun.service" ];
        wantedBy = [ "podman-gluetun.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          install -d -m 0700 -o root -g root /opt/downloads
          VPN_USER=$(cat ''${config.age.secrets.vpn_user.path})
          VPN_PASS=$(cat ''${config.age.secrets.vpn_pass.path})
          umask 177
          cat > /opt/downloads/.env <<ENVEOF
VPN_SERVICE_PROVIDER=protonvpn
VPN_TYPE=openvpn
OPENVPN_USER=$VPN_USER
OPENVPN_PASSWORD=$VPN_PASS
SERVER_COUNTRIES=Netherlands
HEALTH_VPN_DURATION_INITIAL=30s
ENVEOF
        '';
      };

      virtualisation.oci-containers.containers.gluetun = lib.mkMerge [
        {
          environmentFiles = [ "/opt/downloads/.env" ];
          ports = [ "127.0.0.1:8080:8080" "127.0.0.1:8081:8085" ];
        }
      ];
    })
  ]);
}
