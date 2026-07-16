# domains/business/crm — hwc-crm
#
# Front-of-funnel CRM layered on hwc-leads: funnel stages + gates over the
# canonical hwc.leads store, follow-up sequences, next-action surfacing,
# funnel board UI. Runs from a live checkout (lead-scout pattern) at
# cfg.projectDir; Python deps come from nixpkgs (yt-transcripts pattern).
#
# Ownership contract: hwc-leads owns hwc.leads.status; hwc-crm owns
# funnel_stage + the CRM tables (see hwc-crm DECISIONS.md D2). The
# migration is additive-only and idempotent; it runs as ExecStartPre.
#
# NAMESPACE: hwc.business.crm.*

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business.crm;
  paths = config.hwc.paths;

  # Same JT org registry hwc-leads uses — one source of truth for the
  # org id / custom field ids / default location.
  jtMappingsJson = builtins.toJSON (import ../leads/parts/jt-mappings.nix);
  jtMappingsFile = pkgs.writeText "hwc-crm-jt-mappings.json" jtMappingsJson;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi uvicorn psycopg jinja2 httpx pydantic email-validator
    icalendar tzdata
  ]);

  crmWrapper = pkgs.writeShellScript "hwc-crm-wrapper" ''
    export PYTHONPATH="${cfg.projectDir}/src"
    export HWC_CRM_BIND_ADDR="${cfg.bindAddr}"
    export HWC_CRM_PORT="${toString cfg.port}"
    export HWC_CRM_PG_DSN="${cfg.postgresDsn}"
    export HWC_CRM_LOG_LEVEL="${cfg.logLevel}"
    export HWC_CRM_EMAIL_TRANSPORT="${cfg.emailTransport}"
    export HWC_CRM_SPOOL_DIR="${cfg.statePath}/spool"
    export HWC_CRM_JT_MAPPINGS_FILE="${jtMappingsFile}"
    ${lib.optionalString (cfg.jtGrantKeyRef != null) ''
      export HWC_CRM_JT_GRANT_FILE="${config.age.secrets.${cfg.jtGrantKeyRef}.path}"
    ''}
    ${lib.optionalString (cfg.emailTransport == "smtp") ''
      export HWC_CRM_SMTP_HOST="${cfg.smtp.host}"
      export HWC_CRM_SMTP_PORT="${toString cfg.smtp.port}"
      export HWC_CRM_SMTP_LOGIN="${cfg.smtp.login}"
      export HWC_CRM_SMTP_FROM="${cfg.smtp.from}"
      export HWC_CRM_SMTP_PASSWORD_FILE="${config.age.secrets.${cfg.smtp.passwordSecretRef}.path}"
    ''}
    ${lib.optionalString cfg.calendar.enable ''
      export HWC_CRM_CALDAV_URL="${cfg.calendar.caldavUrl}"
      export HWC_CRM_CALDAV_USER="${cfg.calendar.user}"
      export HWC_CRM_CALDAV_PASSWORD_FILE="/run/hwc-crm/caldav-pw"
      export HWC_CRM_CALDAV_COLLECTION="${cfg.calendar.collection}"
      export HWC_CRM_ORGANIZER_EMAIL="${cfg.calendar.organizerEmail}"
    ''}
    ${lib.optionalString (cfg.calendar.enable && cfg.rolodex.enable) ''
      export HWC_CRM_CARDDAV_USER="${cfg.rolodex.user}"
      export HWC_CRM_CARDDAV_PASSWORD_FILE="/run/hwc-crm/carddav-pw"
      export HWC_CRM_CARDDAV_COLLECTION="${cfg.rolodex.collection}"
    ''}
    exec ${pythonEnv}/bin/python3 -m hwc_crm.api.app
  '';

  migrate = pkgs.writeShellScript "hwc-crm-migrate" ''
    for f in ${cfg.projectDir}/migrations/*.sql; do
      ${config.services.postgresql.package}/bin/psql "${cfg.postgresDsn}" \
        -v ON_ERROR_STOP=1 -q -f "$f"
    done
  '';

  # Extract just the `cal:` line's password from the shared radicale htpasswd
  # into a service-private runtime file (the vdirsyncer pattern). Runs as root
  # (ExecStartPre "+") because the htpasswd is root-readable only.
  caldavPwGen = pkgs.writeShellScript "hwc-crm-caldav-pw" ''
    umask 077
    ${pkgs.gawk}/bin/awk -F: -v u=${cfg.calendar.user} \
      '$1==u{match($0,/:/);print substr($0,RSTART+1)}' \
      /run/agenix/radicale-htpasswd > /run/hwc-crm/caldav-pw
    ${pkgs.coreutils}/bin/chown ${cfg.user}:users /run/hwc-crm/caldav-pw
    ${pkgs.coreutils}/bin/chmod 0400 /run/hwc-crm/caldav-pw
    ${lib.optionalString cfg.rolodex.enable ''
      ${pkgs.gawk}/bin/awk -F: -v u=${cfg.rolodex.user} \
        '$1==u{match($0,/:/);print substr($0,RSTART+1)}' \
        /run/agenix/radicale-htpasswd > /run/hwc-crm/carddav-pw
      ${pkgs.coreutils}/bin/chown ${cfg.user}:users /run/hwc-crm/carddav-pw
      ${pkgs.coreutils}/bin/chmod 0400 /run/hwc-crm/carddav-pw
    ''}
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.business.crm = {
    enable = lib.mkEnableOption "hwc-crm front-of-funnel service";

    projectDir = lib.mkOption {
      type = lib.types.str;
      default = "${paths.user.home}/600_apps/hwc-crm";
      description = "Live checkout of the hwc-crm repo (lead-scout pattern).";
    };

    bindAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11660;  # 11600 = hwc-notify, 11650 = hwc-leads
    };

    postgresDsn = lib.mkOption {
      type = lib.types.str;
      default = "postgresql:///hwc";
      description = "Unix-socket peer auth as the service user (same as hwc-leads).";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [ "debug" "info" "warning" "error" ];
      default = "info";
    };

    emailTransport = lib.mkOption {
      type = lib.types.enum [ "file" "smtp" ];
      default = "file";
      description = ''
        "file" renders sequence emails to <statePath>/spool (safe default).
        Flip to "smtp" (Proton Bridge loopback, hwc-leads' path) to go live.
      '';
    };

    smtp = {
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      port = lib.mkOption { type = lib.types.port; default = 1025; };
      login = lib.mkOption { type = lib.types.str; default = "eric@iheartwoodcraft.com"; };
      from = lib.mkOption { type = lib.types.str; default = "eric@iheartwoodcraft.com"; };
      passwordSecretRef = lib.mkOption {
        type = lib.types.str;
        default = "proton-bridge-password";
      };
    };

    jtGrantKeyRef = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "jobtread-grant-key";
      description = "agenix secret for manual-lead JT graph creation. null disables.";
    };

    statePath = lib.mkOption {
      type = lib.types.str;
      default = "${paths.state}/crm";
    };

    user = lib.mkOption { type = lib.types.str; default = "eric"; };

    tick = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Hourly sequence tick timer (sends are still gated by crm_settings.sequences_enabled in the DB).";
      };
      onCalendar = lib.mkOption { type = lib.types.str; default = "hourly"; };
    };

    leadscoutIngest = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Periodic lead_scout → CRM ingest: pulls hot/warm classified FB
          posts from the datax Postgres (READ-ONLY) onto the funnel board.
          Idempotent — already-ingested posts are skipped silently (D22);
          hot leads get next_action_date = today. facebook_scrape is never
          auto-emailed (D13).
        '';
      };
      onCalendar = lib.mkOption { type = lib.types.str; default = "*:00/30"; };
      sinceDays = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = "Rescan window; the skip pre-filter makes overlap free.";
      };
      routes = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            profile = lib.mkOption {
              type = lib.types.str;
              description = "lead_scout classifier_profiles.id to pull from.";
            };
            pipeline = lib.mkOption {
              type = lib.types.enum [ "job" "network" ];
              description = "hwc-crm pipeline the leads land in.";
            };
            source = lib.mkOption {
              type = lib.types.str;
              description = "hwc.leads.source value (must be in the source CHECK).";
            };
            ingestTiers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "lead_scout classification tiers to ingest.";
            };
            nextActionTiers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "Tiers that get next_action_date = today on creation.";
            };
            emailPrefix = lib.mkOption {
              type = lib.types.str;
              description = ''
                Placeholder-email prefix — the dedupe NAMESPACE. Must be
                unique per route: profiles share scrape sources, so the same
                post classified under two profiles must yield two leads.
              '';
            };
          };
        });
        default = [
          {
            profile = "hwc_bozeman_v1";
            pipeline = "job";
            source = "facebook_scrape";
            ingestTiers = [ "hot_lead" "warm_lead" ];
            nextActionTiers = [ "hot_lead" ];
            emailPrefix = "fb";
          }
          {
            profile = "hwc_network_v1";
            pipeline = "network";
            source = "network_scrape";
            ingestTiers = [ "hot_connect" "warm_connect" ];
            nextActionTiers = [ "hot_connect" ];
            emailPrefix = "net";
          }
        ];
        description = ''
          lead_scout → CRM route table (app D23): one route per classifier
          profile feeding one pipeline. Rendered to HWC_CRM_INGEST_ROUTES as
          JSON; one timer iterates all routes.
        '';
      };
      dataxDsn = lib.mkOption {
        type = lib.types.str;
        default = "postgresql:///datax";
        description = "lead_scout's datax DB, unix-socket peer auth (read-only by contract).";
      };
    };

    rolodex = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Bidirectional CardDAV rolodex (app D26): CRM contacts sync to a
          Radicale address book under the PHONE's radicale user, so the
          existing iPhone account (user eric) sees them. Rides on
          calendar.enable (same Radicale + htpasswd). The sync timer pulls
          phone edits/creations back into the CRM.
        '';
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "radicale-htpasswd user owning the address book (the phone's login).";
      };
      collection = lib.mkOption {
        type = lib.types.str;
        default = "eric/contacts";
      };
      sync.onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*:0/15";
        description = "Bidirectional reconcile cadence (phone → CRM latency).";
      };
    };

    calendar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Write appointment events to the self-hosted Radicale CalDAV server
          (loopback) so they sync to khal + iPhone, and email the customer an
          .ics invite. The `cal` password is extracted from the shared
          radicale htpasswd at start (no new secret).
        '';
      };
      caldavUrl = lib.mkOption { type = lib.types.str; default = "http://127.0.0.1:5232"; };
      user = lib.mkOption { type = lib.types.str; default = "cal"; };
      collection = lib.mkOption { type = lib.types.str; default = "cal/migrated"; };
      organizerEmail = lib.mkOption { type = lib.types.str; default = "eric@iheartwoodcraft.com"; };
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.user != "root";
        message = "hwc-crm must not run as root";
      }
      {
        assertion = cfg.jtGrantKeyRef == null || config.age.secrets ? ${cfg.jtGrantKeyRef};
        message = "hwc.business.crm.jtGrantKeyRef '${toString cfg.jtGrantKeyRef}' is not a declared agenix secret";
      }
      {
        assertion = cfg.emailTransport != "smtp" || config.age.secrets ? ${cfg.smtp.passwordSecretRef};
        message = "hwc-crm smtp transport needs agenix secret '${cfg.smtp.passwordSecretRef}'";
      }
    ];

    systemd.services.hwc-crm = {
      description = "hwc-crm — front-of-funnel CRM on hwc-leads";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "postgresql.service" ];
      wants = [ "network-online.target" ];
      requires = [ "postgresql.service" ];

      restartTriggers = lib.optional (cfg.jtGrantKeyRef != null)
        config.age.secrets.${cfg.jtGrantKeyRef}.file
        ++ lib.optional (cfg.emailTransport == "smtp")
          config.age.secrets.${cfg.smtp.passwordSecretRef}.file;

      serviceConfig = {
        Type = "exec";
        User = lib.mkForce cfg.user;
        Group = "users";
        RuntimeDirectory = "hwc-crm";   # /run/hwc-crm for the caldav pw file
        RuntimeDirectoryMode = "0750";
        ExecStartPre =
          lib.optional cfg.calendar.enable "+${caldavPwGen}"  # root: reads htpasswd
          ++ [ "${migrate}" ];                                # eric: additive + idempotent
        ExecStart = "${crmWrapper}";
        Restart = "always";
        RestartSec = "5s";
        StateDirectory = "hwc/crm";
        StateDirectoryMode = "0750";
        ReadWritePaths = [ cfg.statePath ];

        # Hardening (leads/yt-transcripts set)
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
    };

    # Hourly sequence tick. Persistent=true → a missed window fires on
    # boot; the engine processes ALL due work, not current-hour-only.
    systemd.services.hwc-crm-tick = lib.mkIf cfg.tick.enable {
      description = "hwc-crm sequence tick";
      after = [ "hwc-crm.service" ];
      requires = [ "hwc-crm.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce cfg.user;
        Group = "users";
        ExecStart = "${pkgs.curl}/bin/curl -sf -X POST http://${cfg.bindAddr}:${toString cfg.port}/internal/sequences/tick";
      };
    };
    systemd.timers.hwc-crm-tick = lib.mkIf cfg.tick.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.tick.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "60s";
      };
    };

    # lead_scout → funnel board ingest (D22). Persistent=true → a missed
    # window fires on boot; Requires=postgresql so the boot catch-up run
    # can't race the DB. OnFailure → Discord via the alerts notifier, so
    # lead_scout schema drift is loud instead of a silent lead drought.
    systemd.services.hwc-crm-leadscout-ingest = lib.mkIf cfg.leadscoutIngest.enable {
      description = "hwc-crm lead_scout ingest (hot/warm FB posts onto the funnel board)";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      onFailure = lib.mkIf (config.hwc.monitoring.alerts.enable or false)
        [ "hwc-service-failure-notifier@hwc-crm-leadscout-ingest.service" ];
      environment = {
        PYTHONPATH = "${cfg.projectDir}/src";
        HWC_CRM_PG_DSN = cfg.postgresDsn;
        HWC_CRM_DATAX_DSN = cfg.leadscoutIngest.dataxDsn;
        HWC_CRM_INGEST_ROUTES = builtins.toJSON (map (r: {
          profile = r.profile;
          pipeline = r.pipeline;
          source = r.source;
          ingest_tiers = r.ingestTiers;
          next_action_tiers = r.nextActionTiers;
          email_prefix = r.emailPrefix;
        }) cfg.leadscoutIngest.routes);
      };
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce cfg.user;
        Group = "users";
        ExecStart = "${pythonEnv}/bin/python3 -m hwc_crm.integrations.leadscout_ingest"
          + " --since-days ${toString cfg.leadscoutIngest.sinceDays}";
      };
    };
    systemd.timers.hwc-crm-leadscout-ingest = lib.mkIf cfg.leadscoutIngest.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.leadscoutIngest.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "120s";
      };
    };

    # Bidirectional rolodex reconcile (app D26): pulls phone edits/creations
    # into the CRM, pushes missing cards, honors phone deletions.
    systemd.services.hwc-crm-rolodex-sync =
      lib.mkIf (cfg.calendar.enable && cfg.rolodex.enable) {
        description = "hwc-crm rolodex sync (CardDAV ↔ CRM contacts)";
        after = [ "hwc-crm.service" ];
        requires = [ "hwc-crm.service" ];
        onFailure = lib.mkIf (config.hwc.monitoring.alerts.enable or false)
          [ "hwc-service-failure-notifier@hwc-crm-rolodex-sync.service" ];
        serviceConfig = {
          Type = "oneshot";
          User = lib.mkForce cfg.user;
          Group = "users";
          ExecStart = "${pkgs.curl}/bin/curl -sf -X POST http://${cfg.bindAddr}:${toString cfg.port}/internal/rolodex/sync";
        };
      };
    systemd.timers.hwc-crm-rolodex-sync =
      lib.mkIf (cfg.calendar.enable && cfg.rolodex.enable) {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.rolodex.sync.onCalendar;
          Persistent = true;
          RandomizedDelaySec = "60s";
        };
      };

    # Tailnet-private vhost: crm.hwc.iheartwoodcraft.com
    hwc.networking.shared.routes = [{
      name = "crm";
      mode = "vhost";
      upstream = "http://${cfg.bindAddr}:${toString cfg.port}";
    }];
  };
}
