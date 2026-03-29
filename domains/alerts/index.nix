# domains/alerts/index.nix
#
# Alerts Domain - Centralized alert routing to Slack via n8n
#
# NAMESPACE: hwc.alerts.*
#
# DEPENDENCIES:
#   - hwc.automation.n8n (webhook receiver)
#   - hwc.secrets (slack webhook URL)
#
# USED BY:
#   - profiles/alerts.nix (enables alert sources)
#   - domains/system/services/backup (backup notifications)
#   - services.smartd (disk alerts)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.alerts;
  enabled = cfg.enable;
  paths = config.hwc.paths or {};

  # Import webhook scripts
  webhookScripts = import ./parts/slack-webhook.nix { inherit pkgs lib config; };

  # Import CLI tool
  cliTool = import ./parts/cli.nix { inherit pkgs lib config; };

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
    "podman-qbittorrent"
    "podman-sonarr"
    "podman-radarr"
    "podman-prowlarr"
  ];

  # Get final list of services to monitor
  monitoredServices =
    if cfg.sources.serviceFailures.services != []
    then cfg.sources.serviceFailures.services
    else if cfg.sources.serviceFailures.autoDetect
    then autoDetectedServices
    else [];

  # Check if n8n is available (either native or we're on server)
  # Use lazy evaluation to avoid recursion
  n8nAvailable =
    (config.hwc.automation.n8n.enable or false);

in
{
  # OPTIONS
  options.hwc.alerts = {
    enable = lib.mkEnableOption "Centralized alert routing to Slack via n8n";

    #==========================================================================
    # WEBHOOK CONFIGURATION
    #==========================================================================
    webhook = {
      baseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://hwc.ocelot-wahoo.ts.net:2443/webhook";
        description = "Base URL for n8n webhook endpoints";
      };

      endpoints = {
        system = lib.mkOption {
          type = lib.types.str;
          default = "system-alerts";
          description = "Webhook endpoint for system alerts (generic)";
        };

        backup = lib.mkOption {
          type = lib.types.str;
          default = "backup-alerts";
          description = "Webhook endpoint for backup notifications";
        };

        smartd = lib.mkOption {
          type = lib.types.str;
          default = "disk-alerts";
          description = "Webhook endpoint for disk/SMART alerts";
        };

        services = lib.mkOption {
          type = lib.types.str;
          default = "service-alerts";
          description = "Webhook endpoint for service failure alerts";
        };
      };
    };

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
          default = [ "/" "/home" ]
            ++ lib.optional (paths.media.root or null != null) (toString paths.media.root)
            ++ lib.optional (paths.hot.root or null != null) (toString paths.hot.root);
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

    #==========================================================================
    # CLI TOOL
    #==========================================================================
    cli = {
      enable = lib.mkEnableOption "hwc-alert CLI tool for sending alerts";

      defaultEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "system";
        description = "Default webhook endpoint for CLI alerts";
      };

      defaultSeverity = lib.mkOption {
        type = lib.types.str;
        default = "info";
        description = "Default severity for CLI alerts (info, warning, critical)";
      };
    };

    #==========================================================================
    # GOTIFY SERVER (notification infrastructure)
    #==========================================================================
    server = {
      enable = lib.mkEnableOption "gotify notification server (container)";

      port = lib.mkOption {
        type = lib.types.port;
        default = 2586;
        description = "Gotify web port";
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.state or "/var/lib"}/gotify";
        description = "Data directory for gotify server";
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "gotify/server:latest";
        description = "Gotify container image";
      };

      adminPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Environment file containing GOTIFY_DEFAULTUSER_PASS=<password>";
      };

      tokens = {
        alertsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing gotify app token for alerts";
        };

        backupFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing gotify app token for backup notifications";
        };

        mailFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing gotify app token for mail health alerts";
        };

        monitoringFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing gotify app token for monitoring";
        };

        leadsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to file containing gotify app token for lead notifications";
        };
      };
    };

    #==========================================================================
    # INTERNAL OPTIONS (for cross-domain access)
    #==========================================================================
    _internal = {
      webhookScript = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: webhook sender script package";
      };

      cliScript = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: CLI script package";
      };
    };
  };

  imports = [
    ./parts/server.nix        # gotify notification server
    ./parts/gotify-bridge.nix # Alertmanager → gotify bridge
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    # Export internal script packages for cross-domain access
    hwc.alerts._internal = {
      webhookScript = webhookScripts.webhookSender;
      cliScript = cliTool;
    };

    # Install webhook sender scripts
    environment.systemPackages = [
      webhookScripts.webhookSender
      webhookScripts.webhookHealthCheck
      webhookScripts.smartdNotify
      webhookScripts.serviceFailureNotify
      webhookScripts.diskSpaceCheck
      webhookScripts.backupNotify
    ] ++ lib.optional cfg.cli.enable cliTool;

    # =======================================================================
    # SMARTD NOTIFICATIONS
    # =======================================================================
    # Configure smartd to use our notification script via the mail mailer
    # NixOS smartd module internally uses -M exec with a wrapper script
    # that calls the configured mailer, so we point mailer to our webhook script
    services.smartd = lib.mkIf cfg.sources.smartd.enable {
      notifications = {
        # Use mail notification with our custom "mailer" (webhook script)
        mail = {
          enable = lib.mkForce true;
          sender = "smartd@hwc-server";
          recipient = "root";  # Required but unused - our script ignores it
          mailer = "${webhookScripts.smartdNotify}/bin/hwc-smartd-notify";
        };
        # Disable other notification methods
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
            ExecStart = "${webhookScripts.diskSpaceCheck}/bin/hwc-disk-space-check";
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
            ExecStart = "${webhookScripts.serviceFailureNotify}/bin/hwc-service-failure-notify %I";
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
      # NOTE: Adding OnFailure to non-existent services is harmless -
      # systemd merges unit configs and ignores undefined units
      (lib.mkIf (cfg.sources.serviceFailures.enable && monitoredServices != []) (
        lib.listToAttrs (map (serviceName: {
          name = serviceName;
          value = {
            unitConfig.OnFailure = lib.mkDefault "hwc-service-failure-notifier@${serviceName}.service";
          };
        }) monitoredServices)
      ))

      # Webhook health check service
      {
        hwc-webhook-health = {
          description = "HWC webhook endpoint health check";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${webhookScripts.webhookHealthCheck}/bin/hwc-webhook-health";
            User = "root";
          };
        };
      }
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

      # Webhook health check timer (runs every 15 minutes)
      {
        hwc-webhook-health = {
          description = "HWC webhook health check timer";
          wantedBy = [ "timers.target" ];

          timerConfig = {
            OnCalendar = "*:0/15";  # Every 15 minutes
            Persistent = false;
            RandomizedDelaySec = "1min";
          };
        };
      }
    ];

    # =======================================================================
    # TMPFILES
    # =======================================================================
    systemd.tmpfiles.rules = [
      "d /var/log/hwc/alerts 0755 root root -"
    ];

    # =======================================================================
    # LOG ROTATION
    # =======================================================================
    services.logrotate.settings.hwc-alerts = {
      files = [ "/var/log/hwc/alerts/*.log" ];
      frequency = "weekly";
      rotate = 4;
      compress = true;
      delaycompress = true;
      missingok = true;
      notifempty = true;
      create = "0644 root root";
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !enabled || cfg.webhook.baseUrl != "";
        message = "hwc.alerts requires webhook.baseUrl to be configured";
      }
      {
        assertion = !enabled || n8nAvailable;
        message = ''
          hwc.alerts requires n8n to be enabled for webhook routing.
          Enable n8n with: hwc.automation.n8n.enable = true

          Alternatively, configure a different webhook.baseUrl pointing to
          your alert receiver.
        '';
      }
      {
        assertion = !cfg.sources.smartd.enable || (config.services.smartd.enable or false);
        message = "hwc.alerts.sources.smartd requires services.smartd.enable = true";
      }
      {
        assertion = cfg.sources.diskSpace.criticalThreshold >= cfg.sources.diskSpace.warningThreshold;
        message = "hwc.alerts.sources.diskSpace.criticalThreshold must be >= warningThreshold";
      }
      {
        assertion = cfg.sources.diskSpace.criticalThreshold <= 100 && cfg.sources.diskSpace.criticalThreshold > 0;
        message = "hwc.alerts.sources.diskSpace.criticalThreshold must be between 1 and 100";
      }
    ];

    # =======================================================================
    # WARNINGS
    # =======================================================================
    warnings = lib.optional (cfg.sources.serviceFailures.enable && monitoredServices == []) ''
      hwc.alerts.sources.serviceFailures is enabled but no services are being monitored.
      Either:
        1. Set hwc.alerts.sources.serviceFailures.services = [ "service1" "service2" ]
        2. Or ensure auto-detected services are enabled (jellyfin, n8n, etc.)
    '';
  };
}
