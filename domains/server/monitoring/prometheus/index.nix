# domains/server/monitoring/prometheus/index.nix
#
# PROMETHEUS - Metrics collection and monitoring
#
# NAMESPACE: hwc.server.monitoring.prometheus.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#
# USED BY:
#   - Grafana (metrics datasource)
#   - Alertmanager (alert source)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.monitoring.prometheus;
  paths = config.hwc.paths;
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

      # Alert rules organized by severity (P5/P4/P3)
      ruleFiles = [
        (pkgs.writeText "prometheus-alerts.yml" (builtins.toJSON (import ./parts/alerts.nix { inherit lib; })))
      ];
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
        StateDirectory = lib.mkForce "hwc/prometheus";
        WorkingDirectory = lib.mkForce "${paths.state}/prometheus";
      };
    };
    systemd.services.prometheus-node-exporter = {
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (cfg.port != 0);
        message = "Prometheus port must be configured";
      }
      {
        assertion = !cfg.enable || (cfg.dataDir != "");
        message = "Prometheus data directory must be configured";
      }
      {
        assertion = !cfg.enable || (builtins.match "^[0-9]+d$" cfg.retention != null);
        message = "Prometheus retention must be in format '<number>d' (e.g., '30d', '90d')";
      }
    ];
  };
}
