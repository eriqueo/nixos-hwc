# domains/server/frigate/exporter/index.nix
#
# Frigate Prometheus Exporter - Converts Frigate stats API to Prometheus metrics
#
# NAMESPACE: hwc.server.frigate.exporter.*
#
# DEPENDENCIES:
#   - hwc.server.frigate (Frigate NVR service)
#   - hwc.server.native.monitoring.prometheus (metrics collector)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.frigate.exporter;
  frigateCfg = config.hwc.server.frigate;
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
    # Frigate exporter container
    virtualisation.oci-containers.containers.frigate-exporter = {
      image = "ghcr.io/blakeblackshear/frigate-prometheus-exporter:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:9192"
      ];

      environment = {
        FRIGATE_STATS_URL = "${cfg.frigateUrl}/api/stats";
      };

      dependsOn = [ "frigate" ];
    };

    # Register with Prometheus
    hwc.server.native.monitoring.prometheus.scrapeConfigs = [
      {
        job_name = "frigate-exporter";
        static_configs = [{
          targets = [ "localhost:${toString cfg.port}" ];
        }];
        scrape_interval = "30s";
      }
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || frigateCfg.enable;
        message = "Frigate exporter requires Frigate to be enabled (hwc.server.frigate.enable = true)";
      }
      {
        assertion = !cfg.enable || config.hwc.server.native.monitoring.prometheus.enable;
        message = "Frigate exporter requires Prometheus to be enabled (hwc.server.native.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
