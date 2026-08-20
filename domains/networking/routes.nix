{ lib, config, ... }:
let
  mcpCfg = config.hwc.ai.mcp;
  nixosDir = config.hwc.paths.nixos;
in
{
  # Routing standard: `mode = "vhost"` is the default for any new route —
  # served at <name>.<vhostDomain> behind the *.hwc.iheartwoodcraft.com
  # wildcard cert. It avoids the whole class of subpath breakage (apps that
  # ignore their URL base, absolute asset paths, WebSocket upgrades) and keeps
  # one service = one hostname.
  #
  # `mode = "subpath"` is now the exception and needs a reason. The remaining
  # subpath routes below are each held for a stated cause: an external consumer
  # pins the URL (webhook, couchdb, mcp), or the route is a deliberate
  # convenience alias for a service that already has a vhost (jellyseerr-subpath).
  # The rest are simply un-migrated — converting one means clearing its in-app
  # URL base in the same change, or it will redirect to a path that no longer routes.
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

    # Navidrome - name-based vhost. ND_BASEURL is cleared in the same commit
    # (domains/media/navidrome-container/sys.nix): navidrome 302s root to its
    # base, so a stale "/music" would bounce every request off this vhost.
    {
      name = "navidrome";
      mode = "vhost";
      upstream = "http://127.0.0.1:4533";
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

    # SABnzbd - name-based vhost. Two app-side facts move WITH this route and
    # cannot lag it (domains/media/sabnzbd/parts/config.nix): `url_base` must be
    # cleared, and `host_whitelist` must gain sabnzbd.<vhostDomain> or SAB
    # answers every request with "Hostname verification failed".
    {
      name = "sabnzbd";
      mode = "vhost";
      upstream = "http://127.0.0.1:8081";
    }

    # qBittorrent - name-based vhost. No app-side change was needed: it already
    # expected root (the old route stripped /qbt rather than passing it), and
    # `WebUI\ServerDomains=*` in qBittorrent.conf already accepts any forwarded
    # Host — unlike SABnzbd, which had to have its allowlist widened.
    {
      name = "qbittorrent";
      mode = "vhost";
      upstream = "http://127.0.0.1:8080";
    }

    # slskd - name-based vhost
    {
      name = "slskd";
      mode = "vhost";
      upstream = "http://127.0.0.1:5031";
    }

    # *arr stack - name-based vhosts. The in-app URL base is cleared in each
    # app's sys.nix (<APP>__URLBASE) and parts/config.nix (config.xml), so these
    # serve at root; nothing here may reintroduce a path prefix.
    {
      name = "sonarr";
      mode = "vhost";
      upstream = "http://127.0.0.1:8989";
    }

    {
      name = "radarr";
      mode = "vhost";
      upstream = "http://127.0.0.1:7878";
    }

    {
      name = "lidarr";
      mode = "vhost";
      upstream = "http://127.0.0.1:8686";
    }

    {
      name = "readarr";
      mode = "vhost";
      upstream = "http://127.0.0.1:8787";
    }

    {
      name = "prowlarr";
      mode = "vhost";
      upstream = "http://127.0.0.1:9696";
    }

    # LazyLibrarian (books) - name-based vhost. `hwc.media.books.httpRoot` is
    # cleared in the same commit; unlike the SPA-backed apps, LazyLibrarian
    # genuinely 404s at "/" while its http_root is set, so the two halves
    # cannot be staged across separate rebuilds in either order.
    {
      name = "books";
      mode = "vhost";
      upstream = "http://127.0.0.1:5299";
    }

    # Audiobookshelf - name-based vhost. The old `needsUrlBase = true` claimed a
    # "hardcoded /audiobookshelf/ base path"; that was wrong. No base path is
    # configured anywhere (no ROUTER_BASE_PATH in the container env), and the
    # app answers 200 at BOTH / and /audiobookshelf/ on :13378 because its SPA
    # serves index.html for any path — which is exactly what made the false
    # claim look true. Root is the real mount point, so no app-side change.
    {
      name = "audiobookshelf";
      mode = "vhost";
      upstream = "http://127.0.0.1:13378";
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

    # Calibre content server - name-based vhost. No app-side change: the old
    # route stripped /calibre, so the server was already answering at root.
    # Distinct from the `calibre` vhost above (:8083, calibre-web) — two
    # different services, two names, do not collapse them.
    {
      name = "calibre-server";
      mode = "vhost";
      upstream = "http://127.0.0.1:8090";
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
      name = "transcripts";
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

    # Paperless-NGX - name-based vhost. Django validates request Origin against
    # PAPERLESS_CSRF_TRUSTED_ORIGINS, so this route and the origin built in
    # domains/business/paperless/parts/config.nix must name the same host or
    # reads keep working while every write fails CSRF.
    {
      name = "paperless";
      mode = "vhost";
      upstream = "http://127.0.0.1:8102";
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

    # home_scout — real estate intelligence dashboard, name-based vhost
    # (home-scout.hwc.iheartwoodcraft.com). Proxies to the unified home-scout
    # server on :8421 (serves SPA + REST API + /mcp).
    {
      name = "home-scout";
      mode = "vhost";
      upstream = "http://127.0.0.1:8421";
    }

    # research_scout — research/paper intelligence dashboard, name-based vhost
    # (research-scout.hwc.iheartwoodcraft.com). Proxies to the unified
    # research-scout server on :8422 (serves SPA + REST API + /mcp).
    {
      name = "research-scout";
      mode = "vhost";
      upstream = "http://127.0.0.1:8422";
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
