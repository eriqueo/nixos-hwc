# Event Scout owns local event discovery and curation. The existing research-scout
# sibling owns papers and cannot hold this service or its calendar write boundary.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.server.native.ai.event-scout;
  dbName = "event_scout";
  appDir = "${cfg.workspaceRoot}/apps/event-scout";
  cli = "${appDir}/src/cli.ts";
  tsx = "${cfg.workspaceRoot}/node_modules/tsx/dist/cli.mjs";
  tokenFile = config.hwc.secrets.api.${cfg.controlTokenSecret};
  inbox = "${config.hwc.paths.user.home}/000_inbox/downloads";
  origin = "https://event-scout.${config.hwc.networking.shared.vhostDomain}";
  environment = {
    NODE_ENV = "production";
    DATABASE_URL = "postgresql://${dbName}@localhost/${dbName}";
    EVENT_SCOUT_CONTROL_TOKEN_FILE = tokenFile;
    EVENT_SCOUT_ACTOR = cfg.reviewerId;
    EVENT_SCOUT_ORIGIN = origin;
    EVENT_SCOUT_PORT = toString cfg.port;
    EVENT_SCOUT_CALENDAR_INBOX = inbox;
    EVENT_SCOUT_CALENDAR_IMPORTED = "${inbox}/events";
    EVENT_SCOUT_CARD_URL = "http://127.0.0.1:${toString config.hwc.server.ai.hwcControlBot.targets.events.cardPort}";
    # Floating iCal timestamps are held for review, never inferred from host TZ.
    TZ = "America/Denver";
  };
  serviceConfig = {
    User = lib.mkForce "eric";
    Group = "users";
    WorkingDirectory = appDir;
    ExecStartPre = [
      "${pkgs.coreutils}/bin/test -f ${cli}"
      "${pkgs.coreutils}/bin/test -f ${tsx}"
      "${pkgs.coreutils}/bin/test -s ${tokenFile}"
      "${pkgs.coreutils}/bin/test -f ${appDir}/frontend/dist/index.html"
    ];
    TimeoutStopSec = "30s";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = "read-only";
    ReadWritePaths = [ inbox ];
  };
  command = action: "${pkgs.nodejs}/bin/node ${tsx} ${cli} ${action}";
in {
  # Unlike the older Scout modules, this namespace retains native/ai (Law 2).
  options.hwc.server.native.ai.event-scout = {
    enable = lib.mkEnableOption "Event Scout discovery, review, Discord and calendar actions";
    port = lib.mkOption { type = lib.types.port; default = 8423; description = "Loopback HTTP/MCP port."; };
    workspaceRoot = lib.mkOption { type = lib.types.path; default = "${config.hwc.paths.user.home}/600_apps/scout"; description = "Scout monorepo checkout."; };
    controlTokenSecret = lib.mkOption { type = lib.types.str; default = "hwc-control-events-token"; description = "Agenix event-only bearer shared with the HWC bot."; };
    reviewerId = lib.mkOption { type = lib.types.strMatching "^[0-9]{17,20}$"; description = "Authorized reviewer, derived from the existing HWC Discord identity."; };
  };
  config = lib.mkIf cfg.enable {
    services.postgresql = {
      ensureDatabases = [ dbName ];
      ensureUsers = [{ name = dbName; ensureDBOwnership = true; }];
    };
    # CRITICAL database: included in fleet pg_dumpall/Borg; no second backup job.
    hwc.networking.shared.routes = [{ name = "event-scout"; mode = "vhost"; upstream = "http://127.0.0.1:${toString cfg.port}"; }];
    systemd.services.event-scout = {
      description = "Event Scout private review dashboard and control API";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "postgresql.service" ];
      requires = [ "postgresql.service" ];
      inherit environment;
      startLimitIntervalSec = 300;
      startLimitBurst = 5;
      serviceConfig = serviceConfig // {
        Type = "simple"; ExecStart = command "serve"; Restart = "on-failure";
        RestartSec = "15s";
      };
    };
    systemd.services.event-scout-sweep = {
      description = "Discover and curate local events; deliver a bounded Discord shortlist";
      after = [ "network-online.target" "postgresql.service" "hwc-control-bot.service" ];
      wants = [ "network-online.target" "hwc-control-bot.service" ];
      requires = [ "postgresql.service" ];
      inherit environment;
      onFailure = lib.mkIf (config.hwc.monitoring.alerts.enable or false) [ "hwc-service-failure-notifier@event-scout-sweep.service" ];
      serviceConfig = serviceConfig // { Type = "oneshot"; ExecStart = command "sweep"; TimeoutStartSec = "10min"; };
    };
    systemd.timers.event-scout-sweep = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "*-*-* 07:00:00"; RandomizedDelaySec = "10min"; Persistent = true; };
    };
    assertions = [{ assertion = builtins.hasAttr cfg.controlTokenSecret config.hwc.secrets.api; message = "Event Scout requires its event-only agenix bearer."; }];
  };
}
