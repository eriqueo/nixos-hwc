# domains/server/monitoring/alertmanager/options.nix
#
# Alertmanager Alert Routing Options
# Charter v7.0 compliant

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.server.monitoring.alertmanager = {
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
}
