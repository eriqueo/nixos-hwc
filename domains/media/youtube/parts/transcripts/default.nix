# domains/media/youtube/parts/transcripts/default.nix
#
# YOUTUBE TRANSCRIPTS API — single FastAPI service for transcript extraction
#
# NAMESPACE: hwc.media.youtube.transcripts.*
#
# ARCHITECTURE:
#   - Single FastAPI process
#   - youtube-transcript-api for captions, yt-dlp for metadata only
#   - No LLM, no spaCy, no PostgreSQL
#   - Caddy vhost at transcripts.hwc.iheartwoodcraft.com (upstream 127.0.0.1:8100)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.media.youtube.transcripts;
  paths = config.hwc.paths;

  scriptDir = "${paths.nixos}/workspace/media/youtube-services";

  pythonPackages = with pkgs.python3Packages; [
    fastapi
    uvicorn
    pydantic
    youtube-transcript-api
  ];

  pythonPath = pkgs.python3Packages.makePythonPath pythonPackages;

  # The set of writable save locations, default first. Sandbox writability
  # (ReadWritePaths) and the UI dropdown both derive from this one list.
  outputRoots = lib.unique ([ cfg.outputDirectory ] ++ cfg.outputRoots);

  apiWrapper = pkgs.writeShellScript "transcripts-wrapper" ''
    set -euo pipefail

    export PYTHONPATH="${pythonPath}:${scriptDir}"
    export PATH="${pkgs.yt-dlp}/bin:$PATH"
    export YT_TRANSCRIPTS_HOST="127.0.0.1"
    export YT_TRANSCRIPTS_PORT="${toString cfg.port}"
    export YT_TRANSCRIPTS_OUTPUT_DIR="${cfg.outputDirectory}"
    export YT_TRANSCRIPTS_OUTPUT_ROOTS="${lib.concatStringsSep ":" (map toString outputRoots)}"
    export YT_TRANSCRIPTS_DEFAULT_MODE="${cfg.defaultFormat}"
    export YT_TRANSCRIPTS_LANGUAGES="${lib.concatStringsSep "," cfg.languages}"

    exec ${pkgs.python3}/bin/python3 ${scriptDir}/api.py
  '';

  # n8n integration script — calls HTTP API
  n8nScript = pkgs.writeShellScriptBin "n8n-transcript-extract" ''
    set -euo pipefail

    YOUTUBE_URL="''${1:?YouTube URL is required}"
    MODE="''${2:-clean}"
    JOB_ID="''${3:-txn-$(date +%s)-$(${pkgs.openssl}/bin/openssl rand -hex 3)}"

    API_RESPONSE=$(${pkgs.curl}/bin/curl -sf --max-time 35 -X POST \
      http://127.0.0.1:${toString cfg.port}/transcript \
      -H "Content-Type: application/json" \
      -d "{\"url\": \"$YOUTUBE_URL\", \"mode\": \"$MODE\"}")

    echo "STATUS=success"
    echo "JOB_ID=$JOB_ID"
    echo "TITLE=$(echo "$API_RESPONSE" | ${pkgs.jq}/bin/jq -r .title)"
    echo "EXTRACTED_FILE=$(echo "$API_RESPONSE" | ${pkgs.jq}/bin/jq -r .filename)"
    echo "TIMESTAMP=$(date -Iseconds)"
  '';

in
{
  config = lib.mkIf cfg.enable {

    systemd.services.transcripts = {
      description = "YouTube Transcripts API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "exec";
        ExecStart = apiWrapper;
        Restart = "always";
        RestartSec = 5;

        # Run as eric (owns output dirs)
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";

        StateDirectory = "hwc/transcripts";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        # Grant write access to every whitelisted save location, not just the
        # default — the UI lets the user pick any of these as the base.
        ReadWritePaths = outputRoots;
      };
    };

    # Ensure every save-location root exists
    systemd.tmpfiles.rules = map (d: "d ${toString d} 0755 eric users -") outputRoots;

    # Provide n8n integration script system-wide
    environment.systemPackages = [ n8nScript ];
  };
}
