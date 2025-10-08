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
      stateDir = cfg.dataDir;
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
      ] ++ cfg.scrapeConfigs;
    };
    
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
    };
  };
}
