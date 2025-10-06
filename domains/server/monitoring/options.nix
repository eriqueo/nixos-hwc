# domains/server/monitoring/options.nix
#
# Consolidated options for server monitoring subdomain
# Charter-compliant: ALL monitoring options defined here

{ lib, config, ... }:

let
  paths = config.hwc.paths;
in
{
  #============================================================================
  # PROMETHEUS OPTIONS
  #============================================================================
  options.hwc.services.prometheus = {
    enable = lib.mkEnableOption "Prometheus monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/prometheus";
      description = "Data directory";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Data retention period";
    };

    scrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Scrape configurations";
    };
  };

  #============================================================================
  # GRAFANA OPTIONS
  #============================================================================
  options.hwc.services.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Grafana port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/grafana";
      description = "Data directory";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "grafana.local";
      description = "Domain name";
    };
  };
}