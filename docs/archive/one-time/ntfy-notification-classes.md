# ntfy Notification Class System

**Infrastructure**: Self-hosted ntfy at `https://hwc-server.ocelot-wahoo.ts.net/notify`

---

## Topic Architecture

### Topic Naming Convention
- **hwc-critical** - P5, immediate action required (server down, disk full, security)
- **hwc-alerts** - P4, important but not urgent (service restarts, warnings)
- **hwc-backups** - P3, backup status (failures only by default)
- **hwc-media** - P2, media service events (new content, library updates)
- **hwc-monitoring** - P2, monitoring/stats (resource usage, health checks)
- **hwc-updates** - P1, system updates and rebuilds
- **hwc-ai** - P2, AI/ML workflow completions

### Machine-Specific Topics (for debugging/detailed logs)
- **hwc-server-events** - All server events
- **hwc-laptop-events** - All laptop events

---

## Notification Classes

### 1. CRITICAL (Priority 5) - `hwc-critical`
**Immediate attention required**

Use cases:
- ❌ System services failed (Jellyfin, Immich, Caddy down)
- 💾 Disk space >95% full
- 🔥 Temperature critical (GPU >85°C, CPU >90°C)
- 🔒 Security events (repeated SSH failures, firewall breaches)
- 💥 Container crashes (Frigate, media services)
- ⚡ Power loss (UPS battery, server unexpected shutdown)
- 📦 RAID degradation
- 🚨 Backup failures

**Retention**: 7 days
**Phone behavior**: Max urgency, override DND

---

### 2. ALERTS (Priority 4) - `hwc-alerts`
**Important but not urgent**

Use cases:
- ⚠️ Disk space >80% (warning level)
- 🔄 Service restarts (automatic recovery)
- 🌡️ Temperature warnings (GPU >75°C, CPU >80°C)
- 📡 Tailscale reconnections
- 🐳 Container restarts
- 💿 SMART warnings (disk health degrading)
- 🔌 Power state changes (laptop AC/battery)

**Retention**: 3 days
**Phone behavior**: High priority

---

### 3. BACKUPS (Priority 3) - `hwc-backups`
**Backup operations**

Use cases:
- ❌ Backup failures (local, cloud)
- ✅ Backup success (optional, can be noisy)
- 🔍 Backup verification failures
- 📊 Weekly backup summary
- 💾 Backup storage space warnings

**Retention**: 7 days (for audit trail)
**Phone behavior**: Normal priority

---

### 4. MEDIA (Priority 2) - `hwc-media`
**Media service events**

Use cases:
- 🎬 Jellyfin library scan complete
- 📸 Immich bulk upload complete (>100 photos)
- 🎵 Navidrome new music added
- 📹 Frigate person detection events
- 🎥 Frigate motion detected (optional, can be noisy)
- 📺 Media service health checks

**Retention**: 2 days
**Phone behavior**: Low priority
**Note**: Can be filtered by tags (person, motion, library)

---

### 5. MONITORING (Priority 2) - `hwc-monitoring`
**System monitoring and health**

Use cases:
- 📊 Daily resource usage summary
- 💻 CPU/GPU utilization >80% sustained
- 🌡️ Temperature normal after warning
- 💾 Storage usage trends
- 🔋 UPS battery status
- 🌐 Network bandwidth anomalies
- 🐳 Container resource usage

**Retention**: 1 day
**Phone behavior**: Low priority

---

### 6. UPDATES (Priority 1) - `hwc-updates`
**System updates and maintenance**

Use cases:
- 🔄 NixOS rebuild successful
- ❌ NixOS rebuild failed
- 📦 Flake updates available
- 🔒 Security updates available
- 🎯 Successful deployments
- 📝 Configuration changes applied

**Retention**: 3 days
**Phone behavior**: Min priority

---

### 7. AI/ML (Priority 2) - `hwc-ai`
**AI workflow events**

Use cases:
- 🤖 Ollama model download complete
- 📝 Daily journal generation complete
- 🧹 File cleanup agent completed
- 📄 Auto-documentation generated
- ⚠️ AI service errors
- 🔧 MCP server issues

**Retention**: 2 days
**Phone behavior**: Low priority

---

## Implementation Examples

### Server Critical Events

```bash
# Disk space critical
if [ $USAGE -gt 95 ]; then
  hwc-ntfy-send --priority 5 --tag disk,critical \
    hwc-critical \
    "🚨 CRITICAL: Disk Space" \
    "$(hostname): Root filesystem at ${USAGE}%! Immediate cleanup required."
fi

# Service failure (systemd OnFailure)
hwc-ntfy-send --priority 5 --tag service,failure \
  hwc-critical \
  "❌ Service Failed: %n" \
  "$(hostname): Service %n has failed. Check journalctl -u %n"

# GPU temperature critical
hwc-ntfy-send --priority 5 --tag gpu,temperature \
  hwc-critical \
  "🔥 GPU Temperature Critical" \
  "$(hostname): GPU at ${TEMP}°C! Thermal throttling likely."
```

### Backup Integration

```bash
# Backup failure
hwc-ntfy-send --priority 5 --tag backup,failure \
  hwc-critical \
  "[$(hostname)] Backup FAILED" \
  "Backup failed. Check logs immediately."

# Backup success (to backups topic)
hwc-ntfy-send --priority 3 --tag backup,success \
  hwc-backups \
  "[$(hostname)] Backup Success" \
  "Weekly backup completed. Size: $BACKUP_SIZE"
```

### Media Events

```bash
# Immich upload complete
hwc-ntfy-send --priority 2 --tag immich,photos \
  hwc-media \
  "📸 Photo Upload Complete" \
  "$COUNT new photos added to Immich library"

# Frigate person detection
hwc-ntfy-send --priority 2 --tag frigate,person \
  hwc-media \
  "👤 Person Detected" \
  "Front door camera detected person at $(date)"
```

### Storage Warnings

```bash
# Disk space warning (80%)
hwc-ntfy-send --priority 4 --tag disk,warning \
  hwc-alerts \
  "⚠️ Disk Space Warning" \
  "$(hostname): Root at ${USAGE}%. Consider cleanup."

# SMART warning
hwc-ntfy-send --priority 4 --tag smart,health \
  hwc-alerts \
  "💿 Disk Health Warning" \
  "Drive $DEVICE showing SMART errors. Backup and replace soon."
```

### AI Workflow Complete

```bash
# Daily journal generated
hwc-ntfy-send --priority 2 --tag ai,journal \
  hwc-ai \
  "📝 Daily Journal Generated" \
  "AI summary complete. $(wc -l < $JOURNAL_FILE) lines written."
```

### NixOS Updates

```bash
# Rebuild successful
hwc-ntfy-send --priority 1 --tag nixos,rebuild \
  hwc-updates \
  "✅ NixOS Rebuild Success" \
  "$(hostname): System rebuilt successfully. Generation $GENERATION"

# Rebuild failed
hwc-ntfy-send --priority 4 --tag nixos,rebuild,failure \
  hwc-alerts \
  "❌ NixOS Rebuild Failed" \
  "$(hostname): Build failed. Check nixos-rebuild logs."
```

---

## Phone Automations

### ntfy Click Actions

Notifications can include click actions that:
- Open SSH apps with pre-filled commands
- Trigger Tasker/Shortcuts automations
- Open web dashboards (Jellyfin, Immich, Frigate)
- Copy error messages to clipboard

Example with click action:
```bash
hwc-ntfy-send --priority 5 \
  hwc-critical \
  "Service Failed" \
  "Jellyfin crashed. Click to view logs." \
  --click "https://hwc-server.ocelot-wahoo.ts.net/jellyfin"
```

### Bi-directional Communication

**Phone → Server**:
- Send commands via ntfy topics
- Server monitors `hwc-commands` topic
- Authenticated actions (restart services, run backups, etc.)

**Example**:
```bash
# On server: listen for commands
ntfy sub hwc-commands | while read msg; do
  case "$msg" in
    "restart-jellyfin") systemctl restart jellyfin ;;
    "run-backup") systemctl start backup-local ;;
  esac
done
```

**Phone sends**:
```bash
# From Termux or automation app
ntfy pub hwc-commands "restart-jellyfin"
```

---

## Subscription Recommendations

### Phone Subscriptions
1. **hwc-critical** - Max priority, always alert
2. **hwc-alerts** - High priority
3. **hwc-backups** - Normal priority (audit trail)
4. **hwc-media** - Low priority (optional, for media fans)

### Laptop Subscriptions
- **hwc-critical** - Alert on server critical events
- **hwc-server-events** - Monitor all server activity

---

## Topic Summary Table

| Topic | Priority | Retention | Use Case | Phone Alert |
|-------|----------|-----------|----------|-------------|
| hwc-critical | 5 | 7d | System failures, security | Max, override DND |
| hwc-alerts | 4 | 3d | Warnings, service restarts | High |
| hwc-backups | 3 | 7d | Backup status | Normal |
| hwc-media | 2 | 2d | Media events | Low |
| hwc-monitoring | 2 | 1d | Health checks, stats | Low |
| hwc-updates | 1 | 3d | NixOS rebuilds, updates | Min |
| hwc-ai | 2 | 2d | AI workflow completions | Low |
| hwc-server-events | varies | 3d | All server events | Normal |
| hwc-laptop-events | varies | 3d | All laptop events | Normal |

---

## Implementation Priority

### Phase 1 (Immediate)
1. ✅ hwc-critical - Service failures, disk space
2. ✅ hwc-backups - Already integrated
3. ✅ hwc-alerts - Storage warnings, temp warnings

### Phase 2 (Soon)
4. hwc-media - Frigate person detection
5. hwc-updates - NixOS rebuild notifications
6. hwc-monitoring - Daily summaries

### Phase 3 (Later)
7. hwc-ai - AI workflow notifications
8. Bi-directional commands (phone → server)
9. Advanced automations

---

**Version**: 1.0
**Last Updated**: 2025-11-21
**Maintainer**: Eric
