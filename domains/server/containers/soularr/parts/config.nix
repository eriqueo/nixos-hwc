# soularr configuration file generator (config-only - container moved to sys.nix)
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.server.containers.soularr;
  cfgRoot = "/opt/downloads";
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
download_dir = /downloads/music

[Slskd]
host_url = http://slskd:5030
api_key = $SLSKD_API_KEY
download_dir = /downloads/music

[General]
interval = 300
EOF
        chmod 644 "$CONFIG_FILE"
        echo "Config file written successfully."
        echo "--- soularr-config seeder finished ---"
      '';
    };
  };
}
