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
    ├── index.nix # Options + Tailscale funnel services
    ├── sys.nix   # Container definition via mkContainer
    └── parts/
        └── workflows/  # JSON workflow definitions
```

## Changelog
- 2026-03-18: Add MQTT integration for n8n, allowing detection events to be forwarded via webhook
- 2026-03-15: Add Tailscale Funnel service to expose n8n on port 10000, providing full access for external automation tools.

- 2026-03-15: Changed port 10000 funnel to full n8n access (was webhook-only)
- 2026-03-04: Namespace migration hwc.server.native.n8n.* → hwc.automation.n8n.*
- 2026-03-04: Created automation domain; moved n8n from domains/server/native/ (Phase 6 of DDD migration)
