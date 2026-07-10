# domains/monitoring/ — Monitoring Domain

## Purpose

Self-contained observability stack: Prometheus, Grafana, Alertmanager, cAdvisor, Exportarr, Homepage dashboard, and Uptime Kuma.
Other domains register their scrape configs via `hwc.monitoring.prometheus.scrapeConfigs`.

## Boundaries

- Owns: metrics collection, dashboards, alerting, uptime monitoring, service dashboard, alert source detection
- Does NOT own: alert delivery (that's `domains/notifications/`), workflow automation (that's n8n in `domains/automation/`)
- External integrations: Immich, Frigate, and *arr containers push their scrape configs here

## Structure

```
monitoring/
├── index.nix           # Domain aggregator
├── README.md           # This file
├── options.nix         # Base toggle (hwc.monitoring.enable)
├── prometheus/         # Metrics collection + alert rules
│   ├── index.nix
│   ├── options.nix
│   └── parts/alerts.nix
├── grafana/            # Dashboards + visualization
│   ├── index.nix
│   ├── options.nix
│   └── dashboards/     # Pre-configured JSON dashboards
├── alertmanager/       # Alert routing to webhooks
│   ├── index.nix
│   └── options.nix
├── cadvisor/           # Container metrics
│   ├── index.nix
│   └── options.nix
├── exportarr/          # *arr application metrics
│   ├── index.nix
│   └── options.nix
├── homepage/           # Service dashboard (gethomepage)
│   ├── index.nix
│   └── parts/
│       ├── settings.yaml
│       ├── services.yaml
│       ├── widgets.yaml
│       ├── docker.yaml
│       └── bookmarks.yaml
├── uptime-kuma/        # Uptime monitoring
│   └── index.nix
└── alerts/             # Alert sources, thresholds, severity mapping
    └── index.nix
```

## Changelog
- 2026-07-09: Uptime Kuma auth disabled, declaratively — uptime-kuma.hwc.* is tailnet-only, so the login page added friction without security (the tailnet is the auth, like every other .hwc.* UI). Kuma has no env-var for this, so an ExecStartPre on podman-uptime-kuma upserts its `disableAuth` DB setting before each start (survives rebuilds/image updates/volume recreation; no-ops until Kuma's first boot creates kuma.db). The old wizard-set admin credential is no longer needed.
- 2026-07-07: Website + lead-pipeline monitoring — the blackbox exporter (enabled but previously probing nothing) gained three probe modules (CORS-preflight OPTIONS, unsigned-POST-expects-401, 200-or-401) and five probe jobs: public site pages/GEO artifacts, api.iheartwoodcraft.com webhook ingress, hwc-leads HMAC liveness, n8n /healthz, CMS API. New `website_alerts` rule group (P5: page down, webhook ingress down = leads being lost, leads service down, n8n down; P4: CMS down, cert expiry <14d; P3: slow responses). Alerts route via the existing alertmanager → hwc-notify receiver.
- 2026-07-06: Gotify decommission — dropped the stale gotify references from uptime-kuma header comments; the alertmanager `gotify-bridge` receiver was removed in profiles/monitoring/sys.nix (hwc-notify is now the sole receiver).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.

- 2026-07-05: Dropped the `transcript-api-health` blackbox scrape (guarded on `youtube.legacyApi.enable`, which was removed from domains/media — the option was never true, so the job never rendered).
- 2026-06-04: Retired the duplicate script-based disk alerter (`alerts/` `sources.diskSpace`); Prometheus is now the sole disk-alert owner. Salvaged its critical-on-data-volumes logic into `HighDiskUsage` (95% P5), which now matches `/|/mnt/.*` instead of root-only — so a full `/mnt/media` or `/mnt/hot` raises P5, not just P4.
- 2026-06-04: Raised `ModerateDiskUsage` threshold 75% → 82% (`prometheus/parts/alerts.nix`). Root `/` baselines ~77%, so the 75% P3 alert fired permanently and Alertmanager re-sent it to Discord every 4h (repeat_interval) with no actionable signal — the dominant disk-alert spam. 82% sits above baseline, below the Elevated (85%) tier.
- 2026-06-04: Raised `PersonaDaemonReindexStale` threshold 1h → 7h (`prometheus/parts/alerts.nix`). The daemon only reindexes on content change with a 6h backstop reconcile (`persona-daemon/index.nix`, `OnUnitActiveSec=6h`), so the old 1h threshold fired on every quiet-vault period — a guaranteed false positive. 7h = 6h backstop + 1h margin.
- 2026-04-04: Added alerts/ subdir — alert sources, thresholds, severity mapping (from domains/alerts redistribution)
- 2026-03-27: Fixed alertmanager routing — default receiver was empty (alerts silently dropped). Now uses child routes with `continue: true` to fan out to all configured webhook receivers. Added ntfy-bridge as second receiver alongside n8n-webhook.
- 2026-03-04: Namespace migration hwc.server.native.monitoring.* → hwc.monitoring.*
- 2026-03-04: Moved from domains/server/native/monitoring/ (Phase 4 of DDD migration)
- 2026-03-27: Added Homepage (gethomepage) service dashboard and Uptime Kuma uptime monitor
