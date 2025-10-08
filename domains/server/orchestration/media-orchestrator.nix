{ config, pkgs, lib, ... }:
let
  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);
  cfgRoot = "/opt/downloads";
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
        "sops-install-secrets.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        User = "root";
        EnvironmentFile = "${config.sops.secrets.arr_api_keys_env.path}";
        Environment = [
          "SONARR_URL=http://localhost:8989"
          "RADARR_URL=http://localhost:7878"
          "LIDARR_URL=http://localhost:8686"
        ];
        ExecStart = "${pythonWithRequests}/bin/python3 ${cfgRoot}/scripts/media-orchestrator.py";
        Restart = "always";
        RestartSec = "3s";
      };
    };
  };
}