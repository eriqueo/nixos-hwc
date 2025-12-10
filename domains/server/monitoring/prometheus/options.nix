# domains/server/monitoring/prometheus/options.nix
#
# Prometheus Monitoring Options
# Charter v7.0 compliant

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  options.hwc.server.monitoring.prometheus = {
    enable = lib.mkEnableOption "Prometheus monitoring and metrics collection";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus HTTP server port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/prometheus";
      description = "Data directory for Prometheus time-series database";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Data retention period (e.g., '30d', '90d')";
    };

    scrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Additional scrape configurations (extended by other modules)";
    };
    
    blackboxExporter = {
          enable = lib.mkEnableOption "Blackbox Exporter health checks";
        };
  };
}
