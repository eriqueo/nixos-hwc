# Night 2 Report — Alerting Pipeline to ntfy + Stale Alert Fixes

**Date**: 2026-03-27
**Branch**: `claude/alertmanager-ntfy-bridge-aniQp`

## Summary

Wired the existing Prometheus/Alertmanager monitoring stack to deliver alerts to Eric's phone via ntfy. Fixed 3 false-positive ServiceDown alerts that had been firing since March 13. Fixed a critical alertmanager routing bug where ALL alerts were silently dropped.

## Changes Made

### 1. Alertmanager → ntfy Bridge (NEW)

**File**: `domains/alerts/parts/ntfy-bridge.nix`

Created a lightweight Python HTTP service that:
- Listens on `localhost:9095`
- Receives Alertmanager webhook POSTs (JSON)
- Translates each alert into a formatted ntfy notification
- Maps severity (P5/P4/P3) to ntfy priority levels (5/4/3)
- Sends resolved alerts at low priority with checkmark emoji
- Logs to `/var/log/hwc/alerts/ntfy-bridge.log`
- Runs as `eric:users` with systemd hardening

**Enabled in**: `machines/server/config.nix` → `hwc.alerts.ntfyBridge.enable = true`

### 2. Alertmanager Routing Fix (BUG FIX — CRITICAL)

**File**: `domains/monitoring/alertmanager/index.nix`

**Bug**: The default receiver was `"default"` which had no webhook_configs. ALL Prometheus alerts were silently dropped. The n8n-webhook receiver was defined but never referenced in any route.

**Fix**: Changed routing to use child routes with `continue: true` so alerts fan out to ALL configured webhook receivers (n8n-webhook AND ntfy-bridge).

### 3. ntfy Bridge Added as Second Alertmanager Receiver

**File**: `profiles/monitoring.nix`

Added `ntfy-bridge` (http://localhost:9095) alongside existing `n8n-webhook` receiver. Both receivers get all alerts. Slack delivery via n8n is preserved.

### 4. Immich Metrics Port Fix (3→0 false ServiceDown alerts)

**File**: `domains/media/immich-container/parts/config.nix`

**Bug**: Immich metrics ports 8091 (API) and 8092 (microservices) were set as container env vars but never published to the host. The container runs on `media` podman network — only port 2283 was mapped. Prometheus scraped `localhost:8091` and `localhost:8092` which didn't exist on the host.

**Fix**: Added port mappings `127.0.0.1:8091:8091` and `127.0.0.1:8092:8092` to the immich-server container, conditional on metrics being enabled.

### 5. Frigate Scrape Config Fix (1→0 false ServiceDown alerts)

**File**: `domains/media/frigate/index.nix`

**Bug**: Frigate container uses `--network=host`. Port mappings are ignored with host networking. The mapping `9191:9090` was silently ignored, so `localhost:9191` didn't exist. Additionally, Frigate doesn't natively export Prometheus metrics — that's what the separate `frigate-exporter` container is for.

**Fix**:
- Removed broken `9191:9090` port mapping
- Removed broken `frigate-nvr` Prometheus scrape config
- Enabled `hwc.media.frigate.exporter` in server config (port 9192, proper Prometheus metrics)

### 6. Frigate Exporter Enabled

**File**: `machines/server/config.nix`

Added `exporter.enable = true` to frigate config. The exporter container polls Frigate's `/api/stats` API and serves Prometheus-format metrics on port 9192.

## Files Changed

| File | Change |
|------|--------|
| `domains/alerts/parts/ntfy-bridge.nix` | **NEW** — Alertmanager → ntfy bridge service |
| `domains/alerts/index.nix` | Import ntfy-bridge module |
| `domains/monitoring/alertmanager/index.nix` | Fix routing: fan out to all receivers via child routes |
| `profiles/monitoring.nix` | Add ntfy-bridge as second webhook receiver |
| `machines/server/config.nix` | Enable ntfy bridge + frigate exporter |
| `domains/media/immich-container/parts/config.nix` | Publish metrics ports 8091/8092 to host |
| `domains/media/frigate/index.nix` | Remove broken port mapping + scrape config |
| `domains/alerts/README.md` | Updated structure + changelog |
| `domains/monitoring/README.md` | Updated changelog |
| `domains/media/frigate/README.md` | Updated changelog |
| `domains/media/immich-container/README.md` | Updated changelog |
| `night2_audit.md` | Full audit of notification landscape |

## What Was NOT Changed

- Prometheus alert rules (thresholds unchanged)
- Grafana dashboards
- Existing Slack/n8n notification path (preserved as-is)
- n8n workflows (not touched)
- No `nixos-rebuild switch` was run

## Eric's Action Items

### Before Applying

1. **Run `nix flake check`** — nix was not available in the CI environment
2. **Review the alertmanager routing change** — this was a silent bug; all Prometheus alerts have been silently dropped since alertmanager was configured
3. **Consider the ModerateDiskUsage alert** — P3 at 75% threshold. Decide if this is noise or useful once ntfy is delivering

### After `nixos-rebuild switch`

4. **Test ntfy delivery**:
   ```bash
   # Direct ntfy test
   curl -d "Night 2 test — alerting pipeline working" \
     -H "Title: Test Alert" -H "Tags: test_tube" \
     http://localhost:2586/hwc-alerts

   # Alertmanager → ntfy bridge test
   curl -X POST http://localhost:9093/api/v2/alerts \
     -H "Content-Type: application/json" \
     -d '[{"labels":{"alertname":"TestAlert","severity":"P3"},"annotations":{"summary":"Night 2 ntfy bridge test"},"startsAt":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}]'
   ```

5. **Verify stale alerts cleared**:
   ```bash
   curl -s http://localhost:9090/api/v1/alerts | python3 -c "
   import json, sys
   data = json.load(sys.stdin)
   firing = [a for a in data['data']['alerts'] if a['state'] == 'firing']
   print(f'{len(firing)} alerts still firing')
   for a in firing:
       print(f\"  {a['labels'].get('alertname')}: {a['labels'].get('instance')}\")
   "
   ```

6. **Check bridge service**:
   ```bash
   systemctl status alertmanager-ntfy-bridge
   journalctl -u alertmanager-ntfy-bridge -f
   ```

7. **Subscribe to ntfy topic on phone**: Open ntfy app → subscribe to `hwc-alerts` on `https://hwc.ocelot-wahoo.ts.net:2586`

### Optional Enhancements

- Adjust ModerateDiskUsage threshold (75% → 80%?) if too noisy
- Add more scrape targets for services like heartwood-mcp (:6100), estimator-api (:8099)
- Consider adding state-change-only tracking in the bridge to avoid repeat notifications (Alertmanager's `repeat_interval: 4h` handles this partially)
