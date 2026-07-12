# Notifications Domain

## Purpose
Delivery infrastructure — how messages reach humans.

## Namespace

`hwc.notifications.*`

## Structure

```
notifications/
├── index.nix                    # Domain aggregator, send.cli options, _internal exports
├── canary.nix                   # delivery deadman probe (Discord + SMTP, daily timer)
├── notify/                      # hwc-notify hexagonal dispatcher (Discord + SMTP)
├── send/
│   ├── notify-scripts.nix       # smartd/service/backup notifiers → hwc-alert wrappers
│   └── cli.nix                  # hwc-alert CLI → :11600/notify
└── README.md
```

## Boundaries

**Owns:** All outbound notification delivery — hwc-notify dispatcher, webhook sending, CLI tools, health checks.

**Does NOT own:** Alert detection/thresholds (monitoring/alerts), workflow automation (automation/n8n).

## Key Options

| Option | Description |
|--------|-------------|
| `hwc.notifications.enable` | Enable notification delivery |
| `hwc.notifications.send.cli.enable` | Enable hwc-alert CLI |
| `hwc.notifications.canary.enable` | Enable the delivery deadman probe |
| `hwc.notifications.canary.interval` | Canary cadence (OnCalendar, default `daily`) |

## Changelog
- 2026-07-12: **Alert-actionability pass.** (1) `routes.nix` p1-fanout no longer includes `discord-hwc-leads` — ops criticals (service failures, mail-health) were paging the leads-only channel; P1 now goes to #hwc-alerts + email. (2) `send/notify-scripts.nix` service-failure notifier is outcome-aware: 30s grace, then `systemctl is-active` — a unit that self-healed (e.g. the gluetun self-heal's SIGKILL stop artifacts on qbittorrent/mousehole) sends a warning-level "crashed & auto-recovered" note instead of a P1 3-channel page; only still-down units page, and the critical body now leads with the act (`journalctl -u X`, `systemctl restart X`). (3) `from-alertmanager.ts` `severityToPriority` parses the Prometheus rules' inverted P-scale (P5=Critical/P4=Warning/P3=Info) — previously every alertmanager alert fell through to priority 3, erasing the tiers.
- 2026-07-11: canary — `User = lib.mkForce "eric"` per the native-services Architecture Law (was bare; no-op today, verified by before/after eval).
- 2026-07-08: logrotate fix — the 2026-07-07 `2775 root:users` log dir made logrotate refuse the whole `hwc-notifications` glob ("insecure permissions", unit exits 1 hourly = the briefing's "1 failed service(s)" alert). Added `su = "root users"` and `create = "0664 root users"` so rotation runs under the dir's actual ownership and recreated logs stay group-writable.
- 2026-07-07: Notification unification (Slack eradication). `send/cli.nix` `hwc-alert` now POSTs the native NotificationInput shape to `:11600/notify` (severity→priority, endpoint→source) instead of the n8n Slack webhook; `send/slack-webhook.nix` deleted. `send/notify-scripts.nix` replaces it — smartd/service-failure/backup notifiers are thin `hwc-alert` wrappers (same script names, so `monitoring/alerts` + `data/backup` callers are untouched). Deleted `health.nix` (n8n-webhook health timer — obsolete; hwc-notify has its own watchdog) and the `webhook.*` options + the n8n-required/baseUrl assertions. New `canary.nix`: a daily deadman probe that POSTs a synthetic notify routed to both Discord and SMTP and fails loud (non-zero unit + sentinel + wall) if any adapter doesn't deliver — closes the silent-drop gap the premortem flagged. Log dir → `2775 root:users` so interactive `hwc-alert` can write.
- 2026-07-06: hwc-notify robustness: Restart=always + StartLimitIntervalSec=0 (no failed-state lockout), liveness watchdog timer (5-min /health probe, double-check then restart — catches hangs Restart= can't see), --max-time on every CLI curl so callers can't hang.
- 2026-07-06: Gotify stack decommissioned per 2026-06-11 plan (server/igotify/bridge/send modules, secrets, alertmanager receiver, client configs). hwc-notify (Discord+SMTP) is the sole alert path.
- 2026-07-05: Law 12 burn-down — restructured headings to the required contract (`## Purpose` / `## Boundaries` / `## Structure`); content unchanged, headings renamed/split from the old Scope-&-Boundary/Layout form.
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.

- 2026-06-12: Added the `discord-nightly-builds` channel (`#nightly-builds`, secret `discord-webhook-nightly-builds`) and a `topic=nightly-builds` route in `notify/parts/`. The automation domain's nightly-builds runner and readme-freshness report POST here; channel + route stay Nix data, the webhook URL is an agenix secretRef.
- 2026-06-11: `gotify/server/` — token auto-discovery (agenix secrets named `gotify-{universe}-{domain}` → `tokens."universe:domain"`) moved from machines/server/config.nix into the `tokens` option default; still overridable per machine. All 5 toplevels byte-identical (proven no-op).
- 2026-06-09: Law 9/10 — `gotify/{igotify,bridge,server}.nix` and `send/gotify.nix` each converted to `<name>/index.nix` directory modules (pure relocation).
- 2026-06-09: Law 10 migration — inlined `notify/options.nix` into `notify/index.nix` (schema types moved into the index `let`).
- **2026-06-04**: Retired the legacy script-based disk-space alerter (`hwc-disk-space-check` in `send/slack-webhook.nix`, the `hwc-disk-space-monitor` timer, and the `sources.diskSpace` option). It routed through the deprecated n8n webhook path and duplicated the Prometheus disk alerts. Disk-space monitoring is now solely owned by Prometheus (`monitoring/prometheus/parts/alerts.nix`) → Alertmanager → `hwc-notify`. Its 95%-critical-on-data-volumes coverage was salvaged into `HighDiskUsage` before removal.
- **2026-05-31** (Phase 1 complete): `notify/` is in production. Replaces the broken n8n `home:admin:alert-manager` workflow. Alertmanager fans out to `hwc-notify` (Discord + SMTP) and `gotify-bridge` (iOS push, kept independent); n8n receiver removed, workflow deactivated. SQLite audit log, per-channel circuit breaker, `hwc-notify` CLI and `hwc_notify` MCP tool all live. Full design + ops in `notify/README.md`.
- **2026-05-31**: Added `notify/` subdomain — `hwc.notifications.notify.*` (Phase 0 scaffold).
- **2026-04-04**: Created from alerts + automation/gotify domain redistribution
