# domains/notifications/notify — hwc-notify

Hexagonal TypeScript notification dispatcher. **Phase 0 scaffold — not yet implemented.**

## Purpose

Replace the n8n `home:admin:alert-manager` workflow and the per-script CLI
senders (`hwc-gotify-send`, `hwc-webhook-send`, `hwc-smartd-notify`, etc.)
with one service that:

- exposes HTTP, CLI, and MCP shells over the same core
- runs outbound notifications through pluggable adapters (Discord, SMTP,
  later Gotify / Slack / iGotify)
- loads routing rules + channels from declarative Nix data
- enforces a Zod-validated `Notification` contract at every shell
- writes an audit row per delivery attempt
- trips per-channel circuit breakers and falls over to a secondary channel
  when one craters

## Why

Today's notification routing lives inside a 14-node n8n workflow whose
failures only surface as failed-execution rows nobody reads. On 2026-05-31
the workflow had been silently erroring for a full day because of a stale
`ntfy` URL. There is no schema validation, no circuit breaker, no audit
log of "what should have notified me today vs. what actually delivered."

See `~/.claude/plans/hashed-snacking-crab.md` for the full design.

## Namespace

`hwc.notifications.notify.*` (Charter Law 2 — namespace = folder).

## Structure

```
notify/
├── README.md          # This file
├── index.nix          # Charter Law 6 module (OPTIONS / IMPL / VALIDATION)
├── options.nix        # hwc.notifications.notify.* schema
├── parts/             # Phase 1: channels.nix, routes.nix (data-as-config)
└── src/               # Phase 1: TypeScript service (core / adapters / shells)
```

## Status

| Phase | State | What lands |
|-------|-------|------------|
| 0 | ✅ scaffolded | This module evaluates clean when disabled; enabling it asserts until Phase 1 lands. |
| 1 | ⬜ planned | TS core, Discord + SMTP adapters, HTTP/CLI/MCP shells, audit log, cutover from `alert-manager` workflow. |

## Changelog

- **2026-05-31**: Phase 0 scaffold. Module structure + enable option only; no implementation yet.
