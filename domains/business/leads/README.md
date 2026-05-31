# domains/business/leads — hwc-leads

Hexagonal TypeScript lead pipeline. **Phase 0 scaffold — not yet implemented.**

## Purpose

Collapse three independent lead-capture paths into one service:

- **Calculator** (`/webhook/calculator-lead` → 23-node n8n workflow)
- **Appointment** (`/webhook/calculator-appointment` → dead n8n workflow)
- **Contact form** (JT Web Form embed → direct to JobTread, no DB row, no notification)

…into a single `POST /leads` endpoint that:

- validates the inbound payload (HMAC + Zod) at the trust boundary
- creates the JobTread graph idempotently (account → location → contact → job)
- writes a canonical Lead row to `hwc.calculator_leads`
- emits a Notification to hwc-notify for the lead-pings channel
- sends a customer-facing confirmation email via hwc-notify's SMTP adapter
- generates a Report row tied to the Lead for the calculator's report viewer

## Why

The three paths today have three different validation regimes (i.e. none),
three different notification gaps (the contact form sends nothing at all),
and three different storage policies. There is no single "Lead" entity —
which means there is no single place to ask "did anything blow up while
handling that submission?"

See `~/.claude/plans/hashed-snacking-crab.md` for the full design.

## Namespace

`hwc.business.leads.*` (Charter Law 2 — namespace = folder).

## Structure

```
leads/
├── README.md          # This file
├── index.nix          # Charter Law 6 module (OPTIONS / IMPL / VALIDATION)
├── options.nix        # hwc.business.leads.* schema
├── parts/             # Phase 2: jt-mappings.nix (custom field IDs as data)
└── src/               # Phase 2: TypeScript service
    ├── core/          #   pure Lead / Project / Estimate types + rules
    ├── adapters/      #   JobTread, Postgres, Notify, Reports, ContactEmail
    ├── shells/        #   http, mcp, cli
    └── schemas/       #   Zod contracts at every boundary
```

## Status

| Phase | State | What lands |
|-------|-------|------------|
| 0 | ✅ scaffolded | This module evaluates clean when disabled; enabling it asserts until Phase 2 lands. |
| 2 | ⬜ planned | TS core, JT + Postgres + Notify adapters, HTTP/CLI/MCP shells, n8n workflows shrink to thin shells, contact form converts off JT embed. |

## Changelog

- **2026-05-31**: Phase 0 scaffold. Module structure + enable option only; no implementation yet.
