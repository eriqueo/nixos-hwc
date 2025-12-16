{ lib, config, ... }:
let
  cfg = config.hwc.features.monitoring;
   imports = [
      ../domains/server/monitoring/index.nix
    ];
in
{
  options.hwc.features.monitoring = {
    enable = lib.mkEnableOption "monitoring services (Prometheus, Grafana)";
  };

  config = lib.mkIf cfg.enable {
    #==========================================================================
    # MONITORING SERVICES
    #==========================================================================

    # Prometheus - Metrics collection with 90-day retention
    hwc.server.monitoring.prometheus = {
      enable = true;
      retention = "90d";
      blackbox.enable = true;
    };

    # cAdvisor - Container metrics
    hwc.server.monitoring.cadvisor.enable = lib.mkDefault true;

    # Exportarr - Arr apps metrics (Sonarr/Radarr/Lidarr/Prowlarr)
    hwc.server.monitoring.exportarr.enable = lib.mkDefault true;

    # Frigate exporter - Disabled until working image is found
    # hwc.server.frigate.exporter.enable = lib.mkDefault true;

    # Grafana - Dashboards and visualization
    hwc.server.monitoring.grafana = {
      enable = true;
      domain = "grafana.hwc.local";
      adminPasswordFile = config.age.secrets.grafana-admin-password.path;
    };

    # Alertmanager - Alert routing to n8n webhooks
    hwc.server.monitoring.alertmanager = {
      enable = true;
      # Webhook receivers configured post-deployment via n8n
      # webhookReceivers = [
      #   {
      #     name = "n8n-slack";
      #     url = "https://${config.hwc.services.shared.rootHost}/n8n/webhook/alertmanager";
      #     sendResolved = true;
      #   }
      # ];
    };

    # n8n - Workflow automation for alert routing
    hwc.server.n8n = {
      enable = true;
      port = 5678;
      dataDir = "/var/lib/hwc/n8n";
      webhookUrl = "https://hwc.ocelot-wahoo.ts.net:2443";
    };
  };
}
