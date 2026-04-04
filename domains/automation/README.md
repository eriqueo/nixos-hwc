# domains/automation/ — Automation Domain

## Purpose

Workflow engine and event bus. Contains n8n for workflow orchestration
and MQTT broker for event-driven automation (Frigate → n8n).

## Boundaries

- Owns: n8n workflow automation, MQTT broker
- Does NOT own: notification delivery (`domains/notifications/`), alert definitions (`domains/monitoring/alerts/`)

## Structure

```
automation/
├── index.nix    # Domain aggregator
├── README.md    # This file
├── mqtt/        # MQTT broker for event-driven automation
│   └── index.nix
└── n8n/         # n8n workflow automation
    ├── index.nix     # Options + Tailscale funnel services
    ├── sys.nix       # Container definition via mkContainer
    ├── mcp-bridge.nix # n8n-mcp HTTP bridge
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
- 2026-04-04: Removed gotify/ — moved to `domains/notifications/send/gotify.nix` (domain redistribution)
- 2026-03-29: Migrated from ntfy to gotify — replaced ntfy/ directory with gotify/, new CLI tool hwc-gotify-send with JSON API + per-app tokens
- 2026-03-26: Add work_calculator_lead n8n workflow (Heartwood MCP /call → JT + Postgres + Slack); migration 002-calculator-leads.sql
- 2026-03-24: Added work_calculator_lead workflow (ID: SoLwmxgkMILrOYbP) - full JobTread integration for bathroom calculator leads
- 2026-03-18: Add MQTT integration for n8n, allowing detection events to be forwarded via webhook
- 2026-03-15: Add Tailscale Funnel service to expose n8n on port 10000, providing full access for external automation tools.

- 2026-03-15: Changed port 10000 funnel to full n8n access (was webhook-only)
- 2026-03-04: Namespace migration hwc.server.native.n8n.* → hwc.automation.n8n.*
- 2026-03-04: Created automation domain; moved n8n from domains/server/native/ (Phase 6 of DDD migration)
