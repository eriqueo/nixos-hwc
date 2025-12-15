# domains/server/monitoring/exportarr/index.nix
#
# Exportarr - Prometheus exporter for *arr applications
#
# NAMESPACE: hwc.server.monitoring.exportarr.*
#
# DEPENDENCIES:
#   - hwc.server.monitoring.prometheus (metrics collector)
#   - hwc.server.containers.{sonarr,radarr,lidarr,prowlarr} (target apps)
#   - age.secrets.{sonarr,radarr,lidarr,prowlarr}-api-key (API authentication)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.monitoring.exportarr;

  # Port mapping for Arr apps
  appPorts = {
    sonarr = 8989;
    radarr = 7878;
    lidarr = 8686;
    prowlarr = 9696;
  };
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
    # Exportarr container
    virtualisation.oci-containers.containers.exportarr = {
      image = "ghcr.io/onedr0p/exportarr:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:${toString cfg.port}"
      ];

      volumes = [
        "/run/agenix:/run/agenix:ro"
      ];

      environment = {
        PORT = toString cfg.port;
        ENABLE_ADDITIONAL_METRICS = "true";
        ENABLE_UNKNOWN_QUEUE_ITEMS = "true";
      };

      # Start exportarr for each configured app
      cmd = lib.concatMapStringsSep " " (app:
        "${app} --url http://127.0.0.1:${toString appPorts.${app}} --api-key-file /run/agenix/${app}-api-key"
      ) cfg.apps;
    };

    # Ensure exportarr container has access to secrets
    systemd.services."podman-exportarr".serviceConfig = {
      SupplementaryGroups = [ "secrets" ];
    };

    # Register with Prometheus (one job per app)
    hwc.server.monitoring.prometheus.scrapeConfigs = map (app: {
      job_name = "${app}-exporter";
      static_configs = [{
        targets = [ "localhost:${toString cfg.port}" ];
      }];
      metrics_path = "/${app}/metrics";
      scrape_interval = "60s";
      scrape_timeout = "30s";
    }) cfg.apps;
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = [
    {
      assertion = !cfg.enable || config.hwc.server.monitoring.prometheus.enable;
      message = "Exportarr requires Prometheus to be enabled (hwc.server.monitoring.prometheus.enable = true)";
    }
    {
      assertion = !cfg.enable || (builtins.length cfg.apps > 0);
      message = "Exportarr requires at least one app to monitor";
    }
  ] ++ map (app: {
    assertion = !cfg.enable || config.hwc.server.containers.${app}.enable;
    message = "Exportarr monitoring ${app} requires ${app} to be enabled (hwc.server.containers.${app}.enable = true)";
  }) cfg.apps;
}
