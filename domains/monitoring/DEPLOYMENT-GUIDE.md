# Monitoring Stack Deployment Guide

**Charter v7.0 Compliant** | **Created:** 2025-12-07

## Overview

This guide walks through deploying the complete monitoring stack:
- **Prometheus** - Metrics collection (90-day retention)
- **Grafana** - Dashboards and visualization
- **Alertmanager** - Alert routing
- **n8n** - Workflow automation for Slack notifications

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐     ┌─────────┐
│  Frigate    │────▶│  Prometheus  │────▶│ Alertmanager│────▶│   n8n   │────▶ Slack
│  Immich     │     │  (metrics)   │     │  (routing)  │     │(webhook)│
│  System     │     └──────┬───────┘     └─────────────┘     └─────────┘
└─────────────┘            │
                           │
                    ┌──────▼───────┐
                    │   Grafana    │
                    │ (dashboards) │
                    └──────────────┘
```

## Pre-Deployment Checklist

- [x] Charter v7.0 structure implemented
- [x] All modules have proper VALIDATION sections
- [x] Grafana admin password encrypted via agenix
- [x] Caddy reverse proxy routes configured
- [x] Alert rules organized by severity (P5/P4/P3)
- [x] Dashboard JSON files created
- [x] `nix flake check` passes

## Access Points (Post-Deployment)

| Service | URL | Port | Notes |
|---------|-----|------|-------|
| Grafana | `https://hwc.lan:4443` | 4443 | Login: admin / [from secret] |
| n8n | `https://hwc.lan/n8n` | - | Subpath mode via Caddy |
| Prometheus | `http://localhost:9090` | 9090 | Localhost only |
| Alertmanager | `http://localhost:9093` | 9093 | Localhost only |

## Step 1: Deploy the Stack

```bash
# From /etc/nixos (or ~/.nixos)
sudo nixos-rebuild switch --flake .#hwc-server

# Verify services started
systemctl status prometheus
systemctl status grafana
systemctl status alertmanager
systemctl status n8n

# Check for errors
journalctl -u prometheus -n 50
journalctl -u grafana -n 50
journalctl -u alertmanager -n 50
journalctl -u n8n -n 50
```

## Step 2: Initial Grafana Setup

1. **Access Grafana**: Navigate to `https://hwc.lan:4443`

2. **Login Credentials**:
   - Username: `admin`
   - Password: Check secret with `sudo age -d -i /etc/age/keys.txt domains/secrets/parts/server/grafana-admin-password.age`

3. **Verify Prometheus Datasource**:
   - Go to Configuration → Data Sources
   - "Prometheus" should be pre-configured
   - Test the connection

4. **Verify Dashboards**:
   - Navigate to Dashboards → Browse
   - You should see 5 dashboards:
     - System Health
     - Frigate Monitoring
     - Immich Monitoring
     - Container Health
     - Arr Apps

## Step 3: Configure n8n Workflow

### 3.1 Access n8n

Navigate to `https://hwc.lan/n8n` and complete initial setup:
- Create admin account
- Set timezone (should default to America/New_York)

### 3.2 Create Slack Webhook Workflow

1. **Create New Workflow**: "Alertmanager → Slack"

2. **Add Webhook Trigger Node**:
   - Node: `Webhook`
   - HTTP Method: `POST`
   - Path: `alertmanager`
   - Response: `Immediately`

3. **Add Function Node** (Parse Alerts):
   ```javascript
   // Parse Alertmanager webhook payload
   const alerts = $input.item.json.alerts;
   const formatted = alerts.map(alert => ({
     severity: alert.labels.severity,
     category: alert.labels.category,
     summary: alert.annotations.summary,
     description: alert.annotations.description,
     status: alert.status
   }));
   return formatted;
   ```

4. **Add Slack Node**:
   - Authentication: Create Slack credential
   - Channel: Your alert channel (e.g., `#alerts`)
   - Message Template:
     ```
     🚨 *{{ $json.severity }}* Alert - {{ $json.category }}

     *Summary:* {{ $json.summary }}
     *Details:* {{ $json.description }}
     *Status:* {{ $json.status }}
     ```

5. **Activate Workflow** and copy the webhook URL

### 3.3 Configure Alertmanager Webhooks

Edit `profiles/monitoring.nix`:

```nix
hwc.server.monitoring.alertmanager = {
  enable = true;
  webhookReceivers = [
    {
      name = "n8n-slack";
      url = "https://hwc.lan/n8n/webhook/alertmanager";  # Your webhook URL
      sendResolved = true;
    }
  ];
};
```

Rebuild and switch:
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

## Step 4: Test Alert Flow

### Test via Prometheus

1. Access Prometheus: `http://localhost:9090` (via Tailscale or local)

2. Check alert rules are loaded:
   - Status → Rules
   - Should see 3 groups: critical_alerts, warning_alerts, info_alerts

3. Trigger a test alert (simulate high CPU):
   ```bash
   # Run stress test
   stress-ng --cpu 8 --timeout 15m
   ```

4. Monitor alert progression:
   - Prometheus → Alerts (should go from Inactive → Pending → Firing)
   - Alertmanager → `http://localhost:9093` (alert should appear)
   - Slack channel (should receive notification via n8n)

## Step 5: Review Dashboards

### System Health Dashboard
- CPU usage per core
- Memory usage
- Disk usage (root + /mnt/*)
- Network traffic

### Frigate Monitoring Dashboard
- Camera FPS (all cameras)
- Detection FPS
- Detection events timeline
- TensorRT inference speed
- Resource usage

### Immich Monitoring Dashboard
- API request rate
- Response times (p95/p99)
- Worker queue sizes
- Job completion rates
- Storage usage

### Container Health Dashboard
- CPU usage per container
- Memory usage per container
- Network traffic
- Health status

### Arr Apps Dashboard
- Total items (series/movies/artists/indexers)
- Download rates
- Queue sizes
- Service status (up/down)

## Alert Severity Levels

### P5 - Critical (Immediate Action)
- CPU > 90% for 10 minutes
- Memory > 95% for 10 minutes
- Disk > 95% for 15 minutes
- Service down for 5 minutes
- Frigate camera offline
- Immich high error rate (> 10 errors/sec)

### P4 - Warning (Investigate Soon)
- CPU > 70% for 15 minutes
- Memory > 80% for 15 minutes
- Disk > 85% for 30 minutes
- Frigate low FPS (< 10)
- Immich large queue (> 100 jobs)
- Container high memory (> 2GB)

### P3 - Info (Monitor)
- Disk > 75% for 1 hour
- Frigate detection spike (> 50 events/hour)
- Immich slow API (p95 > 2000ms)
- High network traffic (> 100MB/s)

## Troubleshooting

### Prometheus Not Scraping Metrics

```bash
# Check scrape targets
curl http://localhost:9090/api/v1/targets

# Verify exporters are running
systemctl status prometheus-node-exporter

# Check Frigate metrics endpoint
curl http://localhost:9191/metrics

# Check Immich metrics endpoint
curl http://localhost:2283/metrics
```

### Grafana Can't Connect to Prometheus

```bash
# Verify Prometheus is listening
ss -tlnp | grep 9090

# Check Grafana logs
journalctl -u grafana -f

# Test connection from Grafana service
sudo -u eric curl http://localhost:9090/api/v1/query?query=up
```

### Alertmanager Not Receiving Alerts

```bash
# Check Alertmanager config
journalctl -u alertmanager -n 100

# Verify Prometheus knows about Alertmanager
curl http://localhost:9090/api/v1/alertmanagers

# Check alert rules are loaded
curl http://localhost:9090/api/v1/rules
```

### n8n Webhook Not Firing

1. Check n8n logs: `journalctl -u n8n -f`
2. Verify webhook URL is accessible: `curl https://hwc.lan/n8n/webhook/alertmanager`
3. Test Alertmanager → n8n directly:
   ```bash
   curl -X POST https://hwc.lan/n8n/webhook/alertmanager \
     -H "Content-Type: application/json" \
     -d '{
       "alerts": [{
         "status": "firing",
         "labels": {"severity": "P5", "category": "test"},
         "annotations": {"summary": "Test alert", "description": "Testing webhook"}
       }]
     }'
   ```

## Maintenance

### Updating Dashboards

1. Edit JSON files in `domains/server/monitoring/grafana/dashboards/`
2. Rebuild: `sudo nixos-rebuild switch --flake .#hwc-server`
3. Dashboards auto-update (30-second polling interval)

### Adjusting Alert Thresholds

1. Edit `domains/server/monitoring/prometheus/parts/alerts.nix`
2. Modify `expr` values or `for` durations
3. Rebuild and switch
4. Verify: `curl http://localhost:9090/api/v1/rules`

### Rotating Grafana Password

```bash
# Generate new password
NEW_PW=$(head -c 32 /dev/urandom | base64)
echo "$NEW_PW"

# Encrypt with age
echo "$NEW_PW" | age -r age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne \
  > domains/secrets/parts/server/grafana-admin-password.age

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# New password active on next Grafana restart
systemctl restart grafana
```

## Backup Considerations

### What to Backup

1. **Grafana data**: `/var/lib/hwc/grafana/` (dashboards, users, datasources)
2. **Prometheus data**: `/var/lib/hwc/prometheus/` (metrics, 90 days)
3. **n8n workflows**: `/var/lib/hwc/n8n/` (workflows, credentials, executions)
4. **Alertmanager data**: `/var/lib/hwc/alertmanager/` (silences, notifications)

### Quick Backup Script

```bash
#!/usr/bin/env bash
# Backup monitoring stack data
BACKUP_DIR="/mnt/backup/monitoring-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

sudo rsync -av /var/lib/hwc/grafana/ "$BACKUP_DIR/grafana/"
sudo rsync -av /var/lib/hwc/n8n/ "$BACKUP_DIR/n8n/"
sudo rsync -av /var/lib/hwc/alertmanager/ "$BACKUP_DIR/alertmanager/"

# Note: Prometheus data is large, consider selective backup or rely on rebuild
echo "Backup complete: $BACKUP_DIR"
```

## Post-Deployment Tasks (Phase 6)

- [ ] Configure n8n workflow for Alertmanager → Slack
- [ ] Test alert flow end-to-end
- [ ] Set up Slack incoming webhook
- [ ] Create alert runbooks for P5 alerts
- [ ] Configure alert silencing rules for maintenance
- [ ] Set up additional scrape configs for Arr apps (if exporters available)

## Module Structure (Reference)

```
domains/server/monitoring/
├── index.nix                    # Domain aggregator
├── prometheus/
│   ├── index.nix               # Implementation + validation
│   ├── options.nix             # Configuration API
│   └── parts/
│       └── alerts.nix          # Alert rules (P5/P4/P3)
├── grafana/
│   ├── index.nix               # Implementation + validation
│   ├── options.nix             # Configuration API
│   └── dashboards/             # Provisioned dashboards
│       ├── system-health.json
│       ├── frigate-monitoring.json
│       ├── immich-monitoring.json
│       ├── container-health.json
│       └── arr-apps.json
└── alertmanager/
    ├── index.nix               # Implementation + validation
    └── options.nix             # Configuration API

domains/server/n8n/
├── index.nix                   # Implementation + validation
└── options.nix                 # Configuration API

profiles/monitoring.nix         # Feature toggle + configuration
domains/server/routes.nix       # Caddy reverse proxy routes
```

## Questions or Issues?

- Check Charter v7.0 compliance: `./workspace/utilities/lints/charter-lint.sh domains/server/monitoring`
- Review module logs: `journalctl -u <service-name> -f`
- Validate build: `nix flake check`
- Test configuration: `sudo nixos-rebuild test --flake .#hwc-server`

**Version**: 1.0
**Last Updated**: 2025-12-07
**Maintainer**: Eric (with Claude Code assistance)
