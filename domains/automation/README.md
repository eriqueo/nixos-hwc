# domains/automation/ — Automation Domain

## Purpose

Workflow engine and event bus. Contains n8n for workflow orchestration,
MQTT broker for event-driven automation (Frigate → n8n), and the nightly-builds
runner that executes brain-vault gauntlet cards unattended overnight.

## Boundaries

- Owns: n8n workflow automation, MQTT broker, nightly gauntlet-card runner
- Does NOT own: notification delivery (`domains/notifications/`), alert definitions (`domains/monitoring/alerts/`)

## Structure

```
automation/
├── index.nix    # Domain aggregator
├── README.md    # This file
├── mqtt/        # MQTT broker for event-driven automation
│   └── index.nix
├── nightly-builds/  # Overnight gauntlet-card runner (headless Claude Code)
│   ├── index.nix    # Options + systemd service/timer (hwc.automation.nightlyBuilds.*)
│   ├── run.sh       # Launcher: card-smith pass + queued-card execution in git worktrees
│   └── prompts/
│       ├── run-wrapper.md  # Standing rules wrapped around every card
│       └── card-smith.md   # Drafts gated cards from _ideas.md one-liners
└── n8n/         # n8n workflow automation
    ├── index.nix     # Options + firewall rules
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
- 2026-06-12: nightly-builds hardening from 4-night sandbox rehearsal — agents must end output with `NIGHTLY-VERDICT: success|failure` and the launcher only marks a card `done` on a parsed success (a clean stop on an unsatisfiable card previously looked identical to success); card-smith receives the target repo path via launch context instead of a hardcoded `~/.nixos`.
- 2026-06-12: Add `nightly-builds/` — systemd timer (01:30) on the server role runs headless Claude Code against `status: queued` cards in the brain vault's `_inbox/nightly_builds/`; each card executes in a disposable git worktree, pushes its branch to origin, and writes a self-verifying REPORT.md to vault `runs/`. Card-smith pre-pass drafts cards from `_ideas.md` (drafts only; human flips to queued).
- 2026-06-09: Law 9/10 — `n8n/mcp-bridge.nix` → `n8n/mcp-bridge/index.nix` (pure relocation).
- 2026-06-09: Law 3 sweep — `n8n/mcp-bridge.nix` derives its install dir from `hwc.paths.apps.root` instead of hardcoding `/opt/n8n-mcp`.
- 2026-05-22: Remove Tailscale Funnel from n8n — public access migrated to Cloudflare Tunnel (`n8n.heartwoodcraft.me`). Delete `funnel` options and `tailscale-funnel-n8n*` systemd services. Funnel was poisoning MagicDNS for tailnet clients (every Caddy port unreachable from laptop).
- 2026-04-04: Removed gotify/ — moved to `domains/notifications/send/gotify.nix` (domain redistribution)
- 2026-03-29: Migrated from ntfy to gotify — replaced ntfy/ directory with gotify/, new CLI tool hwc-gotify-send with JSON API + per-app tokens
- 2026-03-26: Add work_calculator_lead n8n workflow (Heartwood MCP /call → JT + Postgres + Slack); migration 002-calculator-leads.sql
- 2026-03-24: Added work_calculator_lead workflow (ID: SoLwmxgkMILrOYbP) - full JobTread integration for bathroom calculator leads
- 2026-03-18: Add MQTT integration for n8n, allowing detection events to be forwarded via webhook
- 2026-03-15: Add Tailscale Funnel service to expose n8n on port 10000, providing full access for external automation tools.

- 2026-03-15: Changed port 10000 funnel to full n8n access (was webhook-only)
- 2026-03-04: Namespace migration hwc.server.native.n8n.* → hwc.automation.n8n.*
- 2026-03-04: Created automation domain; moved n8n from domains/server/native/ (Phase 6 of DDD migration)
