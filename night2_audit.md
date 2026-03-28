# Night 2 Audit Report — Notification Landscape

**Date**: 2026-03-27
**Auditor**: Claude (automated)

## 1. Current Notification Channels

### Slack (via n8n webhooks)
- **Service failure notifier**: `hwc-service-failure-notifier@` systemd template — triggers on `OnFailure=` for 16 critical services, sends to Slack via `hwc-service-failure-notify` script
- **Alertmanager → n8n**: Webhook receiver at `https://hwc.ocelot-wahoo.ts.net:2443/webhook/alertmanager` — receives all Prometheus alerts, presumably routes to Slack
- **Backup notifications**: `hwc-backup-notify` sends to Slack webhook
- **Disk space checks**: `hwc-disk-space-check` hourly timer, sends to Slack webhook
- **SMART disk alerts**: `hwc-smartd-notify` hooks into smartd, sends to Slack webhook
- **Webhook health check**: Runs every 15 minutes to verify n8n endpoint is reachable

### ntfy (partially configured)
- **ntfy server**: Container on port 8080, exposed via Tailscale HTTPS at `https://hwc.ocelot-wahoo.ts.net:2586`
- **ntfy CLI tool**: `hwc-ntfy-send` installed system-wide, configured for `ntfy.sh` with default topic `hwc-alerts`
- **Backup integration**: Local backup script calls `hwc-ntfy-send` on success/failure
- **NOT wired to Alertmanager**: No bridge exists between Alertmanager and ntfy

## 2. Alertmanager Configuration

- **Port**: 9093
- **Receivers**: 1 webhook receiver → n8n (`n8n-webhook`)
- **Default receiver**: `default` (empty — alerts matching no route are silently dropped)
- **Route**: Groups by `alertname, cluster, service`; 30s wait, 5m interval, 4h repeat
- **Problem**: Default receiver is empty. Only `n8n-webhook` receiver is configured but the route sends to `default`, not `n8n-webhook`!

## 3. Prometheus Alert Rules

### P5 — Critical (6 rules)
- HighCPUUsage (>90% for 10m)
- HighMemoryUsage (>95% for 10m)
- HighDiskUsage (>95% for 15m, root only)
- **ServiceDown** (`up == 0` for 5m) — catches any scrape target that's unreachable
- FrigateCameraOffline (fps < 1 for 5m)
- ImmichHighErrorRate (>10 errors/sec for 10m)

### P4 — Warning (7 rules)
- ElevatedCPUUsage (>70%), ElevatedMemoryUsage (>80%), ElevatedDiskUsage (>85%)
- FrigateLowFPS, FrigateHighCPU, ImmichLargeQueue, ContainerHighMemory

### P3 — Info (4 rules)
- **ModerateDiskUsage** (>75% for 1h) — likely legitimate
- FrigateDetectionSpike, ImmichSlowAPI, HighNetworkTraffic

## 4. Currently Firing Alerts (4 stale since ~Mar 13)

### ServiceDown — immich-api (localhost:8091)
**Root cause**: Immich container uses `media` podman network. Port 8091 is set as `IMMICH_API_METRICS_PORT` env var inside the container but **never mapped to the host**. Only port 2283:3001 is published.
**Fix**: Add `"127.0.0.1:8091:8091"` port mapping to immich-server container.

### ServiceDown — immich-workers (localhost:8092)
**Root cause**: Same as above — port 8092 (`IMMICH_MICROSERVICES_METRICS_PORT`) is never mapped to the host.
**Fix**: Add `"127.0.0.1:8092:8092"` port mapping to immich-server container.

### ServiceDown — frigate-nvr (localhost:9191)
**Root cause**: Frigate container uses `--network=host` mode. The port mapping `"9191:9090"` is **ignored** when using host networking — container ports bind directly to the host. Port 9090 inside the container (if it exists) would conflict with Prometheus on the host. The scrape config targets `localhost:9191` which doesn't exist.
Additionally, there's a **separate** `frigate-exporter` container (port 9192) that properly exports Frigate metrics. The `frigate-nvr` scrape job in `frigate/index.nix` is redundant.
**Fix**: Remove the broken `9191:9090` port mapping and the `frigate-nvr` scrape config from `frigate/index.nix`. The `frigate-exporter` at port 9192 already handles metrics correctly.

### ModerateDiskUsage — node
**Root cause**: Likely legitimate — disk usage >75% on some mountpoint. This is an info-level (P3) alert. Not a false positive, just noisy.
**Assessment**: No code change needed. Once ntfy is wired, Eric can evaluate whether 75% threshold is appropriate.

## 5. Alertmanager Routing Bug

The alertmanager config has a critical routing issue:
```
route.receiver = "default"   # ← empty receiver, drops all alerts!
```
The `n8n-webhook` receiver is defined but never referenced in routing. All alerts go to `default` (which has no webhook_configs), so **no alerts are actually delivered anywhere**.

**Fix**: Change the default receiver to `n8n-webhook`, or add explicit route matching.

## 6. ntfy Infrastructure Status

- ntfy server container: Running on port 8080, Tailscale-exposed on port 2586
- ntfy CLI (`hwc-ntfy-send`): Functional, used by backup scripts
- **Missing**: Alertmanager → ntfy bridge (no translation layer exists)
- **Missing**: Alert routing to ntfy topic

## 7. n8n Workflows (investigation needed at runtime)

- `sys_alertmanager_router` — likely receives Alertmanager webhooks and routes to Slack
- `Cross-Service Health Monitor` — likely does HTTP health checks
- Both updated Mar 25, suggesting recent maintenance
- Cannot inspect workflow details without runtime access to n8n API

## 8. Recommendations

1. **Create alertmanager-ntfy-bridge**: Small Python HTTP service that receives Alertmanager webhooks and forwards to ntfy
2. **Fix alertmanager routing**: Change default receiver to `n8n-webhook` so alerts actually get delivered
3. **Add ntfy as second receiver**: Keep Slack delivery via n8n, add ntfy bridge as additional receiver
4. **Fix stale alerts**: Map immich metrics ports, remove broken frigate scrape config
5. **Test end-to-end**: Fire a test alert through Alertmanager and verify ntfy delivery
