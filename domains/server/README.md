# Server Domain

## Purpose & Scope

The **Server Domain** provides **application services and container orchestration** - managing containerized applications, service coordination, media automation, AI services, and server-specific functionality. This domain owns application containers, implements service workflows, and coordinates complex multi-container deployments.

**Key Principle**: If it's a containerized application service or server-specific automation → server domain. The server domain is the "application layer" that delivers user functionality through coordinated services.

## Domain Architecture

The server domain is organized by **service categories** based on functionality:

```
domains/server/
├── index.nix                    # Domain aggregator
├── containers/                  # Containerized application services
│   ├── index.nix               # Container aggregator
│   ├── _shared/                # Shared container utilities
│   ├── caddy/                  # Reverse proxy & TLS termination
│   ├── jellyfin/               # Media server
│   ├── immich/                 # Photo management
│   ├── radarr/                 # Movie automation
│   ├── sonarr/                 # TV show automation
│   ├── lidarr/                 # Music automation
│   ├── prowlarr/               # Indexer management
│   ├── qbittorrent/            # Torrent client
│   ├── sabnzbd/                # Usenet client
│   ├── slskd/                  # SoulSeek daemon
│   ├── soularr/                # Music library organization
│   ├── navidrome/              # Music streaming server
│   └── gluetun/                # VPN container networking
├── orchestration/              # Service coordination & automation
│   ├── index.nix               # Orchestration aggregator
│   └── media-orchestrator.nix  # Media workflow automation
├── ai/                         # AI & LLM services
│   ├── ollama/                 # Local LLM server
│   └── ai-bible/               # AI-powered Bible study
├── business/                   # Business application services
│   ├── default.nix            # Business services
│   └── parts/business-api.nix  # Business API integration
├── networking/                 # Network services & databases
│   ├── default.nix            # Network service coordination
│   └── parts/                  # Database, NTFY, VPN coordination
├── monitoring/                 # Observability & metrics
│   ├── default.nix            # Monitoring coordination
│   └── parts/                  # Grafana, Prometheus, dashboards
├── storage/                    # Storage management & cleanup
│   ├── index.nix               # Storage coordination
│   └── parts/                  # Cleanup automation, monitoring
├── backup/                     # Backup services
│   ├── default.nix            # Backup coordination
│   └── parts/user-backup.nix   # User backup automation
└── downloaders/                # Download client orchestration
    ├── index.nix               # Downloader coordination
    └── parts/                  # Download automation, scripts
```

## Service Quick Reference

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

### Common Tasks

```bash
# Access Service Logs
journalctl -u jellyfin -f
podman logs -f sonarr

# Restart Services
systemctl restart jellyfin
systemctl restart podman-sonarr

# Check Service Status
systemctl list-units --type=service --state=running | rg -i "immich|jellyfin|navidrome|frigate|couchdb|podman-"
```

## Routing Architecture

The HWC server uses **Caddy** as a reverse proxy with two routing modes:

1.  **Subpath Mode**: Single HTTPS endpoint with path-based routing
2.  **Port Mode**: Dedicated HTTPS port per service

**Configuration File**: `domains/server/routes.nix`

### Subpath Mode

*   **Path Preservation (`needsUrlBase = true`)**: For apps that support a URL base (e.g., Sonarr, Radarr). The full path is passed to the app.
*   **Path Stripping (`needsUrlBase = false`)**: For apps that expect to be at the root (e.g., Jellyfin, CouchDB). The subpath prefix is removed before proxying.

### Port Mode

Used for "subpath-hostile" applications that have hardcoded paths or problematic redirects. This mode provides a dedicated HTTPS port for the service.

*   **Examples**: Jellyseerr, Immich, Frigate, slskd.

## Service Details

*A summary of key services. For a full list, see the "Access URLs" section above.*

| Service | Type | Access | Mode | Notes |
|---|---|---|---|---|
| **Jellyfin** | Native | `/jellyfin` | Subpath (strip) | Firewall open for LAN discovery. |
| **Jellyseerr**| Container | `:5543` | Port | Subpath-hostile; see case study below. |
| **Navidrome** | Native | `/music` | Subpath (preserve)| Music streaming server. |
| **Immich** | Native | `:7443` | Port | Photo/video backup, subpath-hostile. |
| **\*arr Stack** | Container | `/sonarr`, etc. | Subpath (preserve)| Media automation (TV, movies, music). |
| **Downloaders**| Container | `/sab`, `/qbt` | Subpath | Usenet and torrent clients. |
| **Frigate** | Container | `:5443` | Port | NVR with GPU acceleration, subpath-hostile. |
| **CouchDB** | Native | `/sync` | Subpath (strip) | Backend for Obsidian LiveSync. |

## Troubleshooting & Known Issues

### Media Orchestration Pipeline
*   **Issue**: `media-orchestrator.service` fails to start.
*   **Cause**: Tries to read agenix secrets before they are created.
*   **Solution**: Added `agenix.service` to systemd `after` and `wants` directives.
*   **Issue**: qBittorrent completion events not triggering.
*   **Cause**: Missing volume mounts for scripts and events in the container.
*   **Solution**: Added `/scripts` and `/mnt/hot/events` volumes to the qBittorrent container config.

### CouchDB Reverse Proxy
*   **Issue**: Obsidian LiveSync fails, reporting "databases don't exist".
*   **Cause**: Caddy was preserving the `/sync` prefix, but CouchDB expects database names at the root.
*   **Solution**: Changed the CouchDB route to `needsUrlBase = false` to strip the prefix.

### Fake/Malicious Torrent Detection
*   **Issue**: Downloads complete but are not imported by Sonarr/Radarr.
*   **Cause**: Torrents from untrusted sources (ThePirateBay) contained malware (`.exe` files) and mismatched content.
*   **Lesson**: The *arr services worked correctly by refusing to import suspicious content. This is a security feature.

## Best Practices

### Safe Download Workflow
1.  **Add Media to *arr Apps**: Let Sonarr/Radarr/Lidarr manage searches.
2.  **Use Trusted Indexers**: Configure Prowlarr with reliable sources.
3.  **Automate**: Let the system handle searching, downloading, and importing.
4.  **Manual Downloads**: If necessary, use the "Manual Import" feature in the *arr apps from a trusted source (e.g., YTS, EZTV). **Avoid ThePirateBay.**

### Storage Management
*   **Hot Storage (`/mnt/hot/downloads/`)**: Temporary staging area, cleaned automatically.
*   **Cold Storage (`/mnt/media/`)**: Permanent, organized media library.

## Verification Commands

```bash
# Check all container services
sudo podman ps | grep -E "sonarr|radarr|lidarr|qbittorrent|sabnzbd"

# Check orchestrator status
systemctl status media-orchestrator.service

# Check API connectivity to an *arr app
curl -s http://localhost:8989/api/v3/system/status \
  -H "X-Api-Key: $(sudo cat /run/agenix/sonarr-api-key)" | jq .

# Verify VPN routing for download clients
sudo podman exec qbittorrent curl -s ifconfig.me
```
