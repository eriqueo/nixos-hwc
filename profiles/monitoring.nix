# profiles/monitoring.nix
#
# Monitoring profile — imports monitoring domain and enables all services.
#
# WARNING: References age secrets (grafana-admin-password, n8n-owner-password-hash).
# All machines importing this profile MUST have their host key as a recipient
# in the corresponding .age files. n8n-owner-password-hash.age currently has
# only 1 recipient — re-encrypt to include XPS key if XPS uses this profile.
#
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
  hwc.monitoring.prometheus = {
    enable = lib.mkDefault true;
    retention = "90d";
    blackbox.enable = lib.mkDefault true;
  };

  # cAdvisor - Container metrics
  hwc.monitoring.cadvisor.enable = lib.mkDefault true;

  # Exportarr - Arr apps metrics (Sonarr/Radarr/Lidarr/Prowlarr)
  hwc.monitoring.exportarr.enable = lib.mkDefault true;

  # Grafana - Dashboards and visualization
  hwc.monitoring.grafana = {
    enable = lib.mkDefault true;
    domain = "grafana.hwc.local";
    adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  };

  # Alertmanager - Alert routing to n8n webhooks
  hwc.monitoring.alertmanager = {
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
  hwc.automation.n8n = {
    enable = lib.mkDefault true;
    port = 5678;
    dataDir = "/var/lib/hwc/n8n";
    webhookUrl = "https://hwc.ocelot-wahoo.ts.net:2443";
    owner.passwordHashFile = config.age.secrets.n8n-owner-password-hash.path;
    # Funnel disabled - using Caddy on port 2443 instead (avoids conflict with slskd on 8443)
    funnel.enable = false;
    # Estimator integration credentials
    extraEnv = {
      ESTIMATOR_API_KEY = "T8SLQ1N8wxg9tlwRa8FG1p17ZDUj3w1NwBKVVwQVxWQ=";
      # TODO: Move ESTIMATOR_API_KEY to agenix secret
    };
  };
}
