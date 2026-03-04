# profiles/monitoring.nix
#
# Monitoring profile — imports monitoring domain and enables all services.
# TODO Phase 10: machines should import domains/monitoring directly and set their own values.
{ lib, config, ... }:
{
  imports = [
    ../domains/monitoring/index.nix
    ../domains/automation/index.nix
  ];

  #==========================================================================
  # MONITORING SERVICES
  #==========================================================================

  # Prometheus - Metrics collection with 90-day retention
  hwc.server.native.monitoring.prometheus = {
    enable = lib.mkDefault true;
    retention = "90d";
    blackbox.enable = lib.mkDefault true;
  };

  # cAdvisor - Container metrics
  hwc.server.native.monitoring.cadvisor.enable = lib.mkDefault true;

  # Exportarr - Arr apps metrics (Sonarr/Radarr/Lidarr/Prowlarr)
  hwc.server.native.monitoring.exportarr.enable = lib.mkDefault true;

  # Grafana - Dashboards and visualization
  hwc.server.native.monitoring.grafana = {
    enable = lib.mkDefault true;
    domain = "grafana.hwc.local";
    adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  };

  # Alertmanager - Alert routing to n8n webhooks
  hwc.server.native.monitoring.alertmanager = {
    enable = lib.mkDefault true;
    # Webhook receivers route alerts to n8n for processing
    webhookReceivers = [
      {
        name = "n8n-webhook";
        url = "https://hwc.ocelot-wahoo.ts.net:2443/webhook/alertmanager";
        sendResolved = true;
      }
    ];
  };

  # n8n - Workflow automation for alert routing
  hwc.server.native.n8n = {
    enable = lib.mkDefault true;
    port = 5678;
    dataDir = "/var/lib/hwc/n8n";
    webhookUrl = "https://hwc.ocelot-wahoo.ts.net:2443";
    owner.passwordHashFile = config.age.secrets.n8n-owner-password-hash.path;
  };
}
