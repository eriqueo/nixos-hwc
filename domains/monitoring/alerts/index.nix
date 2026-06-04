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
  autoDetectedServices = [
    "backup"
    "backup-local"
    "backup-cloud"
    "jellyfin"
    "podman-n8n"
    "caddy"
    "postgresql"
    "frigate"
    "receipts-ocr"
    "podman-immich"
    "podman-navidrome"
    "podman-gluetun"
    "podman-mousehole"
    "podman-qbittorrent"
    "podman-sonarr"
    "podman-radarr"
    "podman-prowlarr"
    "jt-mcp"
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
