# Alerts and Business Domains

> **Created**: 2026-02-22
> **Charter Version**: v10.3
> **Status**: Production

This document describes the `hwc.alerts` and `hwc.business` top-level domains, their architecture, configuration, and operational procedures.

---

## Table of Contents

1. [Overview](#overview)
2. [Alerts Domain](#alerts-domain)
   - [Architecture](#alerts-architecture)
   - [Configuration](#alerts-configuration)
   - [Alert Sources](#alert-sources)
   - [CLI Tool](#cli-tool)
   - [Troubleshooting](#alerts-troubleshooting)
3. [Business Domain](#business-domain)
   - [Architecture](#business-architecture)
   - [Configuration](#business-configuration)
   - [Services](#business-services)
   - [Deployment](#deployment)
4. [Robustness Features](#robustness-features)
5. [Log Files](#log-files)
6. [Maintenance](#maintenance)

---

## Overview

Two top-level domains provide cross-cutting infrastructure concerns:

| Domain | Namespace | Purpose |
|--------|-----------|---------|
| **alerts** | `hwc.alerts.*` | Centralized alert routing to Slack via n8n |
| **business** | `hwc.business.*` | Business services (OCR, APIs, future invoicing/CRM) |

Both domains are designed with **fail-graceful** principles:
- Retry logic with exponential backoff
- Local logging when remote services unavailable
- Clear error messages for debugging
- Stub services when dependencies missing

---

## Alerts Domain

### Alerts Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Alert Sources                            │
├──────────┬──────────┬──────────────┬───────────────────────┤
│  smartd  │  backup  │  disk-space  │  service-failures     │
│  (disk)  │ (restic) │   (timer)    │    (systemd)          │
└────┬─────┴────┬─────┴──────┬───────┴──────────┬────────────┘
     │          │            │                   │
     └──────────┴────────────┴───────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │  hwc-webhook-send     │
              │  (retry + logging)    │
              └───────────┬───────────┘
                          │
           ┌──────────────┼──────────────┐
           │              │              │
           ▼              ▼              ▼
     ┌─────────┐    ┌──────────┐   ┌─────────────┐
     │ n8n     │    │ Local    │   │ wall msg    │
     │ webhook │    │ Logs     │   │ (critical)  │
     └────┬────┘    └──────────┘   └─────────────┘
          │
          ▼
     ┌─────────┐
     │  Slack  │
     └─────────┘
```

### Alerts Configuration

**Profile** (`profiles/alerts.nix`):
```nix
{
  imports = [ ../domains/alerts/index.nix ];

  hwc.alerts = {
    enable = lib.mkDefault true;
    sources = {
      smartd.enable = lib.mkDefault true;
      backup.enable = lib.mkDefault true;
      diskSpace.enable = lib.mkDefault true;
      serviceFailures.enable = lib.mkDefault true;
    };
    cli.enable = lib.mkDefault true;
  };
}
```

**Machine Configuration** (`machines/server/config.nix`):
```nix
hwc.alerts = {
  enable = true;

  # Disk space monitoring
  sources.diskSpace = {
    enable = true;
    frequency = "hourly";
    filesystems = [ "/" "/home" "/mnt/media" "/mnt/hot" ];
    warningThreshold = 80;   # P4 alert
    criticalThreshold = 95;  # P5 alert
  };

  # Service failure monitoring
  sources.serviceFailures = {
    enable = true;
    autoDetect = true;  # Monitor jellyfin, n8n, caddy, etc.
    # Or specify explicitly:
    # services = [ "jellyfin" "caddy" "backup" ];
  };

  # SMART disk monitoring
  sources.smartd.enable = true;

  # Backup notifications
  sources.backup = {
    enable = true;
    onSuccess = false;  # Don't spam on success
    onFailure = true;   # Always alert on failure
  };
};
```

### Alert Sources

#### 1. SMART Disk Monitoring

Integrates with `services.smartd` to send alerts on disk failures.

**Severity Mapping**:
| Failure Type | Severity | Tag |
|--------------|----------|-----|
| CurrentPendingSector | critical | P5 |
| ReallocatedSectorCt | critical | P5 |
| OfflineUncorrectable | critical | P5 |
| Other | warning | P4 |

#### 2. Disk Space Monitoring

Hourly timer checks filesystem usage against thresholds.

**Systemd Units**:
- `hwc-disk-space-monitor.service` - oneshot check
- `hwc-disk-space-monitor.timer` - hourly trigger

#### 3. Service Failure Monitoring

Uses systemd `OnFailure=` to trigger alerts when services crash.

**Auto-detected Services** (when `autoDetect = true`):
- backup, backup-local, backup-cloud
- jellyfin, n8n, caddy, postgresql, frigate
- podman-immich, podman-navidrome, podman-qbittorrent
- podman-sonarr, podman-radarr, podman-prowlarr

**Template Service**: `hwc-service-failure-notifier@.service`

#### 4. Backup Notifications

Call from backup scripts:
```bash
hwc-backup-notify success "local" "Completed in 45 minutes"
hwc-backup-notify failure "cloud" "Connection timeout"
```

### CLI Tool

The `hwc-alert` command provides manual alert sending:

```bash
# Basic usage
hwc-alert "Title" "Message"

# With options
hwc-alert -t "Build Failed" -m "NixOS rebuild failed" -s critical -e system

# Add custom fields
hwc-alert "Deploy" "Deployed v1.2.3" -f "version=1.2.3" -f "env=production"

# Test webhook connectivity
hwc-alert --test

# Show what would be sent
hwc-alert "Test" "Message" --dry-run

# View recent activity
hwc-alert --status
```

**Options**:
| Flag | Description |
|------|-------------|
| `-t, --title` | Alert title |
| `-m, --message` | Alert message |
| `-s, --severity` | info, warning, critical |
| `-e, --endpoint` | system, backup, smartd, services |
| `-f, --field` | Add custom key=value field |
| `--test` | Test webhook health |
| `--dry-run` | Show without sending |
| `--status` | Show recent alerts |

### Alerts Troubleshooting

#### Webhook Not Reachable

```bash
# Check webhook health
hwc-alert --test

# Check n8n status
systemctl status n8n

# View health check logs
journalctl -u hwc-webhook-health

# Check failed alerts
cat /var/log/hwc/alerts/failed-alerts.log
```

#### Alerts Not Sending

```bash
# Check webhook logs
tail -f /var/log/hwc/alerts/webhook.log

# Manual test
hwc-webhook-send system "Test" "Manual test" info '{}'

# Check timer status
systemctl list-timers | grep hwc
```

#### Service Failure Alerts Not Working

```bash
# Check if OnFailure is set
systemctl show jellyfin | grep OnFailure

# Test the notifier manually
systemctl start hwc-service-failure-notifier@jellyfin.service

# Check notifier logs
journalctl -u "hwc-service-failure-notifier@*"
```

---

## Business Domain

### Business Architecture

```
domains/business/
├── index.nix             # Domain aggregator
├── options.nix           # hwc.business.* options
└── parts/
    ├── receipts-ocr.nix  # OCR service implementation
    └── api.nix           # Business API implementation
```

### Business Configuration

**Profile** (`profiles/business.nix`):
```nix
{
  imports = [ ../domains/business/index.nix ];

  hwc.business = {
    enable = lib.mkDefault true;
    receiptsOcr.enable = lib.mkDefault false;  # Opt-in
    api.enable = lib.mkDefault false;          # Opt-in
  };

  # Related services
  hwc.server.containers.paperless.enable = lib.mkDefault true;
  hwc.server.databases.redis.enable = lib.mkDefault true;
}
```

**Enable Receipts OCR**:
```nix
hwc.business.receiptsOcr = {
  enable = true;
  port = 8001;
  databaseUrl = "postgresql://business_user@localhost:5432/heartwood_business";

  ollama = {
    enable = true;
    url = "http://localhost:11434";
    model = "llama3.2";
  };

  storageRoot = "/mnt/hot/receipts";
  confidenceThreshold = 0.7;
};
```

### Business Services

#### Receipts OCR Service

Processes receipt images with OCR and stores in PostgreSQL.

**Systemd Units**:
- `receipts-ocr-setup.service` - Deploys code from workspace
- `receipts-ocr.service` - Main FastAPI service
- `receipts-ocr-db-init.service` - Database initialization

**Endpoints**:
- `GET /` - Service status
- `GET /health` - Health check
- `POST /upload` - Upload receipt image
- `GET /receipts` - List processed receipts

**CLI**:
```bash
# Process a receipt
receipt-ocr process /path/to/receipt.jpg

# List receipts
receipt-ocr list --month 2026-02
```

#### Business API (Placeholder)

Generic business API service for future functionality.

```nix
hwc.business.api = {
  enable = true;
  service = {
    enable = true;
    port = 8000;
    autoStart = true;
  };
};
```

### Deployment

#### Deploying Receipts OCR Source Code

The service expects source code at:
```
~/.nixos/workspace/projects/receipts-pipeline/
├── src/
│   ├── __init__.py
│   ├── receipt_ocr_service.py
│   ├── config.py
│   └── ...
└── database/
    └── schema.sql
```

**Deploy Steps**:
```bash
# 1. Clone/create source code
mkdir -p ~/.nixos/workspace/projects/receipts-pipeline/src

# 2. Run setup service
sudo systemctl restart receipts-ocr-setup

# 3. Initialize database
sudo systemctl restart receipts-ocr-db-init

# 4. Start service
sudo systemctl restart receipts-ocr

# 5. Check status
curl http://localhost:8001/health
```

**If Source Not Deployed**:
The service creates a stub that returns:
```json
{
  "status": "stub",
  "message": "Service not deployed. See logs for deployment instructions.",
  "deploy_from": "/home/eric/.nixos/workspace/projects/receipts-pipeline"
}
```

---

## Robustness Features

### Retry Logic

All webhook calls use exponential backoff:
- Attempt 1: immediate
- Attempt 2: 2 seconds delay
- Attempt 3: 4 seconds delay
- Timeout: 30 seconds per attempt

### Fallback Mechanisms

| Scenario | Primary | Fallback |
|----------|---------|----------|
| Webhook fails | n8n webhook | Log to file |
| Critical alert | Slack | `wall` message |
| n8n down | Retry 3x | Log + wall |
| Source missing | Deploy code | Stub service |

### Health Monitoring

- `hwc-webhook-health.timer` - Every 15 minutes
- Logs to `/var/log/hwc/alerts/health.log`
- Validates n8n endpoint reachability

---

## Log Files

### Alerts Domain

| Log File | Purpose |
|----------|---------|
| `/var/log/hwc/alerts/webhook.log` | All webhook attempts |
| `/var/log/hwc/alerts/failed-alerts.log` | Failed alerts for retry |
| `/var/log/hwc/alerts/health.log` | Health check results |
| `/var/log/hwc/alerts/smartd.log` | SMART disk alerts |
| `/var/log/hwc/alerts/disk-space.log` | Disk space checks |
| `/var/log/hwc/alerts/service-failures.log` | Service failure alerts |
| `/var/log/hwc/alerts/backup.log` | Backup notifications |
| `/var/log/hwc/alerts/cli.log` | CLI tool usage |

### Business Domain

| Log File | Purpose |
|----------|---------|
| `/var/log/hwc/receipts-ocr.log` | Service runtime logs |
| `/var/log/hwc/receipts-ocr-setup.log` | Deployment logs |
| `/var/log/hwc/receipts-ocr-db.log` | Database init logs |
| `/var/log/hwc/business-api.log` | API service logs |

### Log Rotation

All logs are rotated weekly, keeping 4 copies with compression.

---

## Maintenance

### Regular Tasks

```bash
# Check failed alerts
cat /var/log/hwc/alerts/failed-alerts.log

# Retry failed alerts manually
# (Copy payloads from failed-alerts.log)

# Check webhook health
hwc-alert --test

# View recent activity
hwc-alert --status
```

### Clearing Old Logs

Logs are automatically rotated, but to manually clear:
```bash
# Clear failed alerts after reviewing
> /var/log/hwc/alerts/failed-alerts.log

# Logs are in /var/log/hwc/alerts/
ls -la /var/log/hwc/alerts/
```

### n8n Webhook Endpoints

The alerts domain expects these n8n webhook endpoints:
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/system-alerts`
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/backup-alerts`
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/disk-alerts`
- `https://hwc.ocelot-wahoo.ts.net:2443/webhook/service-alerts`

Configure these in n8n to route to Slack.

---

## Related Documentation

- [CHARTER.md](/CHARTER.md) - Architectural rules
- [n8n Workflows](/docs/n8n-workflows/) - n8n configuration
- [Backup System](/docs/infrastructure/backup-system.md) - Backup integration
