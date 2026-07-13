{ lib, config, ... }:
let
  mcpCfg = config.hwc.ai.mcp;
  nixosDir = config.hwc.paths.nixos;
in
{
  hwc.networking.shared.routes = [
    # Jellyfin - name-based vhost (jellyfin.hwc.iheartwoodcraft.com)
    {
      name = "jellyfin";
      mode = "vhost";
      upstream = "http://127.0.0.1:8096";
    }

    # Jellyseerr - name-based vhost (applicationUrl updated in jellyseerr settings)
    {
      name = "jellyseerr";
      mode = "vhost";
      upstream = "http://127.0.0.1:5055";
    }

    # Jellyseerr - convenience subpath (strips prefix for client assets)
    {
      name = "jellyseerr-subpath";
      mode = "subpath";
      path = "/jellyseerr";
      upstream = "http://127.0.0.1:5055";
      needsUrlBase = false;
      headers = { "X-Forwarded-Prefix" = "/jellyseerr"; };
    }

    # Navidrome - preserve path (URL base set in app)
    {
      name = "navidrome";
      mode = "subpath";
      path = "/music";
      upstream = "http://127.0.0.1:4533";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/music"; };
    }

    # Immich - name-based vhost (subpath-hostile; host derived from request)
    {
      name = "immich";
      mode = "vhost";
      upstream = "http://127.0.0.1:2283";
    }

    # Frigate - name-based vhost (subpath-hostile, GPU-accelerated with TensorRT)
    {
      name = "frigate";
      mode = "vhost";
      upstream = "http://127.0.0.1:5000";  # GPU-accelerated with CUDA/TensorRT support
    }

    # Grafana - name-based vhost (root_url updated in grafana module)
    {
      name = "grafana";
      mode = "vhost";
      upstream = "http://127.0.0.1:3000";
    }

    # Sabnzbd - preserve path (URL base set in app)
    {
      name = "sabnzbd";
      mode = "subpath";
      path = "/sab";
      upstream = "http://127.0.0.1:8081";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/sab"; };
    }

    # qBittorrent - strip path (app expects root despite URL_BASE)
    {
      name = "qbittorrent";
      mode = "subpath";
      path = "/qbt";
      upstream = "http://127.0.0.1:8080";
      needsUrlBase = false;
      headers = { "X-Forwarded-Prefix" = "/qbt"; };
    }

    # slskd - name-based vhost
    {
      name = "slskd";
      mode = "vhost";
      upstream = "http://127.0.0.1:5031";
    }

    # Sonarr - preserve path (URL base set in app)
    {
      name = "sonarr";
      mode = "subpath";
      path = "/sonarr";
      upstream = "http://127.0.0.1:8989";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/sonarr"; };
    }

    # Radarr - preserve path (URL base set in app)
    {
      name = "radarr";
      mode = "subpath";
      path = "/radarr";
      upstream = "http://127.0.0.1:7878";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/radarr"; };
    }

    # Lidarr - preserve path (URL base set in app)
    {
      name = "lidarr";
      mode = "subpath";
      path = "/lidarr";
      upstream = "http://127.0.0.1:8686";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/lidarr"; };
    }

    # Readarr - preserve path (URL base set in app)
    {
      name = "readarr";
      mode = "subpath";
      path = "/readarr";
      upstream = "http://127.0.0.1:8787";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/readarr"; };
    }

    # Prowlarr - preserve path (URL base set in app)
    {
      name = "prowlarr";
      mode = "subpath";
      path = "/prowlarr";
      upstream = "http://127.0.0.1:9696";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/prowlarr"; };
    }

    # LazyLibrarian (books) - preserve path (Web Root setting in app)
    {
      name = "books";
      mode = "subpath";
      path = "/books";
      upstream = "http://127.0.0.1:5299";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/books"; };
    }

    # Audiobookshelf - audiobook and podcast server
    {
      name = "audiobookshelf";
      mode = "subpath";
      path = "/audiobookshelf";
      upstream = "http://127.0.0.1:13378";
      needsUrlBase = true;  # Audiobookshelf has hardcoded /audiobookshelf/ base path
      headers = { "X-Forwarded-Prefix" = "/audiobookshelf"; };
    }

    # Mousehole - MAM seedbox IP updater (runs through Gluetun VPN)
    {
      name = "mousehole";
      mode = "vhost";
      upstream = "http://127.0.0.1:5010";
    }

    # Calibre - name-based vhost (desktop interface, KasmVNC)
    {
      name = "calibre";
      mode = "vhost";
      upstream = "http://127.0.0.1:8083";
    }

    # Calibre content server - subpath for ebook access
    {
      name = "calibre-server";
      mode = "subpath";
      path = "/calibre";
      upstream = "http://127.0.0.1:8090";
      needsUrlBase = false;  # Content server works without URL base
      headers = { "X-Forwarded-Prefix" = "/calibre"; };
    }

    # CouchDB (Obsidian LiveSync) - strip /sync prefix
    {
      name = "couchdb";
      mode = "subpath";
      path = "/sync";
      upstream = "http://127.0.0.1:5984";
      needsUrlBase = false;  # Strip /sync prefix - CouchDB doesn't support URL base
      headers = {
        Authorization = "{http.request.header.authorization}";
        Upgrade       = "{http.request.header.upgrade}";
        Connection    = "{http.request.header.connection}";
      };
    }

    # Tdarr - name-based vhost (WebSocket intensive, subpath issues)
    {
      name = "tdarr";
      mode = "vhost";
      upstream = "http://127.0.0.1:8265";
    }

    # Organizr - name-based vhost (root dashboard)
    {
      name = "organizr";
      mode = "vhost";
      upstream = "http://127.0.0.1:9983";
    }

    # Pinchflat - YouTube subscription manager (subpath-hostile)
    {
      name = "pinchflat";
      mode = "vhost";
      upstream = "http://127.0.0.1:8945";
    }

    # YouTube Transcripts API - FastAPI transcript extraction service
    # (n8n calls this via loopback :8100, not the public URL)
    {
      name = "yt-transcripts-api";
      mode = "vhost";
      upstream = "http://127.0.0.1:8100";
    }

    # n8n - Workflow automation platform — HELD on port mode.
    # Host-sensitive: N8N_EDITOR_BASE_URL/WEBHOOK_URL + the public Cloudflare
    # tunnel + webhook URLs referenced across notifications/arr/mail modules.
    # Migrating needs a coordinated cutover of all of those — separate change.
    {
      name = "n8n";
      mode = "port";
      port = 2443;
      upstream = "http://127.0.0.1:5678";
      # Strip port from Origin header - n8n validates origin against hostname only
      headers = { Origin = "https://hwc-server.ocelot-wahoo.ts.net"; };
    }

    # Firefly III - name-based vhost (APP_URL updated in firefly module).
    # On :443 the external port is standard https, so the X-Forwarded-Port
    # override is no longer needed.
    {
      name = "firefly";
      mode = "vhost";
      upstream = "http://127.0.0.1:8085";
    }

    # Firefly-Pico - name-based vhost (appUrl updated in firefly module)
    {
      name = "firefly-pico";
      mode = "vhost";
      upstream = "http://127.0.0.1:8086";
    }

    # Firefly III data importer (CSV / SimpleFIN) - name-based vhost
    {
      name = "firefly-import";
      mode = "vhost";
      upstream = "http://127.0.0.1:8087";
    }

    # Paperless-NGX - document management (preserve path)
    {
      name = "paperless";
      mode = "subpath";
      path = "/docs";
      upstream = "http://127.0.0.1:8102";
      needsUrlBase = true;
      headers = { "X-Forwarded-Prefix" = "/docs"; };
    }

    # Generic webhook endpoint - forwards to n8n for external integrations (Slack, etc.)
    # Preserves full path so n8n receives /webhook/* for routing
    {
      name = "webhook";
      mode = "subpath";
      path = "/webhook";
      upstream = "http://127.0.0.1:5678";
      needsUrlBase = true;  # Preserve /webhook prefix - n8n expects it for routing
      headers = { "X-Forwarded-Prefix" = "/webhook"; };
    }

    # CloudBeaver - name-based vhost (subpath-hostile)
    {
      name = "cloudbeaver";
      mode = "vhost";
      upstream = "http://127.0.0.1:8978";
    }

    # Bathroom Calculator - static React app for iheartwoodcraft.com embedding
    # CORS enabled for cross-origin embedding on WordPress
    {
      name = "calculator";
      mode = "vhost";
      root = "${nixosDir}/domains/business/website/calculator/app/dist";
    }
    # Heartwood CMS — name-based vhost (content management dashboard)
    {
      name = "heartwood-cms";
      mode = "vhost";
      upstream = "http://127.0.0.1:8095";
    }

    # Morning Briefing — daily dashboard for Heartwood Craft ops.
    # api: same-origin /mcp proxy to the local gateway so the TODAY queue's
    # action buttons (dismiss/complete/agent via hwc_today) work from the SPA.
    {
      name = "briefing";
      mode = "vhost";
      root = "${nixosDir}/domains/business/morning-briefing/dashboard";
      api = { path = "/mcp"; upstream = "http://127.0.0.1:6200"; };
    }

    # Refinery — read-only Kanban board for the gauntlet hopper, name-based
    # vhost (refinery.hwc.iheartwoodcraft.com). Proxies the board service on
    # :8060 (hwc.automation.refinery).
    {
      name = "refinery";
      mode = "vhost";
      upstream = "http://127.0.0.1:8060";
    }

    # lead_scout — intelligence pipeline dashboard, name-based vhost
    # (lead-scout.hwc.iheartwoodcraft.com). Proxies to the unified lead-scout
    # server on :8420 (serves SPA + REST API + chat + /mcp).
    {
      name = "lead-scout";
      mode = "vhost";
      upstream = "http://127.0.0.1:8420";
    }

    # datax-monitor — DX1 agent-execution diagnostic dashboard, name-based vhost
    # (monitor.hwc.iheartwoodcraft.com). One Hono server on :4400 serves both the
    # React SPA (ui/dist) and the REST API (/api/*). Module:
    # domains/business/datax-monitor.
    {
      name = "monitor";
      mode = "vhost";
      upstream = "http://127.0.0.1:4400";
    }

    # lead_scout API — MCP + REST backend — HELD on port mode.
    # Same :8420 backend as lead-scout; the laptop's Claude MCP config may pin
    # this URL, so migrate it together with the other MCP endpoints.
    {
      name = "lead-scout-api";
      mode = "port";
      port = 22443;
      upstream = "http://127.0.0.1:8420";
    }

    # sr_analyzer — name-based vhost (local Kanban for DataX SR triage).
    # Standalone Podman container at ~/600_apps/sr_analyzer (NOT a NixOS module).
    {
      name = "sr_analyzer";
      mode = "vhost";
      upstream = "http://127.0.0.1:8788";
    }

    # llama.cpp GPU server — LFM2-2.6B Q4 on the Quadro P1000 (loopback clients)
    {
      name = "llama-gpu";
      mode = "vhost";
      upstream = "http://127.0.0.1:11500";
    }

    # llama.cpp CPU server — LFM2-24B-A2B Q4 in host RAM (loopback clients)
    {
      name = "llama-cpu";
      mode = "vhost";
      upstream = "http://127.0.0.1:11501";
    }

  ] ++ lib.optionals (config.hwc.secrets.vaultwarden.enable or false) [
    # Vaultwarden - name-based vhost (DOMAIN updated in vaultwarden module)
    {
      name = "vaultwarden";
      mode = "vhost";
      upstream = "http://127.0.0.1:${toString config.hwc.secrets.vaultwarden.port}";
    }
  ] ++ lib.optionals mcpCfg.reverseProxy.enable [
    # MCP (Model Context Protocol) - AI filesystem access via HTTP proxy
    # Enabled when hwc.ai.mcp.reverseProxy.enable = true
    # Provides LLM access to ~/.nixos directory via Caddy reverse proxy
    {
      name = "mcp";
      mode = "subpath";
      path = mcpCfg.reverseProxy.path;
      upstream = "http://${mcpCfg.proxy.host}:${toString mcpCfg.proxy.port}";
      needsUrlBase = false;  # MCP proxy handles requests at root
      headers = {
        "X-Forwarded-Prefix" = mcpCfg.reverseProxy.path;
      };
    }
  ];
}
