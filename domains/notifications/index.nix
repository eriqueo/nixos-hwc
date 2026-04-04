# domains/notifications/index.nix
#
# Notifications Domain — delivery infrastructure for how messages reach humans.
#
# NAMESPACE: hwc.notifications.*
#
# DEPENDENCIES:
#   - hwc.automation.n8n (webhook receiver)
#   - hwc.monitoring.alerts (severity mapping, alert sources)
#
# USED BY:
#   - profiles/monitoring.nix (enables notification delivery)
#   - domains/monitoring/alerts (alert detection → delivery)
#   - domains/data/borg (backup failure notifications)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.notifications;
  enabled = cfg.enable;

  # Import webhook scripts
  webhookScripts = import ./send/slack-webhook.nix { inherit pkgs lib config; };

  # Import CLI tool
  cliTool = import ./send/cli.nix { inherit pkgs lib config; };

  # Check if n8n is available
  n8nAvailable = (config.hwc.automation.n8n.enable or false);

in
{
  # OPTIONS
  options.hwc.notifications = {
    enable = lib.mkEnableOption "Notification delivery infrastructure (webhooks, gotify, CLI)";

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
    # CLI TOOL
    #==========================================================================
    send.cli = {
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

      smartdNotify = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: smartd notification script package";
      };

      serviceFailureNotify = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: service failure notification script package";
      };

      diskSpaceCheck = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: disk space check script package";
      };

      backupNotify = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: backup notification script package";
      };

      webhookHealthCheck = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        internal = true;
        description = "Internal: webhook health check script package";
      };
    };
  };

  imports = [
    ./gotify/server.nix              # gotify notification server
    ./gotify/bridge.nix              # Alertmanager → gotify bridge
    ./gotify/igotify.nix             # iOS push notification relay
    ./send/gotify.nix                # hwc-gotify-send CLI tool
    ./health.nix                     # webhook health check timer
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    # Export internal script packages for cross-domain access
    hwc.notifications._internal = {
      webhookScript = webhookScripts.webhookSender;
      cliScript = cliTool;
      smartdNotify = webhookScripts.smartdNotify;
      serviceFailureNotify = webhookScripts.serviceFailureNotify;
      diskSpaceCheck = webhookScripts.diskSpaceCheck;
      backupNotify = webhookScripts.backupNotify;
      webhookHealthCheck = webhookScripts.webhookHealthCheck;
    };

    # Install webhook sender scripts
    environment.systemPackages = [
      webhookScripts.webhookSender
      webhookScripts.webhookHealthCheck
      webhookScripts.smartdNotify
      webhookScripts.serviceFailureNotify
      webhookScripts.diskSpaceCheck
      webhookScripts.backupNotify
    ] ++ lib.optional cfg.send.cli.enable cliTool;

    # =======================================================================
    # TMPFILES
    # =======================================================================
    systemd.tmpfiles.rules = [
      "d /var/log/hwc/notifications 0755 root root -"
    ];

    # =======================================================================
    # LOG ROTATION
    # =======================================================================
    services.logrotate.settings.hwc-notifications = {
      files = [ "/var/log/hwc/notifications/*.log" ];
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
        message = "hwc.notifications requires webhook.baseUrl to be configured";
      }
      {
        assertion = !enabled || n8nAvailable;
        message = ''
          hwc.notifications requires n8n to be enabled for webhook routing.
          Enable n8n with: hwc.automation.n8n.enable = true

          Alternatively, configure a different webhook.baseUrl pointing to
          your alert receiver.
        '';
      }
    ];
  };
}
