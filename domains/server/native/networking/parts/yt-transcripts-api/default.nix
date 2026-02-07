# domains/server/native/networking/parts/yt-transcripts-api/index.nix
#
# YOUTUBE TRANSCRIPTS API - Transcript extraction REST API with worker
# Provides async job-based transcript extraction from YouTube videos/playlists/channels
#
# ARCHITECTURE:
#   - API Server: FastAPI with --workers 1 (single process)
#   - Worker: Separate background processor (independent systemd unit)
#   - Database: PostgreSQL with yt_transcripts schema
#   - Deduplication: Global transcripts table prevents re-extraction
#
# DEPENDENCIES:
#   - PostgreSQL (hwc.services.databases.postgresql)
#   - YouTube API key (optional, for playlist expansion)
#   - yt_core and yt_transcripts_api Python packages

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.ytTranscriptsApi;
  paths = config.hwc.paths;

  # Build Python packages with repo-relative paths for reproducibility
  yt-core = pkgs.python3Packages.buildPythonPackage {
    pname = "yt-core";
    version = "0.1.0";
    src = lib.cleanSource "${paths.nixos}/workspace/projects/youtube-services/packages/yt_core";
    format = "pyproject";

    propagatedBuildInputs = with pkgs.python3Packages; [
      sqlalchemy
      asyncpg
      alembic
      pydantic
      pydantic-settings
      google-api-python-client
      httpx
      structlog
    ];

    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    # Skip tests during build (run separately if needed)
    doCheck = false;
  };

  yt-transcripts-api = pkgs.python3Packages.buildPythonPackage {
    pname = "yt-transcripts-api";
    version = "0.1.0";
    src = lib.cleanSource "${paths.nixos}/workspace/projects/youtube-services/packages/yt_transcripts_api";
    format = "pyproject";

    propagatedBuildInputs = with pkgs.python3Packages; [
      yt-core
      fastapi
      uvicorn
      youtube-transcript-api
      python-slugify
    ];

    nativeBuildInputs = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    doCheck = false;
  };

  # Python environment with all dependencies
  pythonEnv = pkgs.python3.withPackages (ps: [
    yt-core
    yt-transcripts-api
    ps.alembic  # For migrations
  ]);

  # API server wrapper script
  apiWrapper = pkgs.writeShellScript "yt-transcripts-api-wrapper" ''
    set -euo pipefail

    # Load secrets from systemd credentials
    export YT_TRANSCRIPTS_DATABASE_URL="$(cat "$CREDENTIALS_DIRECTORY/db-url")"

    # YouTube API key is optional (only needed for playlist expansion)
    if [ -f "$CREDENTIALS_DIRECTORY/youtube-api-key" ]; then
      export YT_TRANSCRIPTS_YOUTUBE_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/youtube-api-key")"
    fi

    # Configuration from options
    export YT_TRANSCRIPTS_HOST="127.0.0.1"
    export YT_TRANSCRIPTS_PORT="${toString cfg.port}"
    export YT_TRANSCRIPTS_OUTPUT_DIRECTORY="${cfg.outputDirectory}"
    export YT_TRANSCRIPTS_DEFAULT_OUTPUT_FORMAT="${cfg.defaultOutputFormat}"
    export YT_TRANSCRIPTS_RATE_LIMIT_RPS="${toString cfg.rateLimit.requestsPerSecond}"
    export YT_TRANSCRIPTS_RATE_LIMIT_BURST="${toString cfg.rateLimit.burst}"
    export YT_TRANSCRIPTS_QUOTA_LIMIT="${toString cfg.rateLimit.quotaLimit}"

    # Run FastAPI with single worker (worker runs separately)
    exec ${pythonEnv}/bin/uvicorn yt_transcripts_api.main:app \
      --host "$YT_TRANSCRIPTS_HOST" \
      --port "$YT_TRANSCRIPTS_PORT" \
      --workers 1 \
      --log-level info
  '';

  # Worker process wrapper script
  workerWrapper = pkgs.writeShellScript "yt-transcripts-worker-wrapper" ''
    set -euo pipefail

    # Load secrets
    export YT_TRANSCRIPTS_DATABASE_URL="$(cat "$CREDENTIALS_DIRECTORY/db-url")"

    if [ -f "$CREDENTIALS_DIRECTORY/youtube-api-key" ]; then
      export YT_TRANSCRIPTS_YOUTUBE_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/youtube-api-key")"
    fi

    # Configuration
    export YT_TRANSCRIPTS_OUTPUT_DIRECTORY="${cfg.outputDirectory}"
    export YT_TRANSCRIPTS_DEFAULT_OUTPUT_FORMAT="${cfg.defaultOutputFormat}"
    export YT_TRANSCRIPTS_WORKERS="${toString cfg.workers}"
    export YT_TRANSCRIPTS_RATE_LIMIT_RPS="${toString cfg.rateLimit.requestsPerSecond}"
    export YT_TRANSCRIPTS_RATE_LIMIT_BURST="${toString cfg.rateLimit.burst}"
    export YT_TRANSCRIPTS_QUOTA_LIMIT="${toString cfg.rateLimit.quotaLimit}"

    # Run worker
    exec ${pythonEnv}/bin/python3 -m yt_transcripts_api.worker
  '';

  # Database setup script (runs Alembic migrations)
  setupScript = pkgs.writeShellScript "yt-transcripts-setup" ''
    set -euo pipefail

    echo "[yt-transcripts-api-setup] Running database migrations..."

    # Load database URL
    export DATABASE_URL="$(cat "$CREDENTIALS_DIRECTORY/db-url")"

    # Run Alembic migrations
    cd ${paths.nixos}/workspace/projects/youtube-services/packages/yt_transcripts_api/migrations
    ${pythonEnv}/bin/alembic upgrade head

    echo "[yt-transcripts-api-setup] Migrations complete"
  '';

in
{
  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Database setup service (runs migrations before API/worker start)
    systemd.services.yt-transcripts-api-setup = {
      description = "YouTube Transcripts API Database Setup";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" ];
      before = [ "yt-transcripts-api.service" "yt-transcripts-worker.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setupScript;
        User = "yt-transcripts-api";
        Group = "yt-transcripts-api";
        StateDirectory = "hwc/yt-transcripts-api";
        LoadCredential = [
          "db-url:${config.age.secrets.youtube-transcripts-db-url.path}"
        ];
      };
    };

    # API server service (FastAPI with --workers 1)
    systemd.services.yt-transcripts-api = {
      description = "YouTube Transcripts API Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "yt-transcripts-api-setup.service" ];
      requires = [ "yt-transcripts-api-setup.service" ];

      serviceConfig = {
        Type = "exec";
        ExecStart = apiWrapper;
        Restart = "always";
        User = "yt-transcripts-api";
        Group = "yt-transcripts-api";
        SupplementaryGroups = [ "secrets" ];
        StateDirectory = "hwc/yt-transcripts-api";

        # Load credentials via systemd LoadCredential
        LoadCredential = [
          "db-url:${config.age.secrets.youtube-transcripts-db-url.path}"
        ] ++ lib.optional (config.age.secrets.youtube-api-key or null != null)
          "youtube-api-key:${config.age.secrets.youtube-api-key.path}";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.outputDirectory ];
      };
    };

    # Worker service (separate process, processes jobs)
    systemd.services.yt-transcripts-worker = {
      description = "YouTube Transcripts Worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "yt-transcripts-api-setup.service" ];
      requires = [ "yt-transcripts-api-setup.service" ];

      serviceConfig = {
        Type = "exec";
        ExecStart = workerWrapper;
        Restart = "always";
        User = "yt-transcripts-api";
        Group = "yt-transcripts-api";
        SupplementaryGroups = [ "secrets" ];
        StateDirectory = "hwc/yt-transcripts-api";

        LoadCredential = [
          "db-url:${config.age.secrets.youtube-transcripts-db-url.path}"
        ] ++ lib.optional (config.age.secrets.youtube-api-key or null != null)
          "youtube-api-key:${config.age.secrets.youtube-api-key.path}";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.outputDirectory ];
      };
    };

    # Create system user and group
    users.users.yt-transcripts-api = {
      isSystemUser = true;
      group = "yt-transcripts-api";
      extraGroups = [ "secrets" ];
      description = "YouTube Transcripts API service user";
    };

    users.groups.yt-transcripts-api = {};

    # Create output directory
    systemd.tmpfiles.rules = [
      "d ${cfg.outputDirectory} 0755 yt-transcripts-api yt-transcripts-api -"
    ];

    # Firewall rules (API port accessible on all interfaces)
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Also allow on Tailscale interface
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];

    # Validation assertions
    assertions = [
      {
        assertion = !cfg.enable || config.hwc.services.databases.postgresql.enable;
        message = "yt-transcripts-api requires PostgreSQL to be enabled";
      }
      {
        assertion = !cfg.enable || (config.age.secrets.youtube-transcripts-db-url or null != null);
        message = "yt-transcripts-api requires age.secrets.youtube-transcripts-db-url to be configured";
      }
    ];
  };
}
