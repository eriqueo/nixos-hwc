# HWC Charter Module/domains/services/monitoring/grafana.nix
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

    # Run grafana as eric user for simplified permissions
    systemd.services.grafana = {
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
        # Disable user namespace isolation so eric can access directories
        PrivateUsers = lib.mkForce false;
      };
    };

    # Ensure grafana data directory exists with proper permissions (owned by eric)
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 eric users -"
      "d ${cfg.dataDir}/plugins 0755 eric users -"
      "d ${cfg.dataDir}/png 0755 eric users -"
      "d ${paths.state}/grafana/logs 0755 eric users -"
    ];
  };
}
