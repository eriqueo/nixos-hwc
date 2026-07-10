# domains/media/frigate/exporter/index.nix
#
# Frigate Prometheus Exporter - Converts Frigate stats API to Prometheus metrics
#
# NAMESPACE: hwc.media.frigate.exporter.*
#
# DEPENDENCIES:
#   - hwc.media.frigate (Frigate NVR service)
#   - hwc.monitoring.prometheus (metrics collector)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.media.frigate.exporter;
  frigateCfg = config.hwc.media.frigate;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.frigate.exporter = {
    enable = lib.mkEnableOption "Frigate Prometheus exporter";
    port = lib.mkOption { type = lib.types.port; default = 9192; description = "Frigate exporter metrics port (host side; container listens on 9100)"; };
    # Frigate runs --network=host on port 5000; this exporter runs on the podman
    # bridge, so it reaches the stats API via the host gateway alias, not localhost.
    frigateUrl = lib.mkOption { type = lib.types.str; default = "http://host.containers.internal:5000"; description = "Frigate API URL (reachable from the exporter container)"; };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Frigate exporter container
    # HWC-EXCEPTION(Law 5): metrics sidecar of the frigate container
    # Justification: tiny exporter joined to frigate; no media mounts, PUID/PGID, or VPN netns
    # Plan: permanent by design (revisit if an infra-shaped helper grows to fit)
    # Revocable: yes
    virtualisation.oci-containers.containers.frigate-exporter = {
      # bairhys/prometheus-frigate-exporter — the maintained image. (The former
      # ghcr.io/blakeblackshear/frigate-prometheus-exporter never existed → 403.)
      # It reads $FRIGATE_STATS_URL and serves /metrics on container port 9100.
      image = "docker.io/rhysbailey/prometheus-frigate-exporter:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:9100"
      ];

      environment = {
        FRIGATE_STATS_URL = "${cfg.frigateUrl}/api/stats";
      };

      dependsOn = [ "frigate" ];
    };

    # Register with Prometheus
    hwc.monitoring.prometheus.scrapeConfigs = [
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
        message = "Frigate exporter requires Frigate to be enabled (hwc.media.frigate.enable = true)";
      }
      {
        assertion = !cfg.enable || config.hwc.monitoring.prometheus.enable;
        message = "Frigate exporter requires Prometheus to be enabled (hwc.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
