{ config, pkgs, lib, ... }:
let
  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);
  cfgRoot = "/opt/downloads";
  paths = config.hwc.paths;
  hotRoot = "/mnt/hot";
in
{
  options.hwc.server.orchestration.mediaOrchestrator = {
    enable = lib.mkEnableOption "Media orchestrator service";
  };

  config = lib.mkIf config.hwc.server.orchestration.mediaOrchestrator.enable {
    systemd.services.media-orchestrator-install = {
      description = "Install media orchestrator assets";
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -e
        mkdir -p ${cfgRoot}/scripts ${hotRoot}/events

        # Deploy automation scripts from workspace
        cp /home/eric/.nixos/workspace/automation/media-orchestrator.py ${cfgRoot}/scripts/
        cp /home/eric/.nixos/workspace/automation/qbt-finished.sh ${cfgRoot}/scripts/
        cp /home/eric/.nixos/workspace/automation/sab-finished.py ${cfgRoot}/scripts/
        chmod +x ${cfgRoot}/scripts/*.py ${cfgRoot}/scripts/*.sh

        chown -R 1000:1000 ${cfgRoot}/scripts ${hotRoot}/events
        chmod 775 ${cfgRoot}/scripts ${hotRoot}/events
      '';
    };

    systemd.services.media-orchestrator = {
      description = "Event-driven *Arr nudger (no file moves)";
      after = [
        "network-online.target"
        "media-orchestrator-install.service"
        "podman-sonarr.service" "podman-radarr.service" "podman-lidarr.service"
      ];
      wantedBy = [ "multi-user.target" ];

      # Create environment file with agenix secrets
      preStart = ''
        # Read API keys from agenix secrets and create environment file
        cat > /tmp/media-orchestrator.env << EOF
SONARR_API_KEY=$(cat ${config.age.secrets.sonarr-api-key.path})
RADARR_API_KEY=$(cat ${config.age.secrets.radarr-api-key.path})
LIDARR_API_KEY=$(cat ${config.age.secrets.lidarr-api-key.path})
PROWLARR_API_KEY=$(cat ${config.age.secrets.prowlarr-api-key.path})
SONARR_URL=http://localhost:8989
RADARR_URL=http://localhost:7878
LIDARR_URL=http://localhost:8686
EOF
      '';

      serviceConfig = {
        Type = "simple";
        User = "root";
        EnvironmentFile = "/tmp/media-orchestrator.env";
        ExecStart = "${pythonWithRequests}/bin/python3 ${cfgRoot}/scripts/media-orchestrator.py";
        Restart = "always";
        RestartSec = "3s";
      };
    };
  };
}