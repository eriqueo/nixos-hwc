# domains/server/native/ai/home-scout/index.nix
#
# Home Scout — real estate intelligence pipeline (lead_scout sibling).
#
# Three parts:
#   1. home-scout.service — unified HTTP + MCP server on port 8421
#      (classify sweeps / notify / digest crons run in-process via node-cron)
#   2. systemd timers running the Python ingesters (homeharvest daily,
#      cadastral + redfin monthly) from <projectDir>/ingest
#   3. Postgres database `home_scout` on the shared instance
#
# Notifications go to the hwc-notify loopback dispatcher (:11600/notify) —
# no webhook secrets needed.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.ai.homeScout;
  node = "/run/current-system/sw/bin/node";
  tsx  = "${cfg.workspaceRoot}/node_modules/tsx/dist/cli.mjs";
  cli  = "${cfg.projectDir}/src/cli.ts";

  # homeharvest is not in nixpkgs; pure-python wheel with nixpkgs-available deps.
  homeharvest = pkgs.python3Packages.buildPythonPackage rec {
    pname = "homeharvest";
    version = "0.8.18";
    format = "wheel";
    src = pkgs.fetchPypi {
      inherit pname version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      sha256 = "87bcca5313e8ecf51e48c588d8dd370426c859349d8f9c88f3a515edfde09ae9";
    };
    propagatedBuildInputs = with pkgs.python3Packages; [
      pandas
      pydantic
      requests
      tenacity
    ];
    doCheck = false;
  };

  ingestPython = pkgs.python3.withPackages (ps: [
    homeharvest
    ps.psycopg
    ps.requests
  ]);

  ingestToml = pkgs.writeText "home-scout-ingest.toml" ''
    [harvest]
    locations = [ ${lib.concatMapStringsSep ", " (l: ''"${l}"'') cfg.locations} ]
    past_days = 3
    sold_past_days = 30
    stale_after_days = 2

    [cadastral]
    counties = [ ${lib.concatMapStringsSep ", " (c: ''"${c}"'') cfg.counties} ]

    [redfin]
    regions = [ ${lib.concatMapStringsSep ", " (r: ''"${r}"'') cfg.redfinRegions} ]
  '';

  ingestEnv = {
    DATABASE_URL = cfg.databaseUrl;
    HOMESCOUT_INGEST_CONFIG = "${ingestToml}";
    PYTHONPATH = "${cfg.projectDir}/ingest";
  };

  ingestServiceDefaults = {
    Type = "oneshot";
    User = cfg.user;
    WorkingDirectory = "${cfg.projectDir}/ingest";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = "read-only";
  };

  # Deploys use the standard `deploy` dispatcher (domains/server/deploy) via
  # the repo's own deploy.sh — no inline deploy command here (the lead-scout
  # inline variant is the superseded legacy pattern).
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.ai.homeScout = {
    enable = lib.mkEnableOption "Home Scout real estate intelligence pipeline";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8421;
      description = "Port the Home Scout HTTP/MCP server listens on";
    };

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/600_apps/home_scout";
      description = "Path to the home_scout project directory";
    };

    workspaceRoot = lib.mkOption {
      type = lib.types.path;
      default = cfg.projectDir;
      description = ''
        Root whose node_modules carries hoisted tooling (tsx). Equal to
        projectDir for a standalone checkout; the monorepo root when
        projectDir is an app inside the scout workspace.
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://home_scout@localhost/home_scout";
      description = "PostgreSQL connection string";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "User to run the service and ingest timers as";
    };

    notifyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11600";
      description = "hwc-notify dispatcher base URL (POSTs to /notify)";
    };

    locations = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Bozeman, MT" "Belgrade, MT" "Livingston, MT" ];
      description = "HomeHarvest locations fetched by the daily harvest timer";
    };

    counties = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Gallatin" "Park" ];
      description = "Montana counties for the monthly cadastral parcel load";
    };

    redfinRegions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Bozeman, MT" "Belgrade, MT" "Livingston, MT" ];
      description = "Redfin city regions kept from the monthly market tracker load";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Database on the shared Postgres instance
    services.postgresql = {
      ensureDatabases = [ "home_scout" ];
      ensureUsers = [{
        name = "home_scout";
        ensureDBOwnership = true;
      }];
    };

    # Local (peer/ident) access for the service user running as `eric` via
    # DATABASE_URL role home_scout requires a password-less local grant; the
    # role is LOGIN by ensureUsers. Allow eric to connect as home_scout over
    # localhost trust is NOT set up here — the app connects as home_scout via
    # unix socket only if user matches. Keep it simple: grant the eric role
    # membership in home_scout so peer auth works with role switching.
    systemd.services.postgresql.postStart = lib.mkAfter ''
      $PSQL -tAc 'GRANT home_scout TO ${cfg.user}' || true
    '';

    #--------------------------------------------------------------------------
    # Unified server
    #--------------------------------------------------------------------------
    systemd.services.home-scout = {
      description = "Home Scout MCP + HTTP Server";
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        DATABASE_URL = cfg.databaseUrl;
        LOG_LEVEL = "info";
        NODE_ENV = "production";
        HWC_NOTIFY_URL = cfg.notifyUrl;
        # The classifier shells out to the `claude` CLI (lead_scout precedent:
        # unit PATH carries only nodejs, so the binary must be declared).
        CLAUDE_BIN = "/etc/profiles/per-user/${cfg.user}/bin/claude";
        # Hardened unit must never write frontend/dist — deploy prebuilds it.
        SKIP_FRONTEND_BUILD = "1";
      };

      path = [ pkgs.nodejs ];

      serviceConfig = {
        Type             = "simple";
        ExecStart        = "${node} ${tsx} ${cli} serve --port ${toString cfg.port}";
        WorkingDirectory = cfg.projectDir;
        User             = cfg.user;
        Restart          = "on-failure";
        RestartSec       = "5s";

        NoNewPrivileges        = true;
        PrivateTmp             = true;
        ProtectSystem          = "strict";
        ProtectHome            = "read-only";
        ProtectKernelTunables  = true;
        ProtectKernelModules   = true;
        ProtectControlGroups   = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces     = true;
        RestrictRealtime       = true;
        RestrictSUIDSGID       = true;
        LockPersonality        = true;

        ReadWritePaths = [ "/tmp" ];
      };
    };

    #--------------------------------------------------------------------------
    # Ingest timers (Python, working-tree deploy like the node service)
    #--------------------------------------------------------------------------
    systemd.services.home-scout-harvest = {
      description = "Home Scout daily HomeHarvest ingest";
      after = [ "network-online.target" "postgresql.service" ];
      environment = ingestEnv;
      serviceConfig = ingestServiceDefaults // {
        ExecStart = "${ingestPython}/bin/python -m homescout_ingest.homeharvest_run";
      };
    };
    systemd.timers.home-scout-harvest = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 06:20:00";
        RandomizedDelaySec = "45min";
        Persistent = true;
      };
    };

    systemd.services.home-scout-cadastral = {
      description = "Home Scout monthly MT cadastral parcel load";
      after = [ "network-online.target" "postgresql.service" ];
      environment = ingestEnv;
      serviceConfig = ingestServiceDefaults // {
        ExecStart = "${ingestPython}/bin/python -m homescout_ingest.cadastral_run";
      };
    };
    systemd.timers.home-scout-cadastral = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-03 04:00:00";
        RandomizedDelaySec = "2h";
        Persistent = true;
      };
    };

    systemd.services.home-scout-redfin = {
      description = "Home Scout monthly Redfin market trends load";
      after = [ "network-online.target" "postgresql.service" ];
      environment = ingestEnv;
      serviceConfig = ingestServiceDefaults // {
        ExecStart = "${ingestPython}/bin/python -m homescout_ingest.redfin_run";
      };
    };
    systemd.timers.home-scout-redfin = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-04 04:00:00";
        RandomizedDelaySec = "2h";
        Persistent = true;
      };
    };
  };
}
