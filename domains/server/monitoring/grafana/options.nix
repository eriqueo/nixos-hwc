# domains/server/monitoring/grafana/options.nix
#
# Grafana Dashboards and Visualization Options
# Charter v7.0 compliant

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.server.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards and visualization";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Grafana HTTP server port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/grafana";
      description = "Data directory for Grafana";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "grafana.local";
      description = "Domain name for Grafana (used in root_url)";
    };

    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing Grafana admin password (via agenix)";
    };

    dashboards = {
      enable = lib.mkEnableOption "Dashboard provisioning" // { default = true; };

      dashboardsPath = lib.mkOption {
        type = lib.types.path;
        default = ./dashboards;
        description = "Path to dashboard JSON files";
      };
    };
  };
}
