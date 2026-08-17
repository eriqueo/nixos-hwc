# Heartwood Estimator → JobTread Integration

## Overview

This integration connects the Heartwood Estimator PWA to JobTread, Postgres, and Slack via n8n webhooks.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        HEARTWOOD ESTIMATOR PWA                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Customer     │  │ Job          │  │ Scope/       │  │ Push         │ │
│  │ Dropdown     │  │ Dropdown     │  │ Details      │  │ Estimate     │ │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘  └──────┬───────┘ │
└─────────┼─────────────────┼────────────────────────────────────┼─────────┘
          │                 │                                    │
          ▼                 ▼                                    ▼
┌─────────────────┐  ┌─────────────────┐            ┌─────────────────────┐
│ GET /webhook/   │  │ GET /webhook/   │            │ POST /webhook/      │
│ jt-customers    │  │ jt-jobs         │            │ estimate-push       │
└────────┬────────┘  └────────┬────────┘            └──────────┬──────────┘
         │                    │                                 │
         ▼                    ▼                                 ▼
    ┌────────────────────────────┐              ┌────────────────────────┐
    │   N8N WORKFLOW 08A         │              │   N8N WORKFLOW 08B     │
    │   JT Data Provider         │              │   Estimate Router      │
    └────────────┬───────────────┘              └───────────┬────────────┘
                 │                               ┌──────────┼──────────┐
                 ▼                               ▼          ▼          ▼
          ┌──────────────┐                ┌──────────┐ ┌──────────┐ ┌──────────┐
          │   JobTread   │                │ JobTread │ │ Postgres │ │  Slack   │
          │   GraphQL    │                │ GraphQL  │ │ estimates│ │ #hwc-    │
          └──────────────┘                └──────────┘ └──────────┘ │ estimates│
                                                                    └──────────┘
```

## Components

### N8N Workflows

| File | Endpoint | Purpose |
|------|----------|---------|
| `08a-jt-data-provider.json` | GET `/webhook/jt-customers` | Fetch customers for dropdown |
| `08a-jt-data-provider.json` | GET `/webhook/jt-jobs?customerId=X` | Fetch jobs for customer |
| `08b-estimate-router.json` | POST `/webhook/estimate-push` | Push estimate to JT + archive |

### React Components

| File | Purpose |
|------|---------|
| `src/components/JobSelector.jsx` | Customer/job selection UI |
| `src/hooks/useProjectState.js` | State model with job fields |
| `src/components/EstimateTab.jsx` | Push logic with API key auth |
| `src/components/ScopeTab.jsx` | Includes JobSelector |

### Database

| File | Purpose |
|------|---------|
| `migrations/001-estimates-table.sql` | Postgres estimates table |

## Authentication

All webhook endpoints require `x-api-key` header matching `ESTIMATOR_API_KEY` env var in n8n.

## Environment Variables

### N8N
- `ESTIMATOR_API_KEY` - Shared secret for webhook auth
- `SLACK_WEBHOOK_URL` - Slack incoming webhook
- `POSTGRES_REST_URL` - PostgREST endpoint (default: `http://127.0.0.1:3001`)

### Estimator App
- `VITE_WEBHOOK_URL` - Full URL to estimate-push endpoint
- `VITE_API_KEY` - Same as ESTIMATOR_API_KEY

## JobTread Custom Fields

- **Phase**: `22P4fguBu3Ub` - Jobs with phase 1-3 are estimating stages
- **Job Type**: `22P4fgU4XmLY` - bathroom, deck, kitchen, etc.

## Related Files

- Workflows: `/home/eric/.nixos/domains/automation/n8n/parts/workflows/`
- Estimator App: `/home/eric/.nixos/workspace/projects/react/heartwood-assembler/`
- Server Config: `/home/eric/.nixos/machines/server/config.nix`

## Structure

Documentation only — this directory ships no Nix, SQL or workflow JSON.

```
estimator-integration/
├── CHANGELOG.md
├── NEXT-SESSION.md   # Working notes for the next session on this integration
└── README.md         # This file
```

## Changelog

- 2026-08-17: Added `## Structure` + this changelog (Law 12 backfill — the file had
  neither). Flagged the stale `SLACK_WEBHOOK_URL` reference: the option
  (`slackWebhookUrlFile`) and its env injection were removed from `n8n/sys.nix` on
  2026-07-07 (`fbd92674`), so the "Environment Variables → N8N" list above is one
  entry out of date. The `jt:estimate-push` workflow now POSTs the native shape to
  `http://127.0.0.1:11600/notify` instead of Slack.
- 2026-06-02: `56c1f6c8` — `NEXT-SESSION.md` swept for the server tailnet rename
  `hwc.ocelot-wahoo.ts.net` → `hwc-server.ocelot-wahoo.ts.net` (4 occurrences).
  Mechanical; no behaviour change.
