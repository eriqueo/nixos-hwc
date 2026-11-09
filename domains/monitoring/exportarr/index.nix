# domains/monitoring/exportarr/index.nix
#
# Exportarr - Prometheus exporter for *arr applications
#
# NAMESPACE: hwc.monitoring.exportarr.*
#
# DEPENDENCIES:
#   - hwc.monitoring.prometheus (metrics collector)
#   - hwc.media.{sonarr,radarr,lidarr,prowlarr} (target apps)
#   - age.secrets.{sonarr,radarr,lidarr,prowlarr}-api-key (API authentication)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.exportarr;

  appPorts = {
    sonarr = 8989;
    radarr = 7878;
    lidarr = 8686;
    prowlarr = 9696;
  };

  # Arr apps use name-based vhosts and have no URL prefix.
  exporters = lib.imap0 (idx: name: {
    inherit name;
    port = cfg.port + idx;
    url = "http://127.0.0.1:${toString appPorts.${name}}";
  }) cfg.apps;
in
{
  # OPTIONS
  options.hwc.monitoring.exportarr = {
    enable = lib.mkEnableOption "Exportarr metrics exporter for *arr applications";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9707;
      description = "Exportarr metrics port";
    };

    apps = lib.mkOption {
      type = lib.types.listOf (lib.types.enum ["sonarr" "radarr" "lidarr" "prowlarr"]);
      default = ["sonarr" "radarr" "lidarr" "prowlarr"];
      description = "Arr applications to monitor";
    };
  };
  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers = lib.listToAttrs (map (app: {
      name = "exportarr-${app.name}";
      value = {
        image = "ghcr.io/onedr0p/exportarr:latest";
        autoStart = true;

        extraOptions = [ "--network=host" ];

        environmentFiles = [
          "/run/exportarr/${app.name}-env"
        ];

        environment = {
          PORT = toString app.port;
          # Host network: bind the tailnet address, not every interface.
          INTERFACE = config.hwc.monitoring.prometheus.agent.listenAddress;
          ENABLE_ADDITIONAL_METRICS = "true";
          ENABLE_UNKNOWN_QUEUE_ITEMS = "true";
        };

        cmd = [
          app.name
          "-p" (toString app.port)
          "-u" app.url
          "-a" "\${API_KEY}"
        ];
      };
    }) exporters);

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

    hwc.monitoring.prometheus.scrapeConfigs = map (app: {
      job_name = "${app.name}-exporter";
      static_configs = [{
        targets = [ "localhost:${toString app.port}" ];
      }];
      metrics_path = "/metrics";
      scrape_interval = "60s";
      scrape_timeout = "30s";
    }) exporters;
    # VALIDATION
    assertions = [
      {
        assertion = !cfg.enable || config.hwc.monitoring.prometheus.agent.enable;
        message = "Exportarr exports to the central Prometheus through this host's agent (hwc.monitoring.prometheus.agent.enable = true)";
      }
      {
        assertion = !cfg.enable || (builtins.length cfg.apps > 0);
        message = "Exportarr requires at least one app to monitor";
      }
    ] ++ map (app: {
      assertion = !cfg.enable || config.hwc.media.${app}.enable;
      message = "Exportarr monitoring ${app} requires ${app} to be enabled (hwc.media.${app}.enable = true)";
    }) cfg.apps;
  };
}
