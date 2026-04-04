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

  # Convert frequency to OnCalendar format
  frequencyToCalendar = freq:
    if freq == "hourly" then "*-*-* *:00:00"
    else if freq == "daily" then "*-*-* 06:00:00"
    else if freq == "every-6h" then "*-*-* 00/6:00:00"
    else if freq == "every-12h" then "*-*-* 00/12:00:00"
    else "*-*-* *:00:00";  # default to hourly

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
    "heartwood-mcp"
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

      diskSpace = {
        enable = lib.mkEnableOption "Disk space monitoring alerts";

        criticalThreshold = lib.mkOption {
          type = lib.types.int;
          default = 95;
          description = "Critical threshold percentage (P5 alert)";
        };

        warningThreshold = lib.mkOption {
          type = lib.types.int;
          default = 80;
          description = "Warning threshold percentage (P4 alert)";
        };

        filesystems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = let paths = config.hwc.paths or {}; in
            [ "/" "/home" ]
            ++ lib.optional ((paths.media or {}).root or null != null) (toString (paths.media or {}).root)
            ++ lib.optional ((paths.hot or {}).root or null != null) (toString (paths.hot or {}).root);
          description = "Filesystems to monitor for disk space";
        };

        frequency = lib.mkOption {
          type = lib.types.enum [ "hourly" "daily" "every-6h" "every-12h" ];
          default = "hourly";
          description = "How often to check disk space";
        };
      };

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
      # Disk space monitoring service
      (lib.mkIf cfg.sources.diskSpace.enable {
        hwc-disk-space-monitor = {
          description = "HWC disk space monitoring";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${notifInternal.diskSpaceCheck}/bin/hwc-disk-space-check";
            User = "root";

            # Security hardening
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
        };
      })

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

    # =======================================================================
    # SYSTEMD TIMERS
    # =======================================================================
    systemd.timers = lib.mkMerge [
      # Disk space monitoring timer
      (lib.mkIf cfg.sources.diskSpace.enable {
        hwc-disk-space-monitor = {
          description = "HWC disk space monitoring timer";
          wantedBy = [ "timers.target" ];

          timerConfig = {
            OnCalendar = frequencyToCalendar cfg.sources.diskSpace.frequency;
            Persistent = true;
            RandomizedDelaySec = "5min";
          };
        };
      })
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
      {
        assertion = cfg.sources.diskSpace.criticalThreshold >= cfg.sources.diskSpace.warningThreshold;
        message = "hwc.monitoring.alerts.sources.diskSpace.criticalThreshold must be >= warningThreshold";
      }
      {
        assertion = cfg.sources.diskSpace.criticalThreshold <= 100 && cfg.sources.diskSpace.criticalThreshold > 0;
        message = "hwc.monitoring.alerts.sources.diskSpace.criticalThreshold must be between 1 and 100";
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
