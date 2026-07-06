# Notifications Domain

## Purpose
Delivery infrastructure — how messages reach humans.

## Namespace

`hwc.notifications.*`

## Structure

```
notifications/
├── index.nix                    # Domain aggregator, webhook config, _internal exports
├── notify/                      # hwc-notify hexagonal dispatcher (Discord + SMTP)
├── send/
│   ├── slack-webhook.nix        # Webhook sender scripts (retry, fallback)
│   └── cli.nix                  # hwc-alert CLI tool
├── health.nix                   # Webhook endpoint health check timer
└── README.md
```

## Boundaries

**Owns:** All outbound notification delivery — hwc-notify dispatcher, webhook sending, CLI tools, health checks.

**Does NOT own:** Alert detection/thresholds (monitoring/alerts), workflow automation (automation/n8n).

## Key Options

| Option | Description |
|--------|-------------|
| `hwc.notifications.enable` | Enable notification delivery |
| `hwc.notifications.webhook.baseUrl` | n8n webhook base URL |
| `hwc.notifications.send.cli.enable` | Enable hwc-alert CLI |

## Changelog
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
