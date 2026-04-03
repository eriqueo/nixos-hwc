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

  # Homepage - Service dashboard
  hwc.monitoring.homepage.enable = lib.mkDefault true;

  # Uptime Kuma - Uptime monitoring
  hwc.monitoring.uptime-kuma.enable = lib.mkDefault true;

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
      {
        name = "gotify-bridge";
        url = "http://localhost:9095";
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
    # Workflow secrets (loaded from agenix)
    secrets = {
      estimatorApiKeyFile = config.age.secrets.estimator-api-key.path;
      jobtreadGrantKeyFile = config.age.secrets.jobtread-grant-key.path;
      slackWebhookUrlFile = config.age.secrets.slack-webhook-url.path;
      anthropicApiKeyFile = config.age.secrets.nanoclaw-anthropic-key.path;
      # Taxonomy-aligned Gotify tokens → env vars GOTIFY_TOKEN_{HWC_OPS, HWC_FINANCIAL, ...}
      gotifyTokenFiles = let api = config.hwc.secrets.api; in
        lib.filterAttrs (_: v: v != null) {
          "hwc-ops"       = api."gotify-hwc-ops" or null;
          "hwc-financial"  = api."gotify-hwc-financial" or null;
          "hwc-dev"        = api."gotify-hwc-dev" or null;
          "hwc-admin"      = api."gotify-hwc-admin" or null;
          "home-security"  = api."gotify-home-security" or null;
          "home-media"     = api."gotify-home-media" or null;
          "home-social"    = api."gotify-home-social" or null;
          "home-admin"     = api."gotify-home-admin" or null;
        };
    };
    # MCP bridge — expose n8n workflows as MCP tools via HTTP for Claude.ai
    mcpBridge.enable = true;
    # Non-secret workflow configuration
    extraEnv = {
      # work_lead_response: Twilio sender number
      TWILIO_PHONE_NUMBER = "+14064378700";
      # work_estimate_router: PostgREST endpoint (has fallback)
      POSTGRES_REST_URL = "http://localhost:3000";
      # work_content_calendar: Google Drive folder for calendar content
      DRIVE_CALENDAR_FOLDER_ID = "1xkrYYSbZzX16Gjo7VbGazgLMkS12u06I";
    };
  };
}
