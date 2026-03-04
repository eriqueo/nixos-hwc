# domains/monitoring/ — Monitoring Domain

## Purpose

Self-contained observability stack: Prometheus, Grafana, Alertmanager, cAdvisor, Exportarr.
Other domains register their scrape configs via `hwc.server.native.monitoring.prometheus.scrapeConfigs`.

## Boundaries

- Owns: metrics collection, dashboards, alerting
- Does NOT own: alert delivery (that's `domains/alerts/`), workflow automation (that's n8n in `domains/automation/`)
- External integrations: Immich, Frigate, and *arr containers push their scrape configs here

## Structure

```
monitoring/
├── index.nix           # Domain aggregator
├── README.md           # This file
├── options.nix         # Base toggle (hwc.server.native.monitoring.enable)
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
└── exportarr/          # *arr application metrics
    ├── index.nix
    └── options.nix
```

## Changelog

- 2026-03-04: Moved from domains/server/native/monitoring/ (Phase 4 of DDD migration)
