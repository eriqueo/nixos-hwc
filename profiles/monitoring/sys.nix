# profiles/monitoring/sys.nix — monitoring role, NixOS lane
#
# Pure observability: prometheus, blackbox, cadvisor, grafana, homepage,
# uptime-kuma, alertmanager + receivers. (The n8n/automation stack lives
# in the business role.)
#
# WARNING: References age secrets (grafana-admin-password). All machines
# using this role MUST have their host key as a recipient in the
# corresponding .age files.
#
# REPLACES: profiles/monitoring.nix
# USED BY: see the machines table in flake.nix
{ lib, config, ... }:
{
  imports = [
    ../../domains/monitoring/index.nix
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

  # Homepage - Service dashboard
  hwc.monitoring.homepage.enable = lib.mkDefault true;

  # Uptime Kuma - Uptime monitoring
  hwc.monitoring.uptime-kuma.enable = lib.mkDefault true;

  # Alertmanager — alert routing to:
  #   hwc-notify     : hexagonal dispatcher (Discord + SMTP + future channels)
  #
  # The n8n `home:admin:alert-manager` workflow was deactivated
  # 2026-05-31 after Phase 1.6 cutover. The workflow row is preserved in
  # n8n's DB as the rollback path (re-activate + re-add the receiver
  # entry below to restore the old path). Don't delete it.
  hwc.monitoring.alertmanager = {
    enable = lib.mkDefault true;
    webhookReceivers = [
      {
        name = "hwc-notify";
        url = "http://localhost:11600/webhook/alertmanager";
        sendResolved = true;
      }
    ];
  };
}
