# HWC Charter Module/domains/services/transcript-api.nix
#
# TRANSCRIPT API - YouTube transcript extraction REST API
# Provides a REST API for extracting transcripts from YouTube videos and playlists
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (modules/system/paths.nix)
#   - Python packages: fastapi, uvicorn, pydantic, httpx, yt-dlp, youtube-transcript-api, python-slugify, spacy, spacy-models.en_core_web_sm
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.services.transcriptApi.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/server.nix: ../domains/server/networking/parts/transcript-api.nix
#
# USAGE:
#   hwc.services.transcriptApi.enable = true;

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.transcriptApi;
  paths = config.hwc.paths;

  # Python environment with all required dependencies
  # Built manually with pkgs.buildEnv so we can set ignoreCollisions = true.
  # This avoids the typer / typer-slim duplicate-file error in python3.withPackages.
  pythonEnv = pkgs.buildEnv {
    name = "python3-transcript-api-env";
    paths = with pkgs.python3Packages; [
      pkgs.python3
      fastapi
      uvicorn
      pydantic
      httpx
      yt-dlp
      youtube-transcript-api
      python-slugify
      spacy
      spacy_models.en_core_web_sm
    ];
    pathsToLink = [ "/bin" "/lib" ];
    ignoreCollisions = true;
  };
  
  # Wrapper script that sets up proper Python environment
  startScript = pkgs.writeShellScript "transcript-api-start" ''
    export PYTHONPATH="${pythonEnv}/lib/python3.13/site-packages:${scriptDir}"
    exec ${pythonEnv}/bin/python3 ${apiScript} "$@"
  '';

  # Source directory for transcript scripts
  scriptDir = "${paths.nixos}/workspace/productivity/transcript-formatter";
  apiScript = "${scriptDir}/yt-transcript-api.py";
in
{
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.transcript-api = {
      description = "YouTube Transcript API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        API_HOST = "0.0.0.0";
        API_PORT = toString cfg.port;
        TRANSCRIPTS_ROOT = cfg.dataDir;
        LANGS = "en,en-US,en-GB";
        COUCHDB_URL = "http://127.0.0.1:5984";
        COUCHDB_DATABASE = "sync_transcripts";
      };

      serviceConfig = {
        ExecStart = "${startScript}";
        Restart = "always";
        StateDirectory = "hwc/transcript-api";
        DynamicUser = false;
        User = "root";  # Needs access to /mnt/media

        # Load CouchDB credentials from secrets
        LoadCredential = [
          "couchdb-username:${config.age.secrets.couchdb-admin-username.path}"
          "couchdb-password:${config.age.secrets.couchdb-admin-password.path}"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
