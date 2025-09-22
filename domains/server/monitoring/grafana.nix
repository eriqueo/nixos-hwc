# nixos-h../domains/services/monitoring/grafana.nix
#
# GRAFANA - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.grafana.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/monitoring/grafana.nix
#
# USAGE:
#   hwc.services.grafana.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.grafana;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
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
  

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_port = cfg.port;
          domain = cfg.domain;
          root_url = "http://${cfg.domain}";
        };
        paths = {
          data = cfg.dataDir;
          logs = "${paths.state}/grafana/logs";
          plugins = "${cfg.dataDir}/plugins";
        };
      };
    };
    
    services.grafana.provision = {
      enable = true;
      datasources.settings.datasources = lib.mkIf config.hwc.services.prometheus.enable [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:${toString config.hwc.services.prometheus.port}";
          isDefault = true;
        }
      ];
    };
  };
}
