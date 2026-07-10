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
      default = "/home/eric/600_apps/hwc-crm";
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

    # Tailnet-private vhost: crm.hwc.iheartwoodcraft.com
    hwc.networking.shared.routes = [{
      name = "crm";
      mode = "vhost";
      upstream = "http://${cfg.bindAddr}:${toString cfg.port}";
    }];
  };
}
