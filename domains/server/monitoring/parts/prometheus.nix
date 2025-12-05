# HWC Charter Module/domains/services/monitoring/prometheus.nix
#
# PROMETHEUS - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.prometheus.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/monitoring/prometheus.nix
#
# USAGE:
#   hwc.services.prometheus.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.prometheus;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;
      stateDir = "hwc/prometheus";
      retentionTime = cfg.retention;
      
      globalConfig = {
        scrape_interval = "15s";
        evaluation_interval = "15s";
      };
      
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [ "localhost:9100" ];
          }];
        }
      ] ++ lib.optional config.hwc.services.transcriptApi.enable {
        job_name = "transcript-api";
        static_configs = [{
          targets = [ "localhost:${toString config.hwc.services.transcriptApi.port}" ];
        }];
        metrics_path = "/health";
      } ++ cfg.scrapeConfigs;
    };
    
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
    };

    # Run prometheus and node-exporter as eric user for simplified permissions
    systemd.services.prometheus = {
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
      };
    };
    systemd.services.prometheus-node-exporter = {
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
      };
    };
  };
}
