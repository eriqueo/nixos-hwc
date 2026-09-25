# profiles/monitoring/sys.nix — monitoring role, NixOS lane
#
# The central observability stack: prometheus (fleet collector), grafana,
# homepage, alertmanager + receivers. Per-host exporters are not here — the
# server role runs them on every serving host. (The n8n/automation stack lives in the
# business role. Uptime Kuma decommissioned 2026-07-09 — the declarative
# blackbox probes + Grafana service-health dashboard replaced it.)
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

  # The central Prometheus (90-day retention). It collects every serving
  # host's exports — node/blackbox agent, cAdvisor, podman-exporter, exportarr,
  # Frigate — which the server role and the machines enable where they run.
  hwc.monitoring.prometheus = {
    enable = lib.mkDefault true;
    retention = "90d";
  };

  # Grafana - Dashboards and visualization
  hwc.monitoring.grafana = {
    enable = lib.mkDefault true;
    domain = "grafana.hwc.local";
    adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  };

  # Homepage - Service dashboard
  hwc.monitoring.homepage.enable = lib.mkDefault true;

  # Alertmanager — alert routing to:
  #   hwc-notify     : hexagonal dispatcher (Discord + SMTP + future channels)
  #
  # The n8n `home:admin:alert-manager` workflow was deactivated 2026-05-31
  # after Phase 1.6 cutover and DELETED from n8n 2026-07-09 (along with the
  # cross-service-health + mail-health routers) — Alertmanager → hwc-notify is
  # the sole path now. Rollback = rebuild the workflow from the git history of
  # domains/automation/n8n/parts/workflows/.
  hwc.monitoring.alertmanager = {
    enable = lib.mkDefault true;
    webhookReceivers = [
      {
        name = "hwc-notify";
        url = "${config.hwc.notifications.notify.url}/webhook/alertmanager";
        sendResolved = true;
      }
    ];
  };
}
