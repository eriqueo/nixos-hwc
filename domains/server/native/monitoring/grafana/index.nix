# domains/server/monitoring/grafana/index.nix
#
# GRAFANA - Dashboards and visualization
#
# NAMESPACE: hwc.server.monitoring.grafana.*
#
# DEPENDENCIES:
#   - hwc.server.native.monitoring.prometheus (datasource)
#   - hwc.paths.state (data directory)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.native.monitoring.grafana;
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
    services.grafana = {
      enable = true;
      dataDir = cfg.dataDir;  # Override default /var/lib/grafana
      settings = {
        server = {
          http_port = cfg.port;
          domain = cfg.domain;
          root_url = "https://${config.hwc.services.shared.rootHost}:4443";  # Via Caddy reverse proxy
        };

        paths = {
          data = cfg.dataDir;
          logs = "${paths.state}/grafana/logs";
          plugins = "${cfg.dataDir}/plugins";
        };

        security = lib.mkIf (cfg.adminPasswordFile != null) {
          admin_password = "$__file{${cfg.adminPasswordFile}}";
        };
      };
    };

    # Prometheus datasource provisioning
    services.grafana.provision = lib.mkIf config.hwc.server.native.monitoring.prometheus.enable {
      enable = true;

      datasources.settings = {
        apiVersion = 1;
        # Prune stale provisioned datasources to prevent drift
        deleteDatasources = [];  # Explicit empty list
        datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            uid = "prometheus";
            url = "http://localhost:${toString config.hwc.server.native.monitoring.prometheus.port}";
            access = "proxy";
            isDefault = true;
            # Mark as provisioned to enable pruning
            editable = false;
          }
        ];
      };

      # Dashboard provisioning
      dashboards.settings = lib.mkIf cfg.dashboards.enable {
        apiVersion = 1;
        providers = [{
          name = "hwc-dashboards";
          type = "file";
          updateIntervalSeconds = 30;
          options.path = "${cfg.dashboards.dashboardsPath}";
        }];
      };
    };

    # Run grafana as eric user for simplified permissions
    systemd.services.grafana = {
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
        # Override state directory to use our custom path
        StateDirectory = lib.mkForce "hwc/grafana";
        WorkingDirectory = lib.mkForce cfg.dataDir;
        # Disable user namespace isolation so eric can access directories
        PrivateUsers = lib.mkForce false;
      };
    };

    # Ensure grafana data directory exists with proper permissions (owned by eric)
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 eric users -"
      "d ${cfg.dataDir}/plugins 0755 eric users -"
      "d ${cfg.dataDir}/png 0755 eric users -"
      "d ${paths.state}/grafana/logs 0755 eric users -"
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || (cfg.port != 0);
        message = "Grafana port must be configured";
      }
      {
        assertion = !cfg.enable || (cfg.dataDir != "");
        message = "Grafana data directory must be configured";
      }
      {
        assertion = !cfg.enable || (cfg.domain != "");
        message = "Grafana domain must be configured";
      }
      {
        assertion = !cfg.enable || config.hwc.server.native.monitoring.prometheus.enable;
        message = "Grafana requires Prometheus to be enabled (hwc.server.native.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
