# domains/server/monitoring/alertmanager/index.nix
#
# ALERTMANAGER - Alert routing and notification management
#
# NAMESPACE: hwc.server.monitoring.alertmanager.*
#
# DEPENDENCIES:
#   - hwc.server.native.monitoring.prometheus (alert source)
#   - hwc.paths.state (data directory)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.native.monitoring.alertmanager;
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
  imports = [ ./options.nix ];

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
    services.prometheus.alertmanagers = lib.mkIf config.hwc.server.native.monitoring.prometheus.enable [{
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
        assertion = !cfg.enable || config.hwc.server.native.monitoring.prometheus.enable;
        message = "Alertmanager requires Prometheus (hwc.server.native.monitoring.prometheus.enable = true)";
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
