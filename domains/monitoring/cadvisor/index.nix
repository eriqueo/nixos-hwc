# domains/monitoring/cadvisor/index.nix
#
# cAdvisor - Container Advisor for resource usage and performance metrics
#
# NAMESPACE: hwc.monitoring.cadvisor.*
#
# DEPENDENCIES:
#   - hwc.monitoring.prometheus (metrics collector)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.cadvisor;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.cadvisor = {
    enable = lib.mkEnableOption "cAdvisor container metrics exporter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9120;
      description = "cAdvisor metrics port";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # cAdvisor container for container metrics
    virtualisation.oci-containers.containers.cadvisor = {
      image = "gcr.io/cadvisor/cadvisor:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:8080"
      ];

      volumes = [
        "/:/rootfs:ro"
        "/var/run:/var/run:ro"
        "/sys:/sys:ro"
        "/var/lib/containers:/var/lib/containers:ro"
        "/dev/disk:/dev/disk:ro"
      ];

      extraOptions = [
        "--privileged"
        "--device=/dev/kmsg"
      ];
    };

    # Register with Prometheus
    hwc.monitoring.prometheus.scrapeConfigs = [
      {
        job_name = "cadvisor";
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
        assertion = !cfg.enable || config.hwc.monitoring.prometheus.enable;
        message = "cAdvisor requires Prometheus to be enabled (hwc.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
