# soularr Soulseek integration container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.soularr;
  cfgRoot = "/opt/downloads";
  hotRoot = "/mnt/hot";
  mediaNetworkName = "media-network";
in
{
  config = lib.mkIf cfg.enable {
    # Soularr config file generation from agenix secrets
    systemd.services.soularr-config = {
      description = "Seed Soularr /data/config.ini from agenix secrets";
      wantedBy = [ "podman-soularr.service" ];
      before = [ "podman-soularr.service" ];
      after = [ "agenix.service" ];
      wants = [ "agenix.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        echo "--- Running soularr-config seeder (Charter Version) ---"

        CONFIG_FILE="${cfgRoot}/soularr/config.ini"

        # Remove old config file to ensure changes are applied
        echo "Removing old config file at $CONFIG_FILE..."
        rm -f "$CONFIG_FILE"

        # Get API keys from agenix secrets
        LIDARR_API_KEY=$(cat ${config.age.secrets.lidarr-api-key.path})
        SLSKD_API_KEY=$(cat ${config.age.secrets.slskd-api-key.path})

        echo "DEBUG: LIDARR Key found: $([ -n "$LIDARR_API_KEY" ] && echo 'yes' || echo 'no')"
        echo "DEBUG: SLSKD Key found:  $([ -n "$SLSKD_API_KEY" ] && echo 'yes' || echo 'no')"

        mkdir -p "${cfgRoot}/soularr"
        echo "Writing new config file to $CONFIG_FILE..."

        # Generate config.ini with API keys
        cat > "$CONFIG_FILE" <<EOF
[Lidarr]
host_url = http://lidarr:8686/lidarr
api_key = $LIDARR_API_KEY
download_dir = /downloads/music/complete

[Slskd]
host_url = http://slskd:5030
api_key = $SLSKD_API_KEY
download_dir = /downloads/music/complete

[General]
interval = 300
EOF
        chmod 644 "$CONFIG_FILE"
        echo "Config file written successfully."
        echo "--- soularr-config seeder finished ---"
      '';
    };

    # Container definition
    virtualisation.oci-containers.containers.soularr = {
      image = cfg.image;
      autoStart = true;
      extraOptions = [
        "--network=${mediaNetworkName}"
        "--memory=1g"
        "--cpus=0.5"
      ];
      volumes = [
        "${cfgRoot}/soularr:/config"
        "${cfgRoot}/soularr:/data"
        "${hotRoot}/downloads:/downloads"
      ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = config.time.timeZone or "America/Denver";
      };
      dependsOn = [ "lidarr" ];
    };

    # Service dependencies and timing
    systemd.services."podman-soularr" = {
      after = [ "init-media-network.service" "podman-lidarr.service" "podman-slskd.service" ];
      requires = [ "podman-lidarr.service" ];
      serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-lidarr" ''
        for i in 1 1 2 3 5 8; do
          if ${pkgs.curl}/bin/curl -sf -H "X-Api-Key: $(cat ${config.age.secrets.lidarr-api-key.path})" \
            "http://localhost:8686/lidarr/api/v1/system/status" >/dev/null 2>&1; then
            echo "Lidarr is ready"
            exit 0
          fi
          echo "Waiting for Lidarr... ($i)"
          sleep $i
        done
        echo "Lidarr failed to become ready"
        exit 1
      '';
    };
  };
}
