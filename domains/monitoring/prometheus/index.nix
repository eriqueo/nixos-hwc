# domains/monitoring/prometheus/index.nix
#
# PROMETHEUS - Metrics collection and monitoring
#
# NAMESPACE: hwc.monitoring.prometheus.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#
# USED BY:
#   - Grafana (metrics datasource)
#   - Alertmanager (alert source)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.prometheus;
  paths = config.hwc.paths;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.prometheus = {
    enable = lib.mkEnableOption "Prometheus monitoring and metrics collection";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus HTTP server port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/prometheus";
      description = "Data directory for Prometheus time-series database";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Data retention period (e.g., '30d', '90d')";
    };

    scrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = "Additional scrape configurations (extended by other modules)";
    };

    blackbox = lib.mkOption {
           description = "Blackbox exporter configuration";
           default = {};
           type = lib.types.submodule {
             options = {
               enable = lib.mkEnableOption "Blackbox exporter for health checks";
             };
           };
         };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
      # 1. Blackbox Exporter Implementation (Using NixOS module)
      services.prometheus.exporters.blackbox = lib.mkIf cfg.blackbox.enable {
        enable = true;
        port = 9115;
        configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON {
          modules = {
            http_health_check = {
              prober = "http";
              timeout = "15s";
              http = {
                method = "GET";
                preferred_ip_protocol = "ip4";
                valid_status_codes = [ 200 ];
              };
            };
            # CORS preflight — proves the public webhook ingress chain
            # (Cloudflare proxy → tunnel → n8n webhook) end to end without
            # creating a lead. n8n answers preflights with 204.
            http_options_2xx = {
              prober = "http";
              timeout = "15s";
              http = {
                method = "OPTIONS";
                preferred_ip_protocol = "ip4";
                headers = {
                  "Origin" = "https://iheartwoodcraft.com";
                  "Access-Control-Request-Method" = "POST";
                };
                valid_status_codes = [ 200 204 ];
              };
            };
            # Unsigned POST — a 401 proves hwc-leads is up AND its HMAC
            # verification is active, without persisting anything.
            http_post_401 = {
              prober = "http";
              timeout = "15s";
              http = {
                method = "POST";
                preferred_ip_protocol = "ip4";
                headers = { "Content-Type" = "application/json"; };
                body = "{}";
                valid_status_codes = [ 401 ];
              };
            };
            # Auth-walled services: reachable = 200 or 401.
            http_2xx_or_401 = {
              prober = "http";
              timeout = "15s";
              http = {
                method = "GET";
                preferred_ip_protocol = "ip4";
                valid_status_codes = [ 200 401 ];
              };
            };
          };
        });
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
        # Blackbox probes — website + lead-pipeline health (see parts/alerts.nix
        # "website" group for the alerts these feed). All share the standard
        # blackbox relabel dance: target URL becomes ?target= param + instance
        # label; the scrape itself hits the local exporter on :9115.
        ++ (lib.optionals cfg.blackbox.enable (
          let
            blackboxRelabel = [
              { source_labels = [ "__address__" ]; target_label = "__param_target"; }
              { source_labels = [ "__param_target" ]; target_label = "instance"; }
              { target_label = "__address__"; replacement = "localhost:9115"; }
            ];
            probeJob = name: module: interval: targets: {
              job_name = name;
              metrics_path = "/probe";
              scrape_interval = interval;
              params.module = [ module ];
              static_configs = [{ inherit targets; }];
              relabel_configs = blackboxRelabel;
            };
          in [
            # Public website pages + GEO artifacts (through Cloudflare, like a visitor)
            (probeJob "probe-website" "http_health_check" "60s" [
              "https://iheartwoodcraft.com/"
              "https://iheartwoodcraft.com/calculator/"
              "https://iheartwoodcraft.com/deck-calculator/"
              "https://iheartwoodcraft.com/contact/"
              "https://iheartwoodcraft.com/sitemap.xml"
              "https://iheartwoodcraft.com/robots.txt"
              "https://iheartwoodcraft.com/llms.txt"
              "https://iheartwoodcraft.com/js/calculator.bundle.js"
            ])
            # Public webhook ingress (Cloudflare proxy → tunnel → n8n) via CORS preflight
            (probeJob "probe-webhook-ingress" "http_options_2xx" "60s" [
              "https://api.iheartwoodcraft.com/webhook/calculator-lead"
              "https://api.iheartwoodcraft.com/webhook/calculator-appointment"
            ])
            # hwc-leads liveness + HMAC enforcement (401 on unsigned POST)
            (probeJob "probe-leads-service" "http_post_401" "30s" [
              "http://127.0.0.1:11650/leads"
            ])
            # n8n engine + CMS API (auth-walled: 200 or 401 = alive)
            (probeJob "probe-n8n" "http_health_check" "30s" [
              "http://127.0.0.1:5678/healthz"
            ])
            (probeJob "probe-cms" "http_2xx_or_401" "60s" [
              "http://127.0.0.1:8095/api/health"
            ])
            # Umami analytics — local heartbeat + public collect ingress
            (probeJob "probe-umami" "http_health_check" "60s" [
              "http://127.0.0.1:3009/api/heartbeat"
              "https://stats.iheartwoodcraft.com/api/heartbeat"
            ])
          ]
        ))
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

    # Run prometheus, node-exporter, and blackbox-exporter as eric user for simplified permissions
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
    systemd.services.prometheus-blackbox-exporter = lib.mkIf cfg.blackbox.enable {
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
