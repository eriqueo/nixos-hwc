# nixos-h../domains/services/transcript-api.nix
#
# TRANSCRIPT API - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.transcript-api.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/transcript-api.nix
#
# USAGE:
#   hwc.services.transcript-api.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.transcriptApi;
  paths = config.hwc.paths;
  scriptPath = "${paths.nixos}/scripts/yt_transcript.py";
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
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
  

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
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
        ExecStart = "${pkgs.python3}/bin/python ${scriptPath}";
        Restart = "always";
        StateDirectory = "hwc/transcript-api";
        DynamicUser = true;
      };
    };
    
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
