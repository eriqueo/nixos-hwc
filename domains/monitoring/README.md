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

- 2026-04-04: Added alerts/ subdir — alert sources, thresholds, severity mapping (from domains/alerts redistribution)
- 2026-03-27: Fixed alertmanager routing — default receiver was empty (alerts silently dropped). Now uses child routes with `continue: true` to fan out to all configured webhook receivers. Added ntfy-bridge as second receiver alongside n8n-webhook.
- 2026-03-04: Namespace migration hwc.server.native.monitoring.* → hwc.monitoring.*
- 2026-03-04: Moved from domains/server/native/monitoring/ (Phase 4 of DDD migration)
- 2026-03-27: Added Homepage (gethomepage) service dashboard and Uptime Kuma uptime monitor
