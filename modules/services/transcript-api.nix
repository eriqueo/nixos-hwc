{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.transcriptApi;
  paths = config.hwc.paths;
in {
  options.hwc.services.transcriptApi = {
    enable = lib.mkEnableOption "YouTube transcript API";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "API port";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/transcript-api";
      description = "Data directory";
    };
    
    apiKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "YouTube API keys";
    };
  };
  
  config = lib.mkIf cfg.enable {
    systemd.services.transcript-api = {
      description = "YouTube Transcript API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      
      environment = {
        API_PORT = toString cfg.port;
        DATA_DIR = cfg.dataDir;
      };
      
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python /etc/nixos/scripts/yt_transcript.py";
        Restart = "always";
        StateDirectory = "hwc/transcript-api";
        DynamicUser = true;
      };
    };
    
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
