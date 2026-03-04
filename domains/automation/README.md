# domains/automation/ — Automation Domain

## Purpose

Workflow automation services. Currently contains n8n for alert routing,
webhook handling, and Slack notification integration.

## Boundaries

- Owns: n8n workflow automation
- Does NOT own: alert definitions (that's `domains/alerts/`), monitoring (that's `domains/monitoring/`)

## Structure

```
automation/
├── index.nix    # Domain aggregator
├── README.md    # This file
└── n8n/         # n8n workflow automation
    ├── index.nix
    ├── options.nix
    └── parts/
```

## Changelog

- 2026-03-04: Namespace migration hwc.server.native.n8n.* → hwc.automation.n8n.*
- 2026-03-04: Created automation domain; moved n8n from domains/server/native/ (Phase 6 of DDD migration)
