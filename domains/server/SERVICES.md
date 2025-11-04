# HWC Server Services Guide

**Last Updated**: 2025-11-03
**Server**: hwc-server (hwc.ocelot-wahoo.ts.net)

This document provides a comprehensive guide to all services running on the HWC server, their access methods, routing configuration, and architectural patterns.

---

## Table of Contents

1. [Quick Reference - All Services](#quick-reference---all-services)
2. [Access Methods](#access-methods)
3. [Routing Architecture](#routing-architecture)
4. [Service Details](#service-details)
5. [Troubleshooting Guide](#troubleshooting-guide)
6. [Adding New Services](#adding-new-services)
7. [Case Study: Jellyseerr Subpath Issues](#case-study-jellyseerr-subpath-issues)

---

## Quick Reference - All Services

### Media Services

| Service | Type | Caddy Path | Direct Port | External Port | Purpose |
|---------|------|------------|-------------|---------------|---------|
| **Jellyfin** | Native | `/jellyfin` | 8096 | 8096 (firewall) | Media streaming server |
| **Jellyseerr** | Container | N/A | 5055 | **5543** (HTTPS) | Media request management |
| **Navidrome** | Native | `/music` | 4533 | 4533 (firewall) | Music streaming |
| **Immich** | Native | N/A | 2283 | **7443** (HTTPS) | Photo/video backup |

### Download & Indexing

| Service | Type | Caddy Path | Direct Port | External Port | Purpose |
|---------|------|------------|-------------|---------------|---------|
| **Sonarr** | Container | `/sonarr` | 8989 | N/A | TV show management |
| **Radarr** | Container | `/radarr` | 7878 | N/A | Movie management |
| **Lidarr** | Container | `/lidarr` | 8686 | N/A | Music management |
| **Prowlarr** | Container | `/prowlarr` | 9696 | N/A | Indexer manager |
| **Sabnzbd** | Container | `/sab` | 8081 | N/A | Usenet downloader |
| **qBittorrent** | Container | `/qbt` | 8080 | N/A | Torrent client |
| **slskd** | Container | N/A | 5031 | **8443** (HTTPS) | Soulseek client |

### Infrastructure

| Service | Type | Caddy Path | Direct Port | External Port | Purpose |
|---------|------|------------|-------------|---------------|---------|
| **Frigate** | Container | N/A | 5000 | **5443** (HTTPS) | NVR/Camera system |
| **CouchDB** | Native | `/sync` | 5984 | N/A | Obsidian LiveSync |

---

## Access Methods

### 1. Subpath Access (via Caddy)
**URL Format**: `https://hwc.ocelot-wahoo.ts.net/<path>`

Services accessible via subpaths:
- Jellyfin: https://hwc.ocelot-wahoo.ts.net/jellyfin
- Navidrome: https://hwc.ocelot-wahoo.ts.net/music
- Sonarr: https://hwc.ocelot-wahoo.ts.net/sonarr
- Radarr: https://hwc.ocelot-wahoo.ts.net/radarr
- Lidarr: https://hwc.ocelot-wahoo.ts.net/lidarr
- Prowlarr: https://hwc.ocelot-wahoo.ts.net/prowlarr
- Sabnzbd: https://hwc.ocelot-wahoo.ts.net/sab
- qBittorrent: https://hwc.ocelot-wahoo.ts.net/qbt
- CouchDB: https://hwc.ocelot-wahoo.ts.net/sync

### 2. Port-Based Access (via Caddy)
**URL Format**: `https://hwc.ocelot-wahoo.ts.net:<port>`

Port-based services (subpath-hostile applications):
- **5443**: Frigate NVR
- **5543**: Jellyseerr
- **7443**: Immich
- **8443**: slskd

### 3. Direct Port Access (LAN/Tailscale)
**URL Format**: `http://127.0.0.1:<port>` or `http://<server-ip>:<port>`

Services exposing direct ports:
- **2283**: Immich (HTTP) - Also via HTTPS port 7443
- **4533**: Navidrome (HTTP) - Also via subpath
- **5000**: Frigate (HTTP) - Also via HTTPS port 5443
- **5031**: slskd (HTTP) - Also via HTTPS port 8443
- **5055**: Jellyseerr (HTTP) - Also via HTTPS port 5543
- **5984**: CouchDB (HTTP) - Also via subpath
- **7878**: Radarr (HTTP) - Also via subpath
- **8080**: qBittorrent (HTTP) - Also via subpath
- **8081**: Sabnzbd (HTTP) - Also via subpath
- **8096**: Jellyfin (HTTP) - Also via subpath, firewall open
- **8686**: Lidarr (HTTP) - Also via subpath
- **8989**: Sonarr (HTTP) - Also via subpath
- **9696**: Prowlarr (HTTP) - Also via subpath

### 4. External Access (Open Firewall Ports)

These services have firewall ports open for external access:
- **8096**: Jellyfin (direct HTTP access for devices)
- **7359**: Jellyfin (discovery - TCP/UDP)
- **2283**: Immich (direct HTTP access)
- **4533**: Navidrome (direct HTTP access)

---

## Routing Architecture

### Overview

The HWC server uses **Caddy** as a reverse proxy with two routing modes:

1. **Subpath Mode**: Single HTTPS endpoint with path-based routing
2. **Port Mode**: Dedicated HTTPS port per service

**Configuration File**: `domains/server/routes.nix`

### Subpath Mode

**How it works**:
```
User Request: https://hwc.ocelot-wahoo.ts.net/sonarr
                          ↓
               Caddy Reverse Proxy
                          ↓
          Upstream: http://127.0.0.1:8989
```

**Two subpath strategies**:

#### Path Preservation (`needsUrlBase = true`)
- **Usage**: Applications with URL base configuration support
- **Behavior**: Full path passed to upstream (e.g., `/sonarr/api` → `/sonarr/api`)
- **Requirement**: App must have URL_BASE or equivalent setting configured
- **Examples**: Sonarr, Radarr, Lidarr, Prowlarr, Sabnzbd, Navidrome
- **Caddy directive**: `handle @service_name`

#### Path Stripping (`needsUrlBase = false`)
- **Usage**: Applications expecting root path despite reverse proxy
- **Behavior**: Prefix stripped before upstream (e.g., `/jellyfin/api` → `/api`)
- **Caddy directive**: `handle_path /path*`
- **Examples**: Jellyfin, qBittorrent
- **Risk**: May break redirects and asset loading

### Port Mode

**How it works**:
```
User Request: https://hwc.ocelot-wahoo.ts.net:5543/
                          ↓
         Caddy (dedicated TLS listener)
                          ↓
          Upstream: http://127.0.0.1:5055
```

**When to use**:
- Applications that don't support URL base configuration
- Applications with hardcoded absolute paths in JavaScript/assets
- Applications generating redirects without respecting URL_BASE
- WebSocket-heavy applications with complex routing

**Examples**: Jellyseerr, Immich, Frigate, slskd

**Advantages**:
- No path manipulation required
- Application runs at root path
- Redirects work correctly
- WebSocket connections work reliably

**Disadvantages**:
- Requires unique port per service
- Less elegant URLs
- Firewall port management needed

### Route Schema

Each route in `routes.nix` follows this schema:

```nix
{
  name = "service-name";           # Service identifier
  mode = "subpath" | "port";       # Routing mode

  # Subpath mode fields
  path = "/path";                  # URL path (subpath mode only)
  needsUrlBase = true | false;     # Preserve vs strip path
  headers = { "X-Forwarded-Prefix" = "/path"; };  # Optional headers

  # Port mode fields
  port = 5443;                     # External HTTPS port (port mode only)

  # Common fields
  upstream = "http://127.0.0.1:8080";  # Backend service URL

  # Advanced options (optional)
  assetGlobs = [ "/css/*" "/js/*" ];   # Asset path patterns
  assetStrategy = "none" | "rewrite" | "referer";  # Asset handling
  ws = true | false;               # WebSocket support (default: true)
  timeouts = { try = "10s"; fail = "5s"; };  # Proxy timeouts
}
```

---

## Service Details

### Media Streaming

#### Jellyfin
- **Type**: Native NixOS service
- **Access**: https://hwc.ocelot-wahoo.ts.net/jellyfin
- **Direct**: http://127.0.0.1:8096 or http://<server-ip>:8096
- **Config**: `domains/server/jellyfin/`
- **Mode**: Subpath with path stripping (`needsUrlBase = false`)
- **Notes**:
  - Firewall open for external device access (Roku TVs, etc.)
  - Uses path stripping despite URL_BASE not being supported reliably
  - Discovery ports 7359 (TCP/UDP) also open

#### Jellyseerr
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net:5543/
- **Direct**: http://127.0.0.1:5055
- **Config**: `domains/server/containers/jellyseerr/`
- **Mode**: Port mode (port 5543)
- **Notes**:
  - **Subpath-hostile** - does not respect URL_BASE for redirects
  - Moved from subpath to port mode after troubleshooting
  - See [Case Study](#case-study-jellyseerr-subpath-issues) below

#### Navidrome
- **Type**: Native NixOS service
- **Access**: https://hwc.ocelot-wahoo.ts.net/music
- **Direct**: http://127.0.0.1:4533
- **Config**: `domains/server/navidrome/`
- **Mode**: Subpath with path preservation (`needsUrlBase = true`)
- **Notes**: Supports URL base configuration (`BaseUrl = "/music"`)

#### Immich
- **Type**: Native NixOS service with ML backend
- **Access**: https://hwc.ocelot-wahoo.ts.net:7443/
- **Direct**: http://127.0.0.1:2283
- **Config**: `domains/server/immich/`
- **Mode**: Port mode (port 7443)
- **Notes**:
  - **Subpath-hostile** - hardcoded paths in frontend
  - GPU acceleration via NVIDIA P1000
  - Firewall open for external access

### Download Management

#### Sonarr (TV Shows)
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net/sonarr
- **Direct**: http://127.0.0.1:8989
- **Config**: `domains/server/containers/sonarr/`
- **Mode**: Subpath with path preservation (`needsUrlBase = true`)
- **URL Base**: Set to `/sonarr` in container config

#### Radarr (Movies)
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net/radarr
- **Direct**: http://127.0.0.1:7878
- **Config**: `domains/server/containers/radarr/`
- **Mode**: Subpath with path preservation (`needsUrlBase = true`)
- **URL Base**: Set to `/radarr` in container config

#### Lidarr (Music)
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net/lidarr
- **Direct**: http://127.0.0.1:8686
- **Config**: `domains/server/containers/lidarr/`
- **Mode**: Subpath with path preservation (`needsUrlBase = true`)
- **URL Base**: Set to `/lidarr` in container config

#### Prowlarr (Indexers)
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net/prowlarr
- **Direct**: http://127.0.0.1:9696
- **Config**: `domains/server/containers/prowlarr/`
- **Mode**: Subpath with path preservation (`needsUrlBase = true`)
- **URL Base**: Set to `/prowlarr` in container config

#### Sabnzbd (Usenet)
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net/sab
- **Direct**: http://127.0.0.1:8081
- **Config**: `domains/server/containers/sabnzbd/`
- **Mode**: Subpath with path preservation (`needsUrlBase = true`)
- **URL Base**: Set to `/sab` in container config

#### qBittorrent (Torrents)
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net/qbt
- **Direct**: http://127.0.0.1:8080
- **Config**: `domains/server/containers/qbittorrent/`
- **Mode**: Subpath with path stripping (`needsUrlBase = false`)
- **Notes**: Uses alternative web UI that expects root path

#### slskd (Soulseek)
- **Type**: Podman container
- **Access**: https://hwc.ocelot-wahoo.ts.net:8443/
- **Direct**: http://127.0.0.1:5031
- **Config**: `domains/server/containers/slskd/`
- **Mode**: Port mode (port 8443)
- **Notes**: Subpath-hostile, requires port mode

### Infrastructure

#### Frigate (NVR)
- **Type**: Podman container with GPU acceleration
- **Access**: https://hwc.ocelot-wahoo.ts.net:5443/
- **Direct**: http://127.0.0.1:5000
- **Config**: `domains/server/frigate/`
- **Mode**: Port mode (port 5443)
- **Notes**:
  - **Subpath-hostile** - WebSocket and asset issues
  - GPU acceleration via NVIDIA P1000
  - MQTT enabled for event communication
  - Firewall restricted to Tailscale

#### CouchDB (Obsidian LiveSync)
- **Type**: Native NixOS service
- **Access**: https://hwc.ocelot-wahoo.ts.net/sync
- **Direct**: http://127.0.0.1:5984
- **Config**: `domains/server/couchdb/`
- **Mode**: Subpath with path preservation (`needsUrlBase = true`)
- **Notes**: Configured for Obsidian LiveSync plugin

---

## Troubleshooting Guide

### Health Check Script

Run the health check to verify all services:

```bash
bash workspace/utilities/scripts/caddy-health-check.sh
```

### Common Issues

#### 1. Service Returns 404

**Symptom**: Service accessible directly but 404 through Caddy

**Check**:
```bash
# Verify route exists
rg "name = \"service-name\"" domains/server/routes.nix

# Check Caddy config
cat /etc/caddy/caddy_config

# Test direct access
curl -I http://127.0.0.1:<port>
```

**Solution**: Ensure route is defined in `routes.nix` and service is running

#### 2. Blank Screen / Asset Loading Issues

**Symptom**: HTTP 200 but blank page in browser

**Cause**: Subpath routing incompatibility

**Check**:
```bash
# Check for redirects
curl -I http://127.0.0.1:<port>/

# Look for Location header without base path
# Example: Location: /setup (should be /service/setup)
```

**Solution**: Move to port mode if service doesn't respect URL_BASE

#### 3. WebSocket Connection Failures

**Symptom**: Real-time features not working (live updates, notifications)

**Cause**: WebSocket routing issues with subpath mode

**Solution**: Move to port mode or verify `ws = true` in route config

#### 4. API Calls Failing

**Symptom**: Frontend loads but API calls return 404/502

**Check**:
```bash
# Monitor Caddy logs
journalctl -u caddy -f

# Check API path expectations
# If app expects /api but receives /service/api, mismatch exists
```

**Solution**:
- Verify `needsUrlBase` setting matches app expectations
- Check if URL_BASE environment variable is set correctly
- Consider port mode for problematic apps

### Debugging Workflow

1. **Verify service is running**:
   ```bash
   systemctl status <service>
   # or for containers:
   podman ps | grep <service>
   ```

2. **Test direct access**:
   ```bash
   curl -I http://127.0.0.1:<port>
   ```

3. **Test Caddy proxy**:
   ```bash
   # For subpath:
   curl -I https://hwc.ocelot-wahoo.ts.net/<path>

   # For port mode:
   curl -I https://hwc.ocelot-wahoo.ts.net:<port>
   ```

4. **Check Caddy logs**:
   ```bash
   journalctl -u caddy -f
   ```

5. **Verify route configuration**:
   ```bash
   cat /etc/caddy/caddy_config | grep -A 10 "<service-name>"
   ```

---

## Adding New Services

### Decision Tree: Subpath vs Port Mode?

```
Does the application support URL base configuration?
│
├─ YES → Try subpath mode with path preservation (needsUrlBase = true)
│        └─ Test redirects and asset loading
│           ├─ Works → Use subpath mode ✓
│           └─ Fails → Use port mode
│
└─ NO → Does it work at root path with reverse proxy?
         ├─ YES → Try subpath mode with path stripping (needsUrlBase = false)
         │        └─ Test redirects carefully
         │           ├─ Works → Use subpath mode ✓
         │           └─ Fails → Use port mode
         │
         └─ NO → Use port mode ✓
```

### Subpath Mode Example

```nix
# domains/server/routes.nix
{
  name = "newservice";
  mode = "subpath";
  path = "/newservice";
  upstream = "http://127.0.0.1:9999";
  needsUrlBase = true;  # App supports URL base
  headers = { "X-Forwarded-Prefix" = "/newservice"; };
}
```

**Don't forget**:
1. Configure URL_BASE in the application (if native service)
2. Set URL_BASE environment variable (if container)
3. Test redirects and asset loading
4. Run health check script

### Port Mode Example

```nix
# domains/server/routes.nix
{
  name = "newservice";
  mode = "port";
  port = 9443;  # Choose unused port (check existing routes)
  upstream = "http://127.0.0.1:9999";
}
```

**Port allocation**:
- Check existing ports: `rg "port = " domains/server/routes.nix`
- Use 4-digit ports in 5000-9000 range
- Avoid common service ports

### Testing Checklist

- [ ] Service starts and responds on direct port
- [ ] Caddy route is generated correctly (`cat /etc/caddy/caddy_config`)
- [ ] HTTPS access works through Caddy
- [ ] Redirects work correctly (check for /setup, /login, etc.)
- [ ] Static assets load (CSS, JS, images)
- [ ] API calls work (check browser DevTools)
- [ ] WebSocket connections work (if applicable)
- [ ] Authentication/login works
- [ ] Health check script passes

---

## Case Study: Jellyseerr Subpath Issues

### Problem

Jellyseerr was configured in subpath mode but showed a blank screen in browsers despite:
- Health check returning HTTP 200
- Container running normally
- Direct port access (5055) working fine

### Investigation

1. **Initial check**: Health check showed HTTP 200
   ```bash
   curl -I https://hwc.ocelot-wahoo.ts.net/jellyseerr
   # HTTP/2 200 OK
   ```

2. **Browser behavior**: Page loaded but showed blank screen

3. **Redirect analysis**:
   ```bash
   curl -I http://127.0.0.1:5055/
   # HTTP/1.1 307 Temporary Redirect
   # Location: /setup
   ```

4. **Root cause identified**:
   - Jellyseerr redirects from `/` to `/setup`
   - With path stripping (`handle_path /jellyseerr/*`), the browser request to `/jellyseerr/` became `/` at upstream
   - Upstream redirected to `/setup` (not `/jellyseerr/setup`)
   - Browser followed redirect to `https://hwc.ocelot-wahoo.ts.net/setup` (404)

### Attempted Fixes

#### Attempt 1: Remove URL_BASE
```nix
# domains/server/containers/jellyseerr/sys.nix
environment = {
  # URL_BASE = "/jellyseerr";  # Removed
};
```

**Result**: Failed - redirects still went to `/setup` without base path

#### Attempt 2: Restore URL_BASE and verify
```nix
environment = {
  URL_BASE = "/jellyseerr";  # Restored
};
```

**Result**: Failed - Jellyseerr doesn't respect URL_BASE for internal redirects

### Solution

**Move to port mode**:

```nix
# domains/server/routes.nix
# BEFORE (subpath mode):
{
  name = "jellyseerr";
  mode = "subpath";
  path = "/jellyseerr";
  upstream = "http://127.0.0.1:5055";
  needsUrlBase = false;
  headers = { "X-Forwarded-Prefix" = "/jellyseerr"; };
}

# AFTER (port mode):
{
  name = "jellyseerr";
  mode = "port";
  port = 5543;  # Dedicated port for Jellyseerr
  upstream = "http://127.0.0.1:5055";
}
```

**Remove URL_BASE**:
```nix
# domains/server/containers/jellyseerr/sys.nix
environment = {
  # No URL_BASE needed in port mode
};
```

### Verification

```bash
# Health check
bash workspace/utilities/scripts/caddy-health-check.sh
# jellyseerr: HTTP 200 ✓

# Browser access
curl -L https://hwc.ocelot-wahoo.ts.net:5543/
# Redirects work correctly: / → /setup with proper base path
```

### Lessons Learned

1. **URL_BASE is not always respected**: Some applications claim to support URL base configuration but don't implement it correctly for all redirects

2. **Test redirects explicitly**: Health checks showing HTTP 200 don't catch redirect issues

3. **Subpath-hostile indicators**:
   - Application uses Next.js, React, or similar SPA frameworks
   - Hardcoded absolute paths in JavaScript bundles
   - Internal redirects without checking base path
   - WebSocket connections with hardcoded paths

4. **Port mode is reliable**: When in doubt, port mode always works because the app runs at root path

5. **Document the reason**: Always add comments explaining why a service uses port mode vs subpath mode

### Similar Services

Other services moved to port mode for the same reasons:
- **Immich**: Next.js app with hardcoded paths
- **Frigate**: WebSocket-heavy with complex asset loading
- **slskd**: Doesn't support URL base configuration

---

## Configuration Files Reference

### Primary Configuration
- **Route definitions**: `domains/server/routes.nix`
- **Caddy renderer**: `domains/server/containers/_shared/caddy.nix`
- **Machine config**: `machines/server/config.nix`

### Service Configurations

#### Container Services
- Jellyseerr: `domains/server/containers/jellyseerr/`
- Sonarr: `domains/server/containers/sonarr/`
- Radarr: `domains/server/containers/radarr/`
- Lidarr: `domains/server/containers/lidarr/`
- Prowlarr: `domains/server/containers/prowlarr/`
- Sabnzbd: `domains/server/containers/sabnzbd/`
- qBittorrent: `domains/server/containers/qbittorrent/`
- slskd: `domains/server/containers/slskd/`
- Frigate: `domains/server/frigate/` (Podman via NixOS module)

#### Native Services
- Jellyfin: `domains/server/jellyfin/`
- Immich: `domains/server/immich/`
- Navidrome: `domains/server/navidrome/`
- CouchDB: `domains/server/couchdb/`

### Generated Configuration
- Caddyfile: `/etc/caddy/caddy_config`
- Systemd services: `/etc/systemd/system/<service>.service`

---

## Maintenance

### Updating Routes

1. Edit `domains/server/routes.nix`
2. Rebuild system: `sudo nixos-rebuild switch --flake .#hwc-server`
3. Verify Caddy config: `cat /etc/caddy/caddy_config`
4. Run health check: `bash workspace/utilities/scripts/caddy-health-check.sh`

### Adding Firewall Ports

Edit `machines/server/config.nix`:

```nix
firewall.extraTcpPorts = [ 8096 7359 2283 4533 9999 ];  # Add your port
```

### Container Port Changes

1. Edit container `sys.nix`: `domains/server/containers/<service>/sys.nix`
2. Update route in `routes.nix`
3. Rebuild and test

---

## Support

For issues or questions:
1. Check this guide's [Troubleshooting](#troubleshooting-guide) section
2. Review the [Case Study](#case-study-jellyseerr-subpath-issues) for subpath issues
3. Consult the main HWC charter: `charter.md`
4. Check service-specific READMEs in `domains/server/<service>/`

---

**Document Version**: 1.0
**HWC Architecture Version**: 6.0
