{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.prometheus;
  paths = config.hwc.paths;
in {
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
  
  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = cfg.port;
      dataDir = cfg.dataDir;
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
