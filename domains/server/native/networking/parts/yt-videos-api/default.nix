# domains/server/native/networking/parts/yt-videos-api/index.nix
#
# YOUTUBE VIDEOS API - Video download and archiving REST API with worker
# Provides async job-based video downloads from YouTube with atomic finalization
#
# ARCHITECTURE:
#   - API Server: FastAPI with --workers 1 (single process)
#   - Worker: Separate background downloader (independent systemd unit)
#   - Database: PostgreSQL with yt_videos schema
#   - Atomic Finalization: Staging area with filesystem-aware atomic moves
#   - Deduplication: Global downloads table prevents re-downloads
#
# DEPENDENCIES:
#   - PostgreSQL (hwc.services.databases.postgresql)
#   - yt-dlp (for downloads)
#   - ffmpeg-full (for metadata embedding)
#   - YouTube API key (optional, for playlist expansion)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.ytVideosApi;
  paths = config.hwc.paths;

  # Build Python packages with repo-relative paths
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

    doCheck = false;
  };

  yt-videos-api = pkgs.python3Packages.buildPythonPackage {
    pname = "yt-videos-api";
    version = "0.1.0";
    src = lib.cleanSource "${paths.nixos}/workspace/projects/youtube-services/packages/yt_videos_api";
    format = "pyproject";

    propagatedBuildInputs = with pkgs.python3Packages; [
      yt-core
      fastapi
      uvicorn
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
    yt-videos-api
    ps.alembic  # For migrations
  ]);

  # API server wrapper script
  apiWrapper = pkgs.writeShellScript "yt-videos-api-wrapper" ''
    set -euo pipefail

    # Load secrets from systemd credentials
    export YT_VIDEOS_DATABASE_URL="$(cat "$CREDENTIALS_DIRECTORY/db-url")"

    # YouTube API key is optional (only needed for playlist expansion)
    if [ -f "$CREDENTIALS_DIRECTORY/youtube-api-key" ]; then
      export YT_VIDEOS_YOUTUBE_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/youtube-api-key")"
    fi

    # Configuration from options
    export YT_VIDEOS_HOST="127.0.0.1"
    export YT_VIDEOS_PORT="${toString cfg.port}"
    export YT_VIDEOS_OUTPUT_DIRECTORY="${cfg.outputDirectory}"
    export YT_VIDEOS_STAGING_DIRECTORY="${cfg.stagingDirectory}"
    export YT_VIDEOS_CONTAINER_POLICY="${cfg.containerPolicy}"
    export YT_VIDEOS_QUALITY_PREFERENCE="${cfg.qualityPreference}"
    export YT_VIDEOS_EMBED_METADATA="${lib.boolToString cfg.embedMetadata}"
    export YT_VIDEOS_EMBED_COVER_ART="${lib.boolToString cfg.embedCoverArt}"
    export YT_VIDEOS_RATE_LIMIT_RPS="${toString cfg.rateLimit.requestsPerSecond}"
    export YT_VIDEOS_RATE_LIMIT_BURST="${toString cfg.rateLimit.burst}"
    export YT_VIDEOS_QUOTA_LIMIT="${toString cfg.rateLimit.quotaLimit}"

    # Run FastAPI with single worker (worker runs separately)
    exec ${pythonEnv}/bin/uvicorn yt_videos_api.main:app \
      --host "$YT_VIDEOS_HOST" \
      --port "$YT_VIDEOS_PORT" \
      --workers 1 \
      --log-level info
  '';

  # Worker process wrapper script
  workerWrapper = pkgs.writeShellScript "yt-videos-worker-wrapper" ''
    set -euo pipefail

    # Load secrets
    export YT_VIDEOS_DATABASE_URL="$(cat "$CREDENTIALS_DIRECTORY/db-url")"

    if [ -f "$CREDENTIALS_DIRECTORY/youtube-api-key" ]; then
      export YT_VIDEOS_YOUTUBE_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/youtube-api-key")"
    fi

    # Configuration
    export YT_VIDEOS_OUTPUT_DIRECTORY="${cfg.outputDirectory}"
    # Note: stagingDirectory is deprecated and auto-derived from outputDirectory
    export YT_VIDEOS_CONTAINER_POLICY="${cfg.containerPolicy}"
    export YT_VIDEOS_QUALITY_PREFERENCE="${cfg.qualityPreference}"
    export YT_VIDEOS_EMBED_METADATA="${lib.boolToString cfg.embedMetadata}"
    export YT_VIDEOS_EMBED_COVER_ART="${lib.boolToString cfg.embedCoverArt}"
    export YT_VIDEOS_WORKERS="${toString cfg.workers}"
    export YT_VIDEOS_RATE_LIMIT_RPS="${toString cfg.rateLimit.requestsPerSecond}"
    export YT_VIDEOS_RATE_LIMIT_BURST="${toString cfg.rateLimit.burst}"
    export YT_VIDEOS_QUOTA_LIMIT="${toString cfg.rateLimit.quotaLimit}"

    # Ensure yt-dlp and ffmpeg are in PATH
    export PATH="${pkgs.yt-dlp}/bin:${pkgs.ffmpeg-full}/bin:$PATH"

    # Run worker
    exec ${pythonEnv}/bin/python3 -m yt_videos_api.worker
  '';

  # Database setup script (runs Alembic migrations)
  setupScript = pkgs.writeShellScript "yt-videos-setup" ''
    set -euo pipefail

    echo "[yt-videos-api-setup] Running database migrations..."

    # Load database URL
    export DATABASE_URL="$(cat "$CREDENTIALS_DIRECTORY/db-url")"

    # Run Alembic migrations
    cd ${paths.nixos}/workspace/projects/youtube-services/packages/yt_videos_api/migrations
    ${pythonEnv}/bin/alembic upgrade head

    echo "[yt-videos-api-setup] Migrations complete"
  '';

in
{
  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Database setup service (runs migrations before API/worker start)
    systemd.services.yt-videos-api-setup = {
      description = "YouTube Videos API Database Setup";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" ];
      before = [ "yt-videos-api.service" "yt-videos-worker.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setupScript;
        User = "yt-videos-api";
        Group = "yt-videos-api";
        StateDirectory = "hwc/yt-videos-api";
        LoadCredential = [
          "db-url:${config.age.secrets.youtube-videos-db-url.path}"
        ];
      };
    };

    # API server service (FastAPI with --workers 1)
    systemd.services.yt-videos-api = {
      description = "YouTube Videos API Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "yt-videos-api-setup.service" ];
      requires = [ "yt-videos-api-setup.service" ];

      serviceConfig = {
        Type = "exec";
        ExecStart = apiWrapper;
        Restart = "always";
        User = "yt-videos-api";
        Group = "yt-videos-api";
        SupplementaryGroups = [ "secrets" ];
        StateDirectory = "hwc/yt-videos-api";

        # Load credentials via systemd LoadCredential
        LoadCredential = [
          "db-url:${config.age.secrets.youtube-videos-db-url.path}"
        ] ++ lib.optional (config.age.secrets.youtube-api-key or null != null)
          "youtube-api-key:${config.age.secrets.youtube-api-key.path}";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.outputDirectory ];  # Staging is <output>/.staging
      };
    };

    # Worker service (separate process, processes download jobs)
    systemd.services.yt-videos-worker = {
      description = "YouTube Videos Download Worker";
      wantedBy = [ "multi-user.target" ];
      after = [ "postgresql.service" "yt-videos-api-setup.service" ];
      requires = [ "yt-videos-api-setup.service" ];

      serviceConfig = {
        Type = "exec";
        ExecStart = workerWrapper;
        Restart = "always";
        User = "yt-videos-api";
        Group = "yt-videos-api";
        SupplementaryGroups = [ "secrets" ];
        StateDirectory = "hwc/yt-videos-api";

        LoadCredential = [
          "db-url:${config.age.secrets.youtube-videos-db-url.path}"
        ] ++ lib.optional (config.age.secrets.youtube-api-key or null != null)
          "youtube-api-key:${config.age.secrets.youtube-api-key.path}";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.outputDirectory ];  # Staging is <output>/.staging

        # Higher niceness for download worker (lower priority)
        Nice = 5;
      };
    };

    # Create system user and group
    users.users.yt-videos-api = {
      isSystemUser = true;
      group = "yt-videos-api";
      extraGroups = [ "secrets" ];
      description = "YouTube Videos API service user";
    };

    users.groups.yt-videos-api = {};

    # Create output directory (staging is auto-created inside it)
    systemd.tmpfiles.rules = [
      "d ${cfg.outputDirectory} 0755 yt-videos-api yt-videos-api -"
    ];

    # Install yt-dlp and ffmpeg on the system (needed by worker)
    environment.systemPackages = [
      pkgs.yt-dlp
      pkgs.ffmpeg-full
    ];

    # Firewall rules (API port accessible on all interfaces)
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Also allow on Tailscale interface
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];

    # Validation assertions
    assertions = [
      {
        assertion = !cfg.enable || config.hwc.services.databases.postgresql.enable;
        message = "yt-videos-api requires PostgreSQL to be enabled";
      }
      {
        assertion = !cfg.enable || (config.age.secrets.youtube-videos-db-url or null != null);
        message = "yt-videos-api requires age.secrets.youtube-videos-db-url to be configured";
      }
    ];
  };
}
