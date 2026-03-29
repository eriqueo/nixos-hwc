# domains/automation/ — Automation Domain

## Purpose

Workflow automation services. Contains n8n for alert routing,
webhook handling, and Slack notification integration. Gotify CLI tool
for cross-machine push notifications.

## Boundaries

- Owns: n8n workflow automation, gotify CLI (`hwc-gotify-send`), MQTT broker
- Does NOT own: alert definitions (that's `domains/alerts/`), monitoring (that's `domains/monitoring/`)

## Structure

```
automation/
├── index.nix    # Domain aggregator
├── README.md    # This file
├── mqtt/        # MQTT broker for event-driven automation
│   └── index.nix
├── gotify/      # Gotify notification CLI (hwc-gotify-send)
│   └── index.nix
└── n8n/         # n8n workflow automation
    ├── index.nix # Options + Tailscale funnel services
    ├── sys.nix   # Container definition via mkContainer
    └── parts/
        ├── migrations/  # SQL migrations for workflow data
        └── workflows/   # JSON workflow definitions + docs
```

### Workspace Support (`workspace/automation/`)

```
workspace/automation/
├── hooks/                    # Event-driven scripts
│   ├── audiobook-copier.py   # Audiobook download handler
│   ├── media-orchestrator.py # Media pipeline orchestrator
│   ├── qbt-finished.sh       # qBittorrent completion hook
│   ├── sab-finished.py       # SABnzbd completion hook
│   └── slskd-verify.sh       # SLSKD verification
└── n8n-mcp-wrapper.sh        # MCP wrapper for n8n
```

## Changelog
- 2026-03-29: Migrated from ntfy to gotify — replaced ntfy/ directory with gotify/, new CLI tool hwc-gotify-send with JSON API + per-app tokens
- 2026-03-26: Add work_calculator_lead n8n workflow (Heartwood MCP /call → JT + Postgres + Slack); migration 002-calculator-leads.sql
- 2026-03-24: Added work_calculator_lead workflow (ID: SoLwmxgkMILrOYbP) - full JobTread integration for bathroom calculator leads
- 2026-03-18: Add MQTT integration for n8n, allowing detection events to be forwarded via webhook
- 2026-03-15: Add Tailscale Funnel service to expose n8n on port 10000, providing full access for external automation tools.

- 2026-03-15: Changed port 10000 funnel to full n8n access (was webhook-only)
- 2026-03-04: Namespace migration hwc.server.native.n8n.* → hwc.automation.n8n.*
- 2026-03-04: Created automation domain; moved n8n from domains/server/native/ (Phase 6 of DDD migration)
