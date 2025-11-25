# NTFY Notification System - Complete Setup Guide

**Version:** 1.0
**Last Updated:** 2025-11-23
**Status:** Production - Fully Operational

## Overview

Self-hosted ntfy notification server providing instant push notifications to iOS/Android devices and integration with system monitoring. Runs in Podman container with Caddy reverse proxy handling TLS termination.

### Key Features

- ✅ Self-hosted on hwc-server with local message caching
- ✅ iOS push notifications via ntfy.sh upstream relay (Firebase)
- ✅ 3-tier notification topics (critical, alerts, updates)
- ✅ Integration with system monitoring (disk space, service failures)
- ✅ Accessible via Tailscale VPN with proper TLS
- ✅ No authentication required (private VPN network)

---

## Architecture

### Network Flow

```
┌─────────────────────────────────────────────────────────────┐
│  hwc-ntfy-send CLI / Monitoring Scripts                     │
└────────────────────┬────────────────────────────────────────┘
                     ▼
         ┌───────────────────────┐
         │   Caddy Reverse Proxy │
         │   Port 2586 (HTTPS)   │
         └───────────┬───────────┘
                     ▼
         ┌───────────────────────┐
         │  ntfy Container       │
         │  Port 9999 (HTTP)     │
         └───────────┬───────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌────────────────┐      ┌──────────────────┐
│ Local Cache    │      │ ntfy.sh Upstream │
│ 12h retention  │      │ (iOS Push)       │
└────────────────┘      └──────────────────┘
                                 ▼
                        ┌────────────────┐
                        │ iOS/Android    │
                        │ ntfy App       │
                        └────────────────┘
```

### Port Configuration

**CRITICAL:** Port conflict was the root cause of previous failures.

| Component | Port | Protocol | Purpose |
|-----------|------|----------|---------|
| ntfy Container | 9999 | HTTP | Internal only |
| Caddy Proxy | 2586 | HTTPS | External access |

**Why This Works:**
- ntfy container runs on internal port 9999
- Caddy handles TLS and forwards port 2586 → 9999
- No port conflict

---

## Configuration

### ntfy Container

**File:** `machines/server/config.nix`

```nix
hwc.services.ntfy = {
  enable = true;
  port = 9999;  # Internal port
  dataDir = "/var/lib/hwc/ntfy";
};
```

### ntfy Server Config

**File:** `/var/lib/hwc/ntfy/etc/server.yml`

```yaml
base-url: "https://hwc.ocelot-wahoo.ts.net:2586"
listen-http: ":80"
cache-duration: "12h"
upstream-base-url: "https://ntfy.sh"
behind-proxy: true
enable-login: false
enable-signup: false
log-level: debug
```

### Caddy Route

**File:** `domains/server/routes.nix`

```nix
{
  name = "ntfy";
  mode = "port";
  port = 2586;
  upstream = "http://127.0.0.1:9999";
}
```

### Client Config

**File:** `machines/server/config.nix`

```nix
hwc.system.services.ntfy = {
  enable = true;
  serverUrl = "https://hwc.ocelot-wahoo.ts.net:2586";
  defaultTopic = "hwc-server-events";
};
```

---

## Notification Topics

| Topic | Priority | Use Case |
|-------|----------|----------|
| **hwc-critical** | 5 | Service failures, disk >95% |
| **hwc-alerts** | 4 | Warnings, disk 80-95% |
| **hwc-updates** | 3 | System updates |

---

## Monitoring Integration

### Disk Space Monitor
- **Script:** `workspace/utilities/monitoring/disk-space-monitor.sh`
- **Schedule:** Hourly systemd timer
- **Alerts:** 80%=P4, 95%=P5

### Service Failures
- **Script:** `workspace/utilities/monitoring/systemd-failure-notifier.sh`
- **Monitored:** backup-local, immich, jellyfin, navidrome, frigate, couchdb, ntfy, caddy

---

## iOS Setup

1. Install ntfy app
2. Add server: `https://hwc.ocelot-wahoo.ts.net:2586`
3. Subscribe to: hwc-critical, hwc-alerts, hwc-updates
4. Enable iOS notifications
5. Connect Tailscale VPN

---

## Usage

```bash
# Send notification
hwc-ntfy-send hwc-critical "Alert" "Message"

# With priority/tags
hwc-ntfy-send --priority 5 --tag urgent hwc-critical "Title" "Body"
```

---

## Troubleshooting

### No Messages on iPhone

```bash
# Check ntfy port
sudo podman port ntfy  # Should show 9999

# Test internal
curl -s http://127.0.0.1:9999/hwc-critical/json?poll=1

# Test external
curl -k -s https://hwc.ocelot-wahoo.ts.net:2586/hwc-critical/json?poll=1
```

**Solutions:**
1. Verify Tailscale connected
2. Force-close ntfy app
3. Check server URL in app
4. Restart services

### Port Conflict

**If both ntfy and Caddy try to use 2586:**

```nix
# FIX: ntfy=9999, Caddy=2586
hwc.services.ntfy.port = 9999;
```

---

## Status

✅ All systems operational (2025-11-23)

- ntfy container: Running on port 9999
- Caddy: Forwarding 2586 → 9999
- iOS push: Working via ntfy.sh upstream
- Monitoring: disk-space + service-failure active
