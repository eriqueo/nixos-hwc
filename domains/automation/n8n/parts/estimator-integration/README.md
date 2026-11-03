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
| `src/components/EstimateTab.jsx` | Same-origin push logic without browser credentials |
| `src/components/ScopeTab.jsx` | Includes JobSelector |

### Database

| File | Purpose |
|------|---------|
| `migrations/001-estimates-table.sql` | Postgres estimates table |

## Authentication

All webhook endpoints require `x-api-key` matching `ESTIMATOR_API_KEY` in n8n. Only the private estimator proxy receives the key from agenix and injects it at runtime. Public estimator webhook paths are blocked. The browser sends same-origin requests without credentials.

## Environment Variables

### N8N
- `ESTIMATOR_API_KEY` - Shared secret for webhook auth
- `SLACK_WEBHOOK_URL` - Slack incoming webhook
- `POSTGRES_REST_URL` - PostgREST endpoint (default: `http://127.0.0.1:3001`)

### Estimator App
- `VITE_WEBHOOK_URL` - Relative same-origin estimate-push path; no API key enters Vite.

## JobTread Custom Fields

- **Phase**: `22P4fguBu3Ub` - Jobs with phase 1-3 are estimating stages
- **Job Type**: `22P4fgU4XmLY` - bathroom, deck, kitchen, etc.

## Related Files

- Workflows: `/home/eric/.nixos/domains/automation/n8n/parts/workflows/`
- Estimator App: `/home/eric/.nixos/workspace/projects/react/heartwood-assembler/`
- Server Config: `/home/eric/.nixos/machines/server/config.nix`
