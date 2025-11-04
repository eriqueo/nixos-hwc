# HWC Server Quick Reference

**Last Updated**: 2025-11-03

## All Services at a Glance

### Access URLs

```
SUBPATH SERVICES (https://hwc.ocelot-wahoo.ts.net/...)
├─ /jellyfin      → Jellyfin Media Server
├─ /music         → Navidrome Music Streaming
├─ /sonarr        → Sonarr TV Management
├─ /radarr        → Radarr Movie Management
├─ /lidarr        → Lidarr Music Management
├─ /prowlarr      → Prowlarr Indexer Manager
├─ /sab           → Sabnzbd Usenet Downloader
├─ /qbt           → qBittorrent Torrent Client
└─ /sync          → CouchDB (Obsidian LiveSync)

PORT MODE SERVICES (https://hwc.ocelot-wahoo.ts.net:...)
├─ :5443          → Frigate NVR
├─ :5543          → Jellyseerr Media Requests
├─ :7443          → Immich Photo Backup
└─ :8443          → slskd Soulseek Client

DIRECT ACCESS (http://127.0.0.1:...)
├─ :2283          → Immich
├─ :4533          → Navidrome
├─ :5000          → Frigate
├─ :5031          → slskd
├─ :5055          → Jellyseerr
├─ :5984          → CouchDB
├─ :7878          → Radarr
├─ :8080          → qBittorrent
├─ :8081          → Sabnzbd
├─ :8096          → Jellyfin
├─ :8686          → Lidarr
├─ :8989          → Sonarr
└─ :9696          → Prowlarr
```

## Service Groups

### Media Streaming & Management
- **Jellyfin** (`/jellyfin`) - Stream movies, TV shows, music
- **Jellyseerr** (`:5543`) - Request movies/TV shows
- **Navidrome** (`/music`) - Stream music library
- **Immich** (`:7443`) - Photo/video backup and sharing

### Download Automation
- **Sonarr** (`/sonarr`) - TV show automation
- **Radarr** (`/radarr`) - Movie automation
- **Lidarr** (`/lidarr`) - Music automation
- **Prowlarr** (`/prowlarr`) - Indexer management
- **Sabnzbd** (`/sab`) - Usenet downloader
- **qBittorrent** (`/qbt`) - Torrent client
- **slskd** (`:8443`) - Soulseek (music sharing)

### Infrastructure
- **Frigate** (`:5443`) - Camera/NVR system
- **CouchDB** (`/sync`) - Obsidian sync backend

## Firewall Open Ports

External devices can access these services directly:
- `8096` - Jellyfin (TCP) - Media streaming
- `7359` - Jellyfin (TCP/UDP) - Device discovery
- `2283` - Immich (TCP) - Photo backup
- `4533` - Navidrome (TCP) - Music streaming

## Health Check

```bash
bash workspace/utilities/scripts/caddy-health-check.sh
```

## Common Tasks

### Access Service Logs
```bash
# Native services
journalctl -u jellyfin -f
journalctl -u immich-server -f
journalctl -u navidrome -f

# Container services
podman logs -f jellyseerr
podman logs -f sonarr
podman logs -f frigate
```

### Restart Services
```bash
# Native services
systemctl restart jellyfin
systemctl restart immich-server
systemctl restart navidrome

# Container services
systemctl restart podman-jellyseerr
systemctl restart podman-sonarr
systemctl restart podman-frigate
```

### Check Service Status
```bash
# All services at once
systemctl list-units --type=service --state=running | rg -i "immich|jellyfin|navidrome|frigate|couchdb|podman-"
```

## Routing Modes

### Subpath with Path Preservation (`needsUrlBase = true`)
**Apps with URL base support**
- Request: `/service/api` → Upstream: `/service/api`
- Services: Sonarr, Radarr, Lidarr, Prowlarr, Sabnzbd, Navidrome, CouchDB

### Subpath with Path Stripping (`needsUrlBase = false`)
**Apps expecting root path**
- Request: `/service/api` → Upstream: `/api`
- Services: Jellyfin, qBittorrent

### Port Mode
**Subpath-hostile apps**
- Request: `:5543/api` → Upstream: `/api`
- Services: Jellyseerr, Immich, Frigate, slskd

## Configuration Files

```
Primary config:     domains/server/routes.nix
Caddy renderer:     domains/server/containers/_shared/caddy.nix
Machine config:     machines/server/config.nix
Generated Caddyfile: /etc/caddy/caddy_config
```

## Troubleshooting

| Issue | Check |
|-------|-------|
| Service not accessible | `systemctl status <service>` |
| 404 through Caddy | `rg "name = \"<service>\"" domains/server/routes.nix` |
| Blank screen (HTTP 200) | Check redirects: `curl -I http://127.0.0.1:<port>/` |
| WebSocket issues | Consider port mode |
| Asset loading fails | Verify `needsUrlBase` setting or use port mode |

## Full Documentation

See `SERVICES.md` for comprehensive documentation including:
- Detailed routing architecture
- Complete troubleshooting guide
- Adding new services
- Jellyseerr case study
