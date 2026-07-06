# profiles/business/sys.nix — business role, NixOS lane
#
# Heartwood operations: business subdomains + the n8n/mqtt automation
# stack. A coherent unit, portable to a future dedicated box.
# NOTE: expects domains/networking on the same machine (estimator webhook
# URL derives from hwc.networking.hosts.url).
#
# USED BY: see the machines table in flake.nix

{ config, lib, ... }:

{
  imports = [
    ../../domains/business/index.nix
    ../../domains/automation/index.nix
  ];

  #==========================================================================
  # BUSINESS SUBDOMAINS
  #==========================================================================

  # Unified lead pipeline (Phase 2, in progress 2026-05-31).
  hwc.business.leads.enable = true;

  hwc.business.website.enable = true;

  # hwc-publish: deploy static apps instantly, no rebuild needed.
  # Reserved range: 14000–14099 (on tailscale0)
  # Usage: hwc-publish <name> <dist/> [--port N]
  hwc.business.website.webapps.enable = true;

  # Firefly III personal finance
  hwc.business.firefly.enable = lib.mkDefault true;

  # Business database layer (hwc PostgreSQL database)
  hwc.business.databases.enable = lib.mkDefault true;

  # DataX — legacy postgres role + db that lead_scout connects to.
  # (FB scrape/classify pipeline migrated to hwc.server.ai.leadScout in 2026-05.)
  hwc.business.datax.enable = true;

  # DataX Monitor — DX1 agent-execution diagnostic dashboard (monitor.hwc.iheartwoodcraft.com)
  hwc.business.dataxMonitor.enable = true;

  # Paperless-NGX document management
  hwc.business.paperless.enable = lib.mkDefault true;

  # Morning briefing — daily Claude Code agent (6am MT)
  hwc.business.morningBriefing.enable = true;

  # Heartwood Estimate Assembler — React PWA
  # Port 13443 is pre-allocated outside the hwc-publish range (intentional —
  # the estimator is a first-class named app, not an ad-hoc published slot).
  # Access: https://<host>.ocelot-wahoo.ts.net:13443
  # Build:  sudo systemctl start estimator-build  (or: estimator-build alias)
  hwc.business.estimator = {
    enable     = true;
    port       = 13443;
    webhookUrl = config.hwc.networking.hosts.url { server = "main"; path = "/webhook/estimate-push"; };
    apiKeyFile = config.age.secrets.estimator-api-key.path;
  };

  #==========================================================================
  # AUTOMATION STACK (n8n + MQTT)
  #==========================================================================

  # n8n - Workflow automation for business + alert routing
  hwc.automation.n8n = {
    enable = lib.mkDefault true;
    port = 5678;
    dataDir = "/var/lib/hwc/n8n";
    owner.passwordHashFile = config.age.secrets.n8n-owner-password-hash.path;
    # Workflow secrets (loaded from agenix)
    secrets = {
      estimatorApiKeyFile = config.age.secrets.estimator-api-key.path;
      jobtreadGrantKeyFile = config.age.secrets.jobtread-grant-key.path;
      slackWebhookUrlFile = config.age.secrets.slack-webhook-url.path;
      discordWebhookUrlFile = config.age.secrets.discord-webhook-url.path;
      anthropicApiKeyFile = config.age.secrets.nanoclaw-anthropic-key.path;
      hwcLeadsHmacFile = config.age.secrets.hwc-leads-hmac-secret.path;
      # Taxonomy-aligned Gotify tokens → env vars GOTIFY_TOKEN_{HWC_OPS, HWC_FINANCIAL, ...}
      # TODO(backlog §10.1): this discovery logic belongs inside the n8n module.
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

  # MQTT broker for event-driven automation (Frigate -> n8n)
  hwc.automation.mqtt = {
    enable = true;
    webhookBridge = {
      enable = true;
      topic = "frigate/events";
      webhookUrl = "http://127.0.0.1:5678/webhook/frigate-events";
    };
  };
}
