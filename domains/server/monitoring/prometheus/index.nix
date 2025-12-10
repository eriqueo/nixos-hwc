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
      # 1. Blackbox Exporter Implementation (Only if enabled via the option)
      services.prometheus.blackboxExporter = lib.mkIf cfg.blackboxExporter.enable {
        enable = true;
        modules = {
          http_health_check = { # Module used for HTTP 200 health checks
            prober = "http";
            timeout = "5s";
            http.method = "GET";
            http.valid_status_codes = [ 200 ];
          };
        };
      };
  
      # 2. Prometheus Service Configuration
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
        ]
        # REMOVED: Old, incorrect direct scrape for 'transcript-api'
        
        # NEW: Correct Blackbox probe job (only if transcriptApi is enabled AND Blackbox is enabled)
        ++ lib.optional (config.hwc.services.transcriptApi.enable && cfg.blackboxExporter.enable) {
          job_name = "transcript-api-health";
          metrics_path = "/probe"; # Blackbox Exporter endpoint
          params = {
            module = [ "http_health_check" ]; # Use the custom Blackbox module
          };
          static_configs = [{
            # Set the target URL to be monitored
            targets = [ "http://localhost:${toString config.hwc.services.transcriptApi.port}/health" ];
          }];
          relabel_configs = [
            # Pass the target URL as a parameter to the Blackbox Exporter
            {
              source_labels = [ "__address__" ];
              target_label = "__param_target";
            }
            # Use the original target as the 'instance' label
            {
              source_labels = [ "__param_target" ];
              target_label = "instance";
            }
            # Rewrite the scrape address to point to the Blackbox Exporter's port (9115)
            {
              target_label = "__address__";
              replacement = "localhost:9115";
            }
          ];
        }
        ++ cfg.scrapeConfigs; # Include scrape configs added by other modules
  
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
