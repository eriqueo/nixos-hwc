# n8n Workflow Plan for HWC Server Services

## Overview

This plan defines n8n workflows to enable Slack-based monitoring, control, and notifications for all major server services. Each workflow will:
- Report service status, errors, and important events to Slack
- Accept commands via Slack for service control
- Integrate with the existing webhook infrastructure

## Webhook URLs

| Type | URL | Purpose |
|------|-----|---------|
| Internal | `https://hwc.ocelot-wahoo.ts.net/webhook/*` | Service-to-service communication |
| Public (Funnel) | `https://hwc.ocelot-wahoo.ts.net:10000/webhook/*` | Slack interactivity, external integrations |
| n8n Direct | `https://hwc.ocelot-wahoo.ts.net:2443/webhook/*` | Alertmanager, internal triggers |

## Slack Bot Architecture

### Option A: Single Unified Bot (Recommended)
- **Bot Name**: `HWC Server`
- **Channels**:
  - `#hwc-alerts` - Critical alerts, errors
  - `#hwc-media` - Media service updates
  - `#hwc-system` - System/infrastructure status
- **Pros**: Simpler management, single OAuth setup
- **Cons**: All notifications from one source

### Option B: Domain-Specific Bots
Multiple Slack apps, each with focused purpose:
1. `HWC Media Bot` - Media stack (Jellyfin, *arr, downloads)
2. `HWC System Bot` - Infrastructure (Caddy, monitoring, backups)
3. `HWC AI Bot` - AI services (Ollama, Open-WebUI)
4. `HWC Finance Bot` - Firefly III notifications

---

## Workflows by Domain

### 1. Media Services Domain

#### 1.1 Media Library Monitor
**Trigger**: Schedule (every 15 min) + Webhook
**Services**: Jellyfin, Immich, Navidrome, Audiobookshelf
**Notifications**:
- New content added to libraries
- Playback session started/ended
- Transcoding errors
- Library scan completion

**Slack Commands**:
- `/media status` - Show all media service health
- `/media scan [service]` - Trigger library scan
- `/media sessions` - Show active playback sessions

**Webhook Path**: `/webhook/media-monitor`

#### 1.2 Arr Stack Orchestrator
**Trigger**: Webhook (from *arr apps) + Schedule
**Services**: Sonarr, Radarr, Lidarr, Readarr, Prowlarr
**Notifications**:
- Download grabbed/completed
- Import success/failure
- Missing episodes/movies detected
- Indexer health issues

**Slack Commands**:
- `/arr status` - Show all *arr service status
- `/arr search [query]` - Search across all *arrs
- `/arr queue` - Show download queue
- `/arr missing` - Show missing content summary

**Webhook Path**: `/webhook/arr-orchestrator`

#### 1.3 Download Manager
**Trigger**: Webhook + Schedule (every 5 min)
**Services**: Sabnzbd, qBittorrent, slskd, Gluetun
**Notifications**:
- Download started/completed
- VPN connection status changes
- Port forwarding updates
- Download errors/stalls

**Slack Commands**:
- `/dl status` - Show download client status
- `/dl queue` - Show active downloads
- `/dl vpn` - Show VPN/Gluetun status
- `/dl pause` / `/dl resume` - Control downloads

**Webhook Path**: `/webhook/download-manager`

---

### 2. Infrastructure Domain

#### 2.1 System Health Dashboard
**Trigger**: Schedule (every 5 min) + Alertmanager webhook
**Services**: All systemd services, containers
**Notifications**:
- Service down/recovered
- High CPU/memory/disk usage
- Container restart events
- Systemd unit failures

**Slack Commands**:
- `/sys status` - Full system health overview
- `/sys restart [service]` - Restart a service
- `/sys logs [service]` - Recent logs snippet
- `/sys disk` - Disk usage summary

**Webhook Path**: `/webhook/system-health`

#### 2.2 Reverse Proxy Monitor
**Trigger**: Schedule + Error log webhook
**Services**: Caddy
**Notifications**:
- Upstream service unreachable
- Certificate renewal events
- High error rate on routes
- New routes activated

**Slack Commands**:
- `/proxy status` - Show all routes health
- `/proxy reload` - Reload Caddy config

**Webhook Path**: `/webhook/proxy-monitor`

#### 2.3 Backup & Storage Monitor
**Trigger**: Schedule (daily) + Completion webhook
**Services**: Restic, storage mounts
**Notifications**:
- Backup started/completed
- Backup failures
- Storage space warnings
- Mount health issues

**Slack Commands**:
- `/backup status` - Show backup status
- `/backup run [name]` - Trigger manual backup
- `/storage` - Show storage usage

**Webhook Path**: `/webhook/backup-monitor`

---

### 3. Surveillance Domain

#### 3.1 Frigate Intelligence
**Trigger**: Webhook (from Frigate MQTT/HTTP)
**Services**: Frigate
**Notifications**:
- Person detected (with snapshot)
- Vehicle detected
- Camera offline/online
- Recording events

**Slack Commands**:
- `/cam status` - Camera health overview
- `/cam snapshot [camera]` - Get current snapshot
- `/cam events [camera]` - Recent events
- `/cam arm` / `/cam disarm` - Change detection mode

**Webhook Path**: `/webhook/frigate-events`

---

### 4. AI/ML Domain

#### 4.1 AI Service Monitor
**Trigger**: Schedule + API health checks
**Services**: Ollama, Open-WebUI, AI Model Router
**Notifications**:
- Model loading/unloading
- GPU memory pressure
- Inference errors
- Model availability changes

**Slack Commands**:
- `/ai status` - AI stack health
- `/ai models` - List loaded models
- `/ai gpu` - GPU utilization

**Webhook Path**: `/webhook/ai-monitor`

---

### 5. Documents & Finance Domain

#### 5.1 Document Processing
**Trigger**: Webhook (from Paperless)
**Services**: Paperless-NGX
**Notifications**:
- Document consumed/processed
- OCR completion
- Classification results
- Processing errors

**Slack Commands**:
- `/docs status` - Paperless health
- `/docs recent` - Recent documents
- `/docs inbox` - Inbox count

**Webhook Path**: `/webhook/paperless`

#### 5.2 Finance Notifications
**Trigger**: Webhook (from Firefly III)
**Services**: Firefly III, Firefly-Pico
**Notifications**:
- Transaction imported
- Budget warnings
- Rule triggers
- Reconciliation reminders

**Slack Commands**:
- `/finance status` - Firefly health
- `/finance balance` - Account balances
- `/finance recent` - Recent transactions

**Webhook Path**: `/webhook/firefly`

---

### 6. Books & Reading Domain

#### 6.1 Book Library Monitor
**Trigger**: Schedule + Webhook
**Services**: Calibre, LazyLibrarian, Audiobookshelf, Readarr
**Notifications**:
- New book/audiobook added
- Download completed
- Library scan results

**Slack Commands**:
- `/books status` - Book services health
- `/books search [query]` - Search libraries
- `/books recent` - Recently added

**Webhook Path**: `/webhook/books-monitor`

---

## Shared Components

### Error Handler Workflow
All workflows should use a shared error handler that:
1. Catches workflow errors
2. Formats error details
3. Sends to `#hwc-alerts` with severity
4. Logs to persistent storage

**Webhook Path**: `/webhook/error-handler`

### Notification Router Workflow
Central routing for all notifications:
1. Receives events from all workflows
2. Applies routing rules (channel, urgency)
3. Deduplicates rapid-fire alerts
4. Formats messages consistently

**Webhook Path**: `/webhook/notify`

### Slack Command Router
Single entry point for all Slack slash commands:
1. Receives from Slack interactivity
2. Parses command and arguments
3. Routes to appropriate workflow
4. Returns response to Slack

**Webhook Path**: `/webhook/slack-commands`

---

## Implementation Priority

### Phase 1: Foundation
1. [ ] Notification Router (shared component)
2. [ ] Error Handler (shared component)
3. [ ] Slack Command Router
4. [ ] System Health Dashboard (extends existing Cross-Service Health Monitor)

### Phase 2: Media Stack
5. [ ] Arr Stack Orchestrator
6. [ ] Download Manager
7. [ ] Media Library Monitor

### Phase 3: Infrastructure
8. [ ] Reverse Proxy Monitor
9. [ ] Backup & Storage Monitor

### Phase 4: Specialized
10. [ ] Frigate Intelligence
11. [ ] AI Service Monitor
12. [ ] Document Processing
13. [ ] Finance Notifications
14. [ ] Book Library Monitor

---

## Slack App Configuration

### Required OAuth Scopes
```
chat:write
chat:write.public
commands
incoming-webhook
files:write
users:read
channels:read
groups:read
```

### Slash Commands to Register
| Command | Request URL | Description |
|---------|-------------|-------------|
| `/hwc` | `https://hwc.ocelot-wahoo.ts.net:10000/webhook/slack-commands` | Main HWC command router |
| `/media` | (same) | Media services |
| `/arr` | (same) | Arr stack |
| `/dl` | (same) | Downloads |
| `/sys` | (same) | System |
| `/cam` | (same) | Cameras |
| `/ai` | (same) | AI services |
| `/docs` | (same) | Documents |
| `/finance` | (same) | Finance |
| `/books` | (same) | Books |

### Interactivity URL
`https://hwc.ocelot-wahoo.ts.net:10000/webhook/slack-interactivity`

---

## Service API Endpoints Reference

| Service | Health Check | API Docs |
|---------|--------------|----------|
| Jellyfin | `http://127.0.0.1:8096/health` | `/api-docs` |
| Sonarr | `http://127.0.0.1:8989/api/v3/health` | Built-in |
| Radarr | `http://127.0.0.1:7878/api/v3/health` | Built-in |
| Lidarr | `http://127.0.0.1:8686/api/v1/health` | Built-in |
| Prowlarr | `http://127.0.0.1:9696/api/v1/health` | Built-in |
| Frigate | `http://127.0.0.1:5001/api/config` | Built-in |
| Paperless | `http://127.0.0.1:8102/api/` | Built-in |
| Grafana | `http://127.0.0.1:3000/api/health` | Built-in |
| Prometheus | `http://127.0.0.1:9090/-/healthy` | Built-in |
| qBittorrent | `http://127.0.0.1:8080/api/v2/app/version` | Built-in |
| Sabnzbd | `http://127.0.0.1:8081/api?mode=queue` | Built-in |
| Immich | `http://127.0.0.1:2283/api/server/ping` | Built-in |
| Navidrome | `http://127.0.0.1:4533/rest/ping` | Subsonic API |
| ntfy | `http://127.0.0.1:2586/v1/health` | Built-in |

---

## Next Steps

1. **Confirm Slack bot approach** (unified vs. domain-specific)
2. **Set up Slack app** with required scopes
3. **Create foundation workflows** (Notification Router, Error Handler, Command Router)
4. **Implement Phase 1** workflows
5. **Test Slack integration** end-to-end
6. **Iterate** through remaining phases

