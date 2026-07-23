# domains/server/native/ai/home-scout/index.nix
#
# Home Scout — real estate intelligence pipeline (lead_scout sibling).
#
# Three parts:
#   1. home-scout.service — unified HTTP + MCP server on port 8421
#      (classify sweeps / notify / digest crons run in-process via node-cron)
#   2. systemd timers running the Python ingesters (homeharvest daily,
#      cadastral + redfin monthly, school boundaries weekly) from
#      <projectDir>/ingest
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

  # ── School boundary layers ────────────────────────────────────────────
  # Rendered into [[schools.layers]] TOML blocks. Values are typed by Nix and
  # emitted as TOML scalars/arrays, so a layer is declared once here rather
  # than hand-written into a config file on the server.
  tomlValue = v:
    if builtins.isString v then ''"${v}"''
    else if builtins.isList v then "[ ${lib.concatMapStringsSep ", " (x: ''"${x}"'') v} ]"
    else if builtins.isBool v then (if v then "true" else "false")
    else builtins.toString v;

  renderLayer = layer: ''
    [[schools.layers]]
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "${k} = ${tomlValue v}") layer
    )}
  '';

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

    ${lib.concatMapStringsSep "\n" renderLayer cfg.schoolLayers}
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

    schoolLayers = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      description = ''
        School boundary layers fetched by the monthly schools timer, as
        [[schools.layers]] TOML blocks.

        Montana does not have one "school district" per address. Most of the
        state is covered by paired ELEMENTARY (K-8) and SECONDARY (9-12)
        districts; a handful of communities (Big Sky, West Yellowstone) are
        UNIFIED K-12 instead. Elementary and unified coverage are mutually
        exclusive, verified against the live service, so the `district` level
        is fed by BOTH — every address resolves to exactly one district, and
        grouping by district is complete rather than covering only the two
        unified towns.

        Two source tiers, resolved by `priority` (higher wins where they
        overlap; find_containing in the geometry engine picks the max):

        * MSDI (priority 0) — the same keyless Montana State Library ArcGIS
          server the cadastral ingest uses. Statewide DISTRICT-level coverage
          for every address. All 395 features fetched (no county filter): the
          set is small, and a county filter would drop districts straddling a
          line near Big Sky and Bridger Canyon.
        * BSD7 (priority 10) — Bozeman School District 7's own attendance
          boundaries, published as a Google My Map (KML export). These give
          the ACTUAL school (Longfellow vs Whittier, Bozeman High vs Gallatin
          High) for addresses inside Bozeman, and win over the MSDI district
          there; outside Bozeman only MSDI covers the point, so it still wins.
      '';
      default =
        let
          boundaries =
            "https://gisservicemt.gov/arcgis/rest/services/MSDI_Framework/Boundaries/MapServer";
          # ~50m of generalisation. District lines follow section lines and
          # rivers at metre resolution; that detail cannot change which side
          # of a boundary a house sits on, and dropping it cuts the payload
          # by an order of magnitude.
          simplify = 0.0005;
          layer = key: level: id: {
            inherit key level;
            source = "msdi";
            url = "${boundaries}/${toString id}/query";
            name_field = [ "NAME" ];
            id_field = "SDLEA";
            county_field = "County_Name";
            max_allowable_offset = simplify;
            state = "MT";
          };
          # BSD7's My Map. `mid` is the map id; if the district rebuilds the
          # map Google mints a new mid and the fetch fails loudly (zero
          # features -> failed run), which is the signal to refresh it here.
          bsd7Kml =
            "https://www.google.com/maps/d/kml?mid=1vd1pcm6zfcbXoYrRdVyJ8BmF_0IzZp8Z&forcekml=1";
          bsd7 = key: level: folder: {
            inherit key level folder;
            source = "bsd7";
            driver = "kml";
            url = bsd7Kml;
            name_field = [ "name" ];
            strip_name_code = true; # "Longfellow Elementary School (LO)" -> drop "(LO)"
            priority = 10;
            county = "Gallatin";
            state = "MT";
          };
        in [
          (layer "msdi_elementary" "elementary" 5)
          (layer "msdi_secondary" "high" 4)
          # Both of these write level=district; zone ids stay distinct
          # (msdi:district:<SDLEA>) and the two layers never overlap.
          (layer "msdi_unified_district" "district" 6)
          (layer "msdi_elementary_district" "district" 5)
          # BSD7 attendance zones (Bozeman only) — win over MSDI where present.
          (bsd7 "bsd7_elementary" "elementary" "Bozeman PK-5 Elementary Boundaries")
          (bsd7 "bsd7_middle" "middle" "Bozeman 6-8 Middle School Boundaries")
          (bsd7 "bsd7_high" "high" "Bozeman 9-12 High School Boundaries")
        ];
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

    # School boundaries change on a redistricting cadence (years), but new
    # listings arrive daily and need assigning. The run is cheap when nothing
    # moved — it re-scans only listings whose boundary or coordinates changed
    # — so it goes weekly rather than monthly.
    systemd.services.home-scout-schools = {
      description = "Home Scout school district boundary load + listing assignment";
      after = [ "network-online.target" "postgresql.service" ];
      environment = ingestEnv;
      serviceConfig = ingestServiceDefaults // {
        ExecStart = "${ingestPython}/bin/python -m homescout_ingest.schools_run";
      };
    };
    systemd.timers.home-scout-schools = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 05:00:00";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };
  };
}
