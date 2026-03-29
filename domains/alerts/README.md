# domains/alerts/

## Purpose

Centralized alert routing to Slack via n8n webhooks. Provides fail-graceful alerting infrastructure with retry logic, local logging fallback, and CLI tools for manual alerts. Gotify server provides push notifications to mobile (via iGotify) and Alertmanager bridge.

## Boundaries

- **Manages**: gotify notification server, alert routing, webhook delivery, service failure detection, disk space monitoring, SMART alerts, backup notifications, Alertmanager→gotify bridge
- **Does NOT manage**: n8n configuration (→ `domains/server/native/n8n`), Slack workspace setup (external), individual service monitoring logic (→ respective domains)

## Structure

```
domains/alerts/
├── index.nix           # Domain aggregator with OPTIONS/IMPLEMENTATION/VALIDATION
├── options.nix         # hwc.alerts.* options
└── parts/
    ├── cli.nix         # hwc-alert CLI tool
    ├── gotify-bridge.nix # Alertmanager → gotify bridge service
    ├── server.nix      # Gotify notification server container
    └── slack-webhook.nix # Webhook scripts with retry logic
```

## Configuration

### Gotify Notification Server

```nix
hwc.alerts.server = {
  enable = true;
  port = 2586;
  dataDir = "/var/lib/hwc/gotify";
  # adminPasswordFile = ...; # env file with GOTIFY_DEFAULTUSER_PASS=...
};
```

### Basic Usage

```nix
# In profiles/alerts.nix or machine config
hwc.alerts = {
  enable = true;
  sources = {
    smartd.enable = true;        # SMART disk monitoring
    backup.enable = true;        # Backup notifications
    diskSpace.enable = true;     # Disk space alerts
    serviceFailures.enable = true; # Service crash alerts
  };
  cli.enable = true;  # hwc-alert command
};
```

### Disk Space Monitoring

```nix
hwc.alerts.sources.diskSpace = {
  enable = true;
  frequency = "hourly";
  filesystems = [ "/" "/home" "/mnt/media" "/mnt/hot" ];
  warningThreshold = 80;   # P4 alert at 80%
  criticalThreshold = 95;  # P5 alert at 95%
};
```

### Service Failure Detection

```nix
hwc.alerts.sources.serviceFailures = {
  enable = true;
  autoDetect = true;  # Monitors jellyfin, n8n, caddy, postgresql, etc.
  # Or explicitly: services = [ "jellyfin" "caddy" "backup" ];
};
```

## CLI Tool

```bash
# Send alert
hwc-alert "Title" "Message"
hwc-alert -t "Build Failed" -m "Details" -s critical -e system

# Test webhook
hwc-alert --test

# View status
hwc-alert --status
```

## Webhook Endpoints

Expects n8n webhooks at:
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/system-alerts`
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/backup-alerts`
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/disk-alerts`
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/service-alerts`

## Robustness

- 3 retry attempts with exponential backoff (2s, 4s delays)
- 30s timeout per attempt
- Fallback to `/var/log/hwc/alerts/failed-alerts.log`
- Critical alerts also use `wall` message

## Log Files

| File | Purpose |
|------|---------|
| `/var/log/hwc/alerts/webhook.log` | All webhook attempts |
| `/var/log/hwc/alerts/failed-alerts.log` | Failed alerts for retry |
| `/var/log/hwc/alerts/health.log` | Health check results |
| `/var/log/hwc/alerts/gotify-bridge.log` | Alertmanager→gotify bridge |

## Changelog

- 2026-03-29: Migrated from ntfy to gotify — replaced ntfy container/bridge/options with gotify equivalents, per-app token model
- 2026-03-27: Added alertmanager-ntfy-bridge (parts/ntfy-bridge.nix) — receives Alertmanager webhooks and forwards to ntfy for phone notifications
- 2026-03-24: Enabled ntfy server (port 2586), integrated with work_lead_response n8n workflow for private lead notifications
- 2026-02-27: Added ntfy server (migrated from server/native/networking/)
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2026-02-22: Initial domain implementation
