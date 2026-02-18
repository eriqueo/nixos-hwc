{ lib, config, ... }:
let
  mcpCfg = config.hwc.ai.mcp;
in
{
  hwc.server.shared.routes = [
    # Jellyfin - port mode (reliable, no base URL config needed)
    {
      name = "jellyfin";
      mode = "port";
      port = 6443;  # Dedicated port for Jellyfin
      upstream = "http://127.0.0.1:8096";
    }

    # Jellyseerr - port mode (doesn't work well with subpaths)
    {
      name = "jellyseerr";
      mode = "port";
      port = 5543;  # Dedicated port for Jellyseerr
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

    # Immich - port mode (subpath-hostile)
    {
      name = "immich";
      mode = "port";
      port = 7443;
      upstream = "http://127.0.0.1:2283";
    }

    # Frigate - port mode (subpath-hostile, GPU-accelerated with TensorRT)
    {
      name = "frigate";
      mode = "port";
      port = 5443;
      upstream = "http://127.0.0.1:5001";  # GPU-accelerated with CUDA/TensorRT support
    }

    # Grafana - port mode (monitoring dashboards)
    {
      name = "grafana";
      mode = "port";
      port = 4443;
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

    # slskd - port mode with corrected upstream
    {
      name = "slskd";
      mode = "port";
      port = 8443;
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

    # Calibre - port mode for desktop interface (KasmVNC)
    {
      name = "calibre";
      mode = "port";
      port = 1443;  # Dedicated port for Calibre desktop
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

    # ntfy notification server - preserve path (ntfy handles subpath natively)
    {
      name = "ntfy";
      mode = "subpath";
      path = "/notify";
      upstream = "http://127.0.0.1:2586";
      needsUrlBase = false;  # ntfy works with subpath without URL base
    }

    # Tdarr - port mode (WebSocket intensive, subpath issues)
    {
      name = "tdarr";
      mode = "port";
      port = 8267;  # Use 8267 externally, forward to internal 8265
      upstream = "http://127.0.0.1:8265";
    }

    # Organizr - Root dashboard on dedicated port
    {
      name = "organizr";
      mode = "port";
      port = 9443;  # Dedicated port for Organizr dashboard
      upstream = "http://127.0.0.1:9983";
    }

    # Pinchflat - YouTube subscription manager (port mode - subpath-hostile)
    {
      name = "pinchflat";
      mode = "port";
      port = 8943;  # Dedicated port for Pinchflat
      upstream = "http://127.0.0.1:8945";
    }

    # Transcript API - preserve path (FastAPI routes expect /api prefix)
    {
      name = "transcript-api";
      mode = "subpath";
      path = "/api";
      upstream = "http://127.0.0.1:8099";
      needsUrlBase = true;  # Preserve /api prefix - app routes expect it
      headers = { "X-Forwarded-Prefix" = "/api"; };
    }

    # YouTube Transcripts API - FastAPI transcript extraction service
    {
      name = "yt-transcripts-api";
      mode = "subpath";
      path = "/api/transcripts";
      upstream = "http://127.0.0.1:8100";
      needsUrlBase = false;  # Strip prefix - app routes at root
      headers = {
        "X-Forwarded-For" = "{remote_host}";
        "X-Forwarded-Proto" = "{scheme}";
      };
    }

    # YouTube Videos API - FastAPI video download service
    {
      name = "yt-videos-api";
      mode = "subpath";
      path = "/api/videos";
      upstream = "http://127.0.0.1:8101";
      needsUrlBase = false;  # Strip prefix - app routes at root
      headers = {
        "X-Forwarded-For" = "{remote_host}";
        "X-Forwarded-Proto" = "{scheme}";
      };
    }

    # Open WebUI - AI chat interface (port mode - subpath-hostile SvelteKit app)
    {
      name = "openwebui";
      mode = "port";
      port = 3443;  # Dedicated port for Open WebUI
      upstream = "http://127.0.0.1:3001";  # Changed from 3000 to avoid conflict with Grafana
    }

    # Local Workflows API - HTTP API for AI workflows (Sprint 5.4)
    # Provides chat, cleanup, journal, autodoc endpoints
    {
      name = "workflows-api";
      mode = "subpath";
      path = "/workflows";
      upstream = "http://127.0.0.1:6021";
      needsUrlBase = false;  # API handles requests at root
      headers = { "X-Forwarded-Prefix" = "/workflows"; };
    }

    # n8n - Workflow automation platform (port mode - subpath not properly supported)
    # Used for Alertmanager webhook handling and Slack notifications
    {
      name = "n8n";
      mode = "port";
      port = 2443;
      upstream = "http://127.0.0.1:5678";
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
