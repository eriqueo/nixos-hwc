# domains/monitoring/alertmanager/index.nix
#
# ALERTMANAGER - Alert routing and notification management
#
# NAMESPACE: hwc.monitoring.alertmanager.*
#
# DEPENDENCIES:
#   - hwc.monitoring.prometheus (alert source)
#   - hwc.paths.state (data directory)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.alertmanager;
  paths = config.hwc.paths;

  # Generate Alertmanager configuration
  alertmanagerConfig = {
    global = {
      resolve_timeout = "5m";
    };

    route = {
      group_by = ["alertname" "cluster" "service"];
      group_wait = cfg.groupWait;
      group_interval = cfg.groupInterval;
      repeat_interval = cfg.repeatInterval;
      receiver = "default";  # Fallback receiver
    };

    receivers = [
      { name = "default"; }
    ] ++ map (receiver: {
      name = receiver.name;
      webhook_configs = [{
        url = receiver.url;
        send_resolved = receiver.sendResolved;
      }];
    }) cfg.webhookReceivers;
  };

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.alertmanager = {
    enable = lib.mkEnableOption "Prometheus Alertmanager for alert routing and notification";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9093;
      description = "Alertmanager HTTP server port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/alertmanager";
      description = "Data directory for Alertmanager";
    };

    webhookReceivers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Receiver name";
          };
          url = lib.mkOption {
            type = lib.types.str;
            description = "Webhook URL";
          };
          sendResolved = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Send resolved alerts";
          };
        };
      });
      default = [];
      description = "Webhook receivers configuration for alert delivery";
    };

    groupWait = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      description = "Time to wait before sending first notification for a group";
    };

    groupInterval = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Time between notifications for the same group";
    };

    repeatInterval = lib.mkOption {
      type = lib.types.str;
      default = "4h";
      description = "Time before re-sending an alert";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    services.prometheus.alertmanager = {
      enable = true;
      port = cfg.port;
      configuration = alertmanagerConfig;
    };

    # Configure Prometheus to send alerts to Alertmanager
    services.prometheus.alertmanagers = lib.mkIf config.hwc.monitoring.prometheus.enable [{
      static_configs = [{
        targets = [ "localhost:${toString cfg.port}" ];
      }];
    }];

    # Run as eric user
    # Note: NixOS alertmanager module hardcodes --storage.path=/var/lib/alertmanager
    # We create that directory and ensure eric owns it
    systemd.services.alertmanager = {
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
        StateDirectory = lib.mkForce "alertmanager";  # Creates /var/lib/alertmanager owned by eric
        DynamicUser = lib.mkForce false;
      };
    };

    # Firewall - localhost + Tailscale
    networking.firewall.interfaces."lo".allowedTCPPorts = [ cfg.port ];
    networking.firewall.interfaces."tailscale0".allowedTCPPorts =
      lib.optional (config.networking.interfaces ? "tailscale0") cfg.port;

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || config.hwc.monitoring.prometheus.enable;
        message = "Alertmanager requires Prometheus (hwc.monitoring.prometheus.enable = true)";
      }
      {
        assertion = !cfg.enable || (cfg.port != 0);
        message = "Alertmanager port must be configured";
      }
      {
        assertion = !cfg.enable || (cfg.dataDir != "");
        message = "Alertmanager data directory must be configured";
      }
    ];

    # Warn if no webhook receivers configured (allows deployment without webhooks)
    warnings = lib.optional (cfg.enable && cfg.webhookReceivers == [])
      "Alertmanager has no webhook receivers configured. Configure webhookReceivers to receive alerts.";
  };
}
