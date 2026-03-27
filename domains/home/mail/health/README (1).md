# Mail Health Monitoring

## Purpose

Monitors the full mail dependency chain and alerts when things break. Prevents silent multi-hour outages where GPG/pass/Bridge/mbsync failures go unnoticed because systemd timers keep re-triggering failures quietly.

## Boundaries

- **Owns**: Health check script, systemd timer, alert routing, state tracking
- **Depends on**: mail domain (accounts, bridge, mbsync, notmuch paths), `hwc-ntfy-send`
- **Does NOT touch**: Mail data, configs, or running services (read-only checks + GPG lock cleanup)

## What It Checks (dependency order)

| # | Check | What | Failure mode it catches |
|---|-------|------|------------------------|
| 1 | GPG keyboxd | Stale locks, zombie processes, agent responsiveness | Mar 25 incident root cause |
| 2 | pass | Can decrypt `email/proton/bridge` | GPG cascading failure |
| 3 | Proton Bridge | Service running, IMAP/SMTP ports, vault state | Bridge crash or degraded startup |
| 4 | mbsync | Sync state age, recent failure count in journal | Silent sync failures |
| 5 | Mail freshness | Newest inbox message age | Everything looks ok but mail isn't flowing |

## Auto-Remediation

When `autoRemediate = true` (default):

- Removes stale GPG lock files where the holding PID is dead
- Restarts gpg-agent if unresponsive

Reports remediations as Slack warnings so you know it happened.

## Alert Routing

| Condition | Channel | How |
|-----------|---------|-----|
| First failure | Slack | n8n webhook → `#infra-alerts` |
| Mail down 30+ min | Phone push | `hwc-ntfy-send` → ntfy topic |
| Auto-remediation | Slack | n8n webhook (informational) |
| Warning (freshness, etc.) | Slack | n8n webhook |

Cooldown prevents spam: same failure fingerprint won't re-alert within 60 minutes.

## Configuration

```nix
hwc.home.mail.health = {
  enable = true;
  ntfy.topic = "hwc-mail";                    # Uses hwc-ntfy-send (system ntfy config)
  webhook.url = "https://hwc.ocelot-wahoo.ts.net:10000/webhook/mail-health";
  syncMaxAgeMin = 30;
  freshnessHours = 6;
  alertCooldownMin = 60;
  autoRemediate = true;
  intervalMin = 5;
};
```

## n8n Webhook Setup

Create an n8n workflow at `/webhook/mail-health`:

1. **Trigger**: Webhook node (POST)
2. **Switch** on `severity`: `critical` vs `warning`
3. **Slack**: Post to `#infra-alerts` with emoji based on severity

Expected payload:
```json
{
  "severity": "warning",
  "host": "homeserver",
  "timestamp": "2026-03-26T14:30:00-06:00",
  "details": "• Bridge IMAP port 1143 not accepting connections"
}
```

## Manual Usage

```bash
# Run health check manually
~/.local/bin/mail-health-check

# Check timer status
systemctl --user status mail-health.timer

# View recent results
journalctl --user -u mail-health.service --since "1 hour ago"

# View state files
ls -la ~/.local/state/mail-health/
```

## What This Catches (Mar 25 Scenario)

```
T+0     check_gpg detects stale keyboxd lock (PID 3804, dead)
        → auto-removes lock, restarts agent
        → Slack: "Auto-remediated: Removed stale GPG lock"
        → Total downtime: 0

Without this module:
T+0     GPG lock stale, pass hangs
T+10m   mbsync fails silently, timer re-fires
T+24h   Eric notices he hasn't gotten email in a day
```

## Changelog

- 2026-03-26: Initial implementation
