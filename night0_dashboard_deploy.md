# Night 0: Homepage + Uptime Kuma Deployment Report

**Date**: 2026-03-27
**Status**: NixOS config prepared, pending `nixos-rebuild switch`

---

## 1. Homepage (gethomepage)

### Container Details

| Property | Value |
|----------|-------|
| Image | `ghcr.io/gethomepage/homepage:latest` |
| Internal port | `3080` → container `3000` |
| Caddy TLS port | `17443` |
| Data directory | `/var/lib/homepage` |
| URL | `https://hwc.ocelot-wahoo.ts.net:17443` |

### Volumes

- `/var/lib/homepage:/app/config` — YAML config files
- `/run/podman/podman.sock:/var/run/docker.sock:ro` — Container auto-discovery

### NixOS Config

- Module: `domains/monitoring/homepage/index.nix`
- Options namespace: `hwc.monitoring.homepage.*`
- Enabled in: `profiles/monitoring.nix`

### Config File Locations

All YAML configs are NixOS-managed (deployed via activation script to `/var/lib/homepage/`):

- `domains/monitoring/homepage/parts/settings.yaml` — Theme, layout
- `domains/monitoring/homepage/parts/services.yaml` — All services grouped (Business, Infrastructure, Media, Home)
- `domains/monitoring/homepage/parts/widgets.yaml` — System resources, search, datetime
- `domains/monitoring/homepage/parts/docker.yaml` — Podman socket for container status
- `domains/monitoring/homepage/parts/bookmarks.yaml` — Empty (ready for customization)

### Service Groups

- **Business** (4): JobTread MCP, Estimator API, n8n, Paperless
- **Infrastructure** (7): Caddy, Authentik, Grafana, Prometheus, Vaultwarden, Firefly III, CloudBeaver
- **Media** (10): Jellyfin, Jellyseerr, Sonarr, Radarr, Lidarr, Prowlarr, Navidrome, Readarr, Audiobookshelf, Pinchflat
- **Home** (3): Frigate, Immich, Open WebUI

---

## 2. Uptime Kuma

### Container Details

| Property | Value |
|----------|-------|
| Image | `louislam/uptime-kuma:1` |
| Internal port | `3002` → container `3001` |
| Caddy TLS port | `13543` |
| Data directory | `/var/lib/uptime-kuma` |
| URL | `https://hwc.ocelot-wahoo.ts.net:13543` |

### Volumes

- `/var/lib/uptime-kuma:/app/data` — SQLite database, config

### NixOS Config

- Module: `domains/monitoring/uptime-kuma/index.nix`
- Options namespace: `hwc.monitoring.uptime-kuma.*`
- Enabled in: `profiles/monitoring.nix`

---

## 3. Caddy Routes Added

Both services use `mode = "port"` with dedicated TLS listeners:

| Service | TLS Port | Upstream |
|---------|----------|----------|
| Homepage | 17443 | `http://127.0.0.1:3080` |
| Uptime Kuma | 13543 | `http://127.0.0.1:3002` |

Routes are registered via `hwc.networking.shared.routes` (automatically picked up by the Caddy reverse proxy module).

---

## 4. Manual Steps for Eric

### Deploy

```bash
# After pulling the branch and reviewing:
sudo nixos-rebuild switch --flake .#hwc-server
```

### Verify Services

```bash
# Homepage responding?
curl -s -o /dev/null -w '%{http_code}' http://localhost:3080

# Uptime Kuma responding?
curl -s -o /dev/null -w '%{http_code}' http://localhost:3002

# Via Caddy TLS?
curl -sk -o /dev/null -w '%{http_code}' https://hwc.ocelot-wahoo.ts.net:17443
curl -sk -o /dev/null -w '%{http_code}' https://hwc.ocelot-wahoo.ts.net:13543
```

### Uptime Kuma Initial Setup

1. Open `https://hwc.ocelot-wahoo.ts.net:13543`
2. Create admin account (first-run wizard)
3. **Set up ntfy notification**:
   - Settings → Notifications → Add
   - Type: **ntfy**
   - Server URL: `http://127.0.0.1:2586` (ntfy runs on host network)
   - Topic: `hwc-alerts`
   - Priority: 4 (high)
4. Add monitors (see below)

### Suggested Monitors

**Critical (check every 60s):**

| Name | Type | URL |
|------|------|-----|
| n8n | HTTP | `http://127.0.0.1:5678/healthz` |
| Paperless | HTTP | `http://127.0.0.1:8102/api/` |
| Heartwood MCP | HTTP | `http://127.0.0.1:6100/health` |
| Estimator API | HTTP | `http://127.0.0.1:8099/health` |
| Authentik | HTTP | `http://127.0.0.1:9200` |
| Firefly III | HTTP | `http://127.0.0.1:8085` |
| Caddy Admin | HTTP | `http://127.0.0.1:2019/config/` |

**Important (check every 120s):**

| Name | Type | URL |
|------|------|-----|
| Jellyfin | HTTP | `http://127.0.0.1:8096` |
| Immich | HTTP | `http://127.0.0.1:2283` |
| Frigate | HTTP | `http://127.0.0.1:5001` |
| Grafana | HTTP | `http://127.0.0.1:3000` |
| Prometheus | HTTP | `http://127.0.0.1:9090` |

**Nice to have (check every 300s):**

| Name | Type | URL |
|------|------|-----|
| Sonarr | HTTP | `http://127.0.0.1:8989` |
| Radarr | HTTP | `http://127.0.0.1:7878` |
| Lidarr | HTTP | `http://127.0.0.1:8686` |
| Prowlarr | HTTP | `http://127.0.0.1:9696` |
| Readarr | HTTP | `http://127.0.0.1:8787` |
| Navidrome | HTTP | `http://127.0.0.1:4533` |
| Audiobookshelf | HTTP | `http://127.0.0.1:13378` |
| Open WebUI | HTTP | `http://127.0.0.1:3001` |

> **Note:** All monitors use `127.0.0.1` because the Uptime Kuma container binds to the host port, and services listen on localhost. If Uptime Kuma runs in bridge networking mode, use `host.containers.internal` instead.

### Homepage Customization

To edit Homepage config after deployment, modify the YAML files in `domains/monitoring/homepage/parts/` and rebuild. The activation script deploys them to `/var/lib/homepage/`.

Alternatively, for quick edits without rebuild, edit files directly in `/var/lib/homepage/` (changes will be overwritten on next rebuild).

---

## 5. Notes

- Organizr remains running on port 9443 — Homepage supplements it, does not replace it
- Neither service is exposed to the public internet (Tailscale only)
- Both containers have 512MB memory limit and 0.5 CPU limit
- Homepage mounts the podman socket read-only for container auto-discovery
- The `HOMEPAGE_ALLOWED_HOSTS=*` env var is safe because the service is behind Tailscale
