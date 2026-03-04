# domains/server/monitoring/exportarr/index.nix
#
# Exportarr - Prometheus exporter for *arr applications
#
# NAMESPACE: hwc.server.monitoring.exportarr.*
#
# DEPENDENCIES:
#   - hwc.server.native.monitoring.prometheus (metrics collector)
#   - hwc.server.containers.{sonarr,radarr,lidarr,prowlarr} (target apps)
#   - age.secrets.{sonarr,radarr,lidarr,prowlarr}-api-key (API authentication)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.native.monitoring.exportarr;

  # Port and URL base mapping for Arr apps
  appPorts = {
    sonarr = 8989;
    radarr = 7878;
    lidarr = 8686;
    prowlarr = 9696;
  };

  # URL bases for all Arr apps
  appUrls = {
    sonarr = "http://127.0.0.1:8989/sonarr";
    radarr = "http://127.0.0.1:7878/radarr";
    lidarr = "http://127.0.0.1:8686/lidarr";
    prowlarr = "http://127.0.0.1:9696/prowlarr";
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
    # Create separate exportarr container for each app
    virtualisation.oci-containers.containers = lib.listToAttrs (lib.imap0 (idx: app: {
      name = "exportarr-${app}";
      value = let
        exporterPort = cfg.port + idx;
      in {
        image = "ghcr.io/onedr0p/exportarr:latest";
        autoStart = true;

        # Use host network to access Arr apps on 127.0.0.1
        extraOptions = [ "--network=host" ];

        environmentFiles = [
          "/run/exportarr/${app}-env"
        ];

        environment = {
          PORT = toString exporterPort;
          ENABLE_ADDITIONAL_METRICS = "true";
          ENABLE_UNKNOWN_QUEUE_ITEMS = "true";
        };

        cmd = [
          app
          "-p" (toString exporterPort)
          "-u" appUrls.${app}
          "-a" "\${API_KEY}"
        ];
      };
    }) cfg.apps);

    # Prepare environment files with API keys
    systemd.services = lib.listToAttrs (map (app: {
      name = "podman-exportarr-${app}";
      value = {
        serviceConfig = {
          SupplementaryGroups = [ "secrets" ];
        };
        preStart = ''
          mkdir -p /run/exportarr
          echo "API_KEY=$(cat ${config.age.secrets."${app}-api-key".path})" > /run/exportarr/${app}-env
          chmod 600 /run/exportarr/${app}-env
        '';
      };
    }) cfg.apps);

    # Register with Prometheus (one job per app)
    hwc.server.native.monitoring.prometheus.scrapeConfigs = lib.imap0 (idx: app: {
      job_name = "${app}-exporter";
      static_configs = [{
        targets = [ "localhost:${toString (cfg.port + idx)}" ];
      }];
      metrics_path = "/metrics";
      scrape_interval = "60s";
      scrape_timeout = "30s";
    }) cfg.apps;

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || config.hwc.server.native.monitoring.prometheus.enable;
        message = "Exportarr requires Prometheus to be enabled (hwc.server.native.monitoring.prometheus.enable = true)";
      }
      {
        assertion = !cfg.enable || (builtins.length cfg.apps > 0);
        message = "Exportarr requires at least one app to monitor";
      }
    ] ++ map (app: {
      assertion = !cfg.enable || config.hwc.server.containers.${app}.enable;
      message = "Exportarr monitoring ${app} requires ${app} to be enabled (hwc.server.containers.${app}.enable = true)";
    }) cfg.apps;
  };
}
