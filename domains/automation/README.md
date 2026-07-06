# domains/automation/ — Automation Domain

## Purpose

Workflow engine and event bus. Contains n8n for workflow orchestration,
MQTT broker for event-driven automation (Frigate → n8n), the nightly-builds
runner that executes brain-vault gauntlet cards unattended overnight, and the
readme-freshness weekly Law-12 drift report.

## Boundaries

- Owns: n8n workflow automation, MQTT broker, nightly gauntlet-card runner, readme-freshness report
- Does NOT own: notification delivery (`domains/notifications/`), alert definitions (`domains/monitoring/alerts/`). These modules *emit* to `hwc-notify` (loopback) but do not implement delivery.

## Structure

```
automation/
├── index.nix    # Domain aggregator
├── README.md    # This file
├── inbox-janitor/  # Server-only timer draining ~/000_inbox/downloads (hwc.automation.inboxJanitor.*)
│   ├── index.nix   # Options + systemd oneshot service/timer (every 30m); dryRun default on
│   ├── janitor.py  # Engine: pure classify() core + I/O edges; reads ~/000_inbox/_inbox-routing.yaml
│   └── README.md   # Single-writer rationale + rollout
├── mqtt/        # MQTT broker for event-driven automation
│   └── index.nix
├── nightly-builds/  # Overnight gauntlet-card runner (headless Claude Code)
│   ├── index.nix    # Options + systemd service/timer (hwc.automation.nightlyBuilds.*);
│   │                #   passes NB_DISCORD_WEBHOOK_FILE (agenix discord-webhook-nightly-builds)
│   ├── run.sh       # Launcher: card-smith pass + queued-card execution in git worktrees
│   ├── send-report.sh  # Per-card Discord post: verdict header + Success-criteria + full
│   │                #   REPORT.md attached (one message). hwc-notify is the metadata fallback
│   └── prompts/
│       ├── run-wrapper.md  # Standing rules wrapped around every card
│       └── card-smith.md   # Drafts gated cards from _ideas.md one-liners
├── readme-freshness/  # Weekly Law-12 report + autonomous fix (hwc.automation.readmeFreshness.*)
│   ├── index.nix      # Options + systemd service/timer (Mon 09:00); autoFix opts
│   └── run.sh         # Stage 1: lint + POST summary. Stage 2 (autoFix): headless
│                      #   Claude runs the `readme-refresh` skill in a worktree, the
│                      #   launcher hard-verifies READMEs-only, pushes + opens a PR
├── sr-gauntlet/   # Daily DataX SR investigation schedule (hwc.automation.srGauntlet.*)
│   ├── index.nix  # systemd service/timer (06:30 daily) wrapping ~/700_datax/sr_gauntlet/run.sh
│   └── README.md  # Containment model + pointer to the pipeline repo
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
- 2026-07-06: n8n image pinned to 2.10.3 (Law 15 v12.4 critical tier: workflow DB).
- 2026-06-18: Add `inbox-janitor/` — server-only systemd timer (every 30 min) that drains
  loose files at the root of `~/000_inbox/downloads` per the declarative rule table
  `~/000_inbox/_inbox-routing.yaml`: datax stays resident, business/tech/personal drain to
  the home PARA dirs, secrets/junk quarantine, unmatched → `_review` (fail-loud). Single-writer
  (server-only + hostname guard in `janitor.py`) to avoid Syncthing conflict copies on the
  multi-writer inbox — same rationale as the brain vault hub. Ships `dryRun=true`; enabled in
  `machines/server/config.nix`. v1 = downloads lane only; screenshot/event naming-normalization
  is specced in the YAML for a later pass (events already normalized by hand).
- 2026-06-15: refinery board — **"▶ Run now" + persistent NIGHTLY⇄IMMEDIATE mode + no-purgatory controls**. Every nightly-build project now always shows an actionable queue control: a `blocked` next step renders as **⚠ force-queue (override)** instead of the old dead-end "no draft steps to queue" (root cause: `queueNextStep` only matched `draft`). New per-project **mode** (stored in `_goal.md` frontmatter, default `nightly`): IMMEDIATE means queuing a step kicks a targeted run at once; NIGHTLY waits for 01:30. New **▶ Run now** button runs only that project immediately. Mechanism (hexagonal — the hardened board can't run `run.sh` itself): the board writes a `<goal>` request file to `/var/lib/refinery/run-now` (`REFINERY_RUNNOW_SPOOL`, under its writable `StateDirectory`); a new `systemd.path` `nightly-builds-runnow` drains it via `run.sh NB_ONLY_GOAL=<goal>`. Endpoints `/card/run-now`, `/card/mode`; `/card/queue` auto-kicks in IMMEDIATE. Needs a rebuild (board bundle + the new units).
- 2026-06-15: nightly-builds `run.sh` — per-card agent timeout raised 3h → **5h** (`NB_CARD_TIMEOUT`, env-overridable) so a multi-phase card can finish in one run; added **targeted-run** support (`NB_ONLY_GOAL` env or `run.sh <goal>` arg) that executes ONLY one project's queued step and skips the card-smith pass. Both default-inert: unset `NB_ONLY_GOAL` is the normal nightly run. Consumed by the refinery board's "▶ Run now" / IMMEDIATE-mode triggers. `run.sh` itself runs from the repo working copy via `ExecStart` (no rebuild for run.sh edits) — but the unit's `TimeoutSec` was also raised 4h → **12h** so systemd doesn't kill a 5h card; that part needs a rebuild.
- 2026-06-13: nightly-builds Discord delivery rewritten to match sr_gauntlet — `send-report.sh` posts ONE rich message per card (verdict header + the report's Success-criteria block inline + the full `REPORT.md` attached, readable in Discord's file viewer) directly to the `discord-webhook-nightly-builds` webhook (`NB_DISCORD_WEBHOOK_FILE` from index.nix). The old terse hwc-notify blurb is now only the fallback when no report exists (hard failures). Failure runs with a partial REPORT.md now post it too.
- 2026-06-12: Add `sr-gauntlet/` — daily timer (06:30, 7d/wk, Persistent) launching the SR-investigation pipeline at `~/700_datax/sr_gauntlet` (its own repo): fetch open DataX SRs (SR2 phases new+engaged) from Firestore, one headless read-only Claude investigation per SR against origin/main worktrees of datax/jt-mcp with per-customer Firestore context pack + OpenSearch log access, REPORT.md per SR delivered to Eric's Discord webhook. No code changes, no customer replies — human reviews and applies. Enabled in `machines/server/config.nix` (host one-off: pipeline + creds exist only on hwc-server).
- 2026-06-12: readme-freshness gained an autonomous fix stage (`autoFix`, default on). When the weekly lint finds drift, a headless Claude agent runs the `readme-refresh` skill in a disposable worktree off origin/main, edits READMEs only, and commits; the launcher **hard-verifies the diff is READMEs-only** (blast radius enforced by the runner, not trusted to the agent), pushes the branch, and opens a PR via `gh`. PR review is the human gate — no gauntlet queue-flip. Added `gh`/`openssh`/`nodejs` to the unit path and a `fixTimeoutSec` budget.
- 2026-06-12: nightly-builds run results now POST to Discord via `hwc-notify` (new `discord-webhook-nightly-builds` secret + `discord-nightly-builds` channel + `topic=nightly-builds` route in `domains/notifications/`). `run.sh` gained a best-effort `notify()` helper (per-card verdict + card-smith summary); `curl` added to the unit path.
- 2026-06-12: Add `readme-freshness/` — weekly systemd timer (Mon 09:00, server role) runs `workspace/tools/readme-freshness.sh` and posts a Law-12 drift summary to the #nightly-builds Discord channel. Report-only; emits to `hwc-notify`, never edits a README.
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
