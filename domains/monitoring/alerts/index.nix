# domains/monitoring/alerts/index.nix
#
# Alert Sources — what to watch, thresholds, severity mapping, systemd triggers.
#
# NAMESPACE: hwc.monitoring.alerts.*
#
# DEPENDENCIES:
#   - hwc.notifications (delivery infrastructure)
#
# USED BY:
#   - profiles/monitoring.nix (enables alert sources)
#   - machines/server/config.nix (configures thresholds)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.alerts;
  enabled = cfg.enable;

  # Get notification scripts from the notifications domain
  notifInternal = config.hwc.notifications._internal;

  # List of critical services to auto-detect (when services list is empty)
  # NOTE: We don't check if services exist at build time to avoid infinite recursion
  # systemd will gracefully handle OnFailure= for non-existent services
  #
  # Audited 2026-08-26. That graceful handling is exactly the hazard: OnFailure=
  # on a unit that does not exist is a silent no-op, so a dead entry reads as
  # coverage and delivers nothing. Seven of the eighteen entries here named
  # units that do not exist on hwc-server -- measured with
  # `systemctl show -p LoadState --value <u>.service` returning `bad-setting`:
  #   backup, backup-local, backup-cloud   (the real unit is
  #                                         borgbackup-job-hwc-backup, which is
  #                                         covered from its own module)
  #   frigate, receipts-ocr, podman-immich (retired)
  #   jt-mcp                               (runs on a droplet, not this host)
  # `backup` was the worst of them: it looked like backup coverage for months.
  #
  # Eight live timer-driven units carried NO notifier at all and are added
  # below. Each was verified `loaded` with an empty OnFailure before adding.
  # postgresql-db-backup is the one that mattered most -- a silently failing
  # backup job is the failure you find out about on the day you need it.
  #
  # This list is still a hand-maintained blessed list, which is why it drifted.
  # Deriving it from config.systemd.services is the principled fix and is
  # blocked on the infinite recursion the NOTE above describes; left as a known
  # gap rather than pretended away.
  autoDetectedServices = [
    # Web / infra
    "caddy"
    "postgresql"
    "jellyfin"
    "podman-n8n"

    # Media stack
    "podman-navidrome"
    "podman-gluetun"
    "podman-mousehole"
    "podman-qbittorrent"
    "podman-sonarr"
    "podman-radarr"
    "podman-prowlarr"

    # Timer-driven jobs (added 2026-08-26 — all were uncovered)
    #
    # postgresql-db-backup is deliberately NOT here. It was on this list for
    # about ten minutes while writing this change, until an eval showed the
    # mistake: the same commit retires that job (machines/server/config.nix),
    # so naming it here would generate a unit carrying only `OnFailure=` and no
    # ExecStart — which is precisely how the seven dead entries above came to
    # report LoadState=bad-setting. A name on this list is not a no-op; it
    # CREATES a stub unit. Add a name here only after checking the unit exists.
    "brainvec-ingest"
    "hwc-crm-tick"
    "storage-monitor"
    "inbox-janitor"
    "morning-briefing"
    "nightly-builds"
    "llama-embed"
  ];

  # Get final list of services to monitor
  monitoredServices =
    if cfg.sources.serviceFailures.services != []
    then cfg.sources.serviceFailures.services
    else if cfg.sources.serviceFailures.autoDetect
    then autoDetectedServices
    else [];

in
{
  # OPTIONS
  options.hwc.monitoring.alerts = {
    enable = lib.mkEnableOption "Alert sources — detection, thresholds, severity mapping";

    #==========================================================================
    # ALERT SOURCES
    #==========================================================================
    sources = {
      smartd = {
        enable = lib.mkEnableOption "SMART disk monitoring alerts";
      };

      backup = {
        enable = lib.mkEnableOption "Backup completion/failure alerts";

        onSuccess = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Send alert on successful backup";
        };

        onFailure = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Send alert on backup failure";
        };
      };

      # NOTE: Disk-space monitoring is owned by Prometheus alerts
      # (domains/monitoring/prometheus/parts/alerts.nix: Moderate/Elevated/High
      # DiskUsage → Alertmanager → hwc-notify). The legacy script-based
      # hwc-disk-space-check source was retired 2026-06-04 (n8n webhook path).

      serviceFailures = {
        enable = lib.mkEnableOption "Service failure monitoring alerts";

        services = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            List of services to monitor for failures.
            Empty list = auto-detect critical services.
          '';
          example = [ "podman-immich" "jellyfin" "backup" ];
        };

        # Auto-detected critical services when services list is empty
        autoDetect = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Auto-detect critical services to monitor";
        };
      };
    };

    #==========================================================================
    # SEVERITY MAPPING
    #==========================================================================
    severity = {
      critical = lib.mkOption {
        type = lib.types.str;
        default = "P5";
        description = "Severity tag for critical alerts (immediate action required)";
      };

      warning = lib.mkOption {
        type = lib.types.str;
        default = "P4";
        description = "Severity tag for warning alerts (attention needed)";
      };

      info = lib.mkOption {
        type = lib.types.str;
        default = "P3";
        description = "Severity tag for informational alerts";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {

    # =======================================================================
    # SMARTD NOTIFICATIONS
    # =======================================================================
    # Configure smartd to use our notification script via the mail mailer
    services.smartd = lib.mkIf cfg.sources.smartd.enable {
      notifications = {
        mail = {
          enable = lib.mkForce true;
          sender = "smartd@hwc-server";
          recipient = "root";  # Required but unused - our script ignores it
          mailer = "${notifInternal.smartdNotify}/bin/hwc-smartd-notify";
        };
        x11.enable = lib.mkForce false;
        wall.enable = lib.mkForce false;
        test = lib.mkForce false;
      };
    };

    # =======================================================================
    # SYSTEMD SERVICES
    # =======================================================================
    systemd.services = lib.mkMerge [
      # Service failure notifier (template service using %I for instance name)
      (lib.mkIf cfg.sources.serviceFailures.enable {
        "hwc-service-failure-notifier@" = {
          description = "HWC service failure notifier for %I";

          serviceConfig = {
            Type = "oneshot";
            # %I is the unescaped instance name (everything after @)
            ExecStart = "${notifInternal.serviceFailureNotify}/bin/hwc-service-failure-notify %I";
            User = "root";

            # Don't fail if notification fails - we log it
            SuccessExitStatus = [ 0 1 ];
          };

          # Don't block on this
          unitConfig = {
            DefaultDependencies = false;
            RefuseManualStart = false;
          };
        };
      })

      # Add OnFailure= to monitored services
      (lib.mkIf (cfg.sources.serviceFailures.enable && monitoredServices != []) (
        lib.listToAttrs (map (serviceName: {
          name = serviceName;
          value = {
            unitConfig.OnFailure = lib.mkDefault "hwc-service-failure-notifier@${serviceName}.service";
          };
        }) monitoredServices)
      ))
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !enabled || (config.hwc.notifications.enable or false);
        message = ''
          hwc.monitoring.alerts requires notifications to be enabled for delivery.
          Enable notifications with: hwc.notifications.enable = true
        '';
      }
      {
        assertion = !cfg.sources.smartd.enable || (config.services.smartd.enable or false);
        message = "hwc.monitoring.alerts.sources.smartd requires services.smartd.enable = true";
      }
    ];

    # =======================================================================
    # WARNINGS
    # =======================================================================
    warnings = lib.optional (cfg.sources.serviceFailures.enable && monitoredServices == []) ''
      hwc.monitoring.alerts.sources.serviceFailures is enabled but no services are being monitored.
      Either:
        1. Set hwc.monitoring.alerts.sources.serviceFailures.services = [ "service1" "service2" ]
        2. Or ensure auto-detected services are enabled (jellyfin, n8n, etc.)
    '';
  };
}
