# Business Domain

## Purpose
Heartwood Craft operations: lead pipeline, estimator, document management,
finance, business databases, website/CMS, and the daily morning briefing.

## Boundaries
- Manages: `hwc.business.*` services and their PostgreSQL schemas.
- Does NOT manage: workflow automation (n8n/MQTT → `domains/automation/`),
  AI inference (`domains/ai/`, `domains/server/native/ai/`), reverse-proxy
  routes (`domains/networking/routes.nix`).
- Enabled as a bundle by the business role (`profiles/business/sys.nix`,
  server-only).

## Structure
```
business/
├── index.nix          # Domain aggregator
├── databases/         # hwc.business.databases — business PostgreSQL layer
├── datax/             # hwc.business.datax — legacy postgres role/db (lead_scout)
├── datax-monitor/     # hwc.business.dataxMonitor — DX1 diagnostic dashboard on :4400
├── estimator/         # hwc.business.estimator — React PWA on :13443
├── firefly/           # hwc.business.firefly — Firefly III finance
├── leads/             # hwc.business.leads — unified lead pipeline
├── morning-briefing/  # hwc.business.morningBriefing — 6am Claude agent
├── paperless/         # hwc.business.paperless — Paperless-NGX documents
└── website/           # hwc.business.website — Heartwood CMS + 11ty + webapps
```

## Changelog
- 2026-06-29: `morning-briefing` rewritten to gather locally in bash instead of through a headless Claude+MCP pass (b2466860) and the `is-system-running` fallback no longer concatenates onto the previous value (4d2fc19e). Both were stability fixes for the 6am briefing.
- 2026-06-19: Moved `datax-monitor` checkout `~/projects/datax-monitor` →
  `~/600_apps/datax-monitor` to match every other app (lead-scout, todui, khalt,
  sr_analyzer…). Updated the `projectDir` default in `datax-monitor/index.nix`
  accordingly; nothing else references the old path. Zero-downtime on the server
  (moved + symlinked old path so the live service kept serving, rebuilt to
  repoint the unit, dropped the symlink).
- 2026-06-18: Added `datax-monitor` — standalone DX1 agent-execution diagnostic
  dashboard (`hwc.business.dataxMonitor`). Native out-of-store Node app at
  `~/600_apps/datax-monitor` (mirrors lead-scout): one Hono server on :4400
  serves the React SPA (`ui/dist`) + REST API; `datax-monitor-migrate` oneshot
  applies the schema before the API; `datax-monitor-ingest` oneshot + 4h timer
  pulls Firestore executions, classifies them, and writes the local
  `datax_monitor` Postgres DB. Caddy vhost `monitor.hwc.iheartwoodcraft.com`
  (one route line in `domains/networking/routes.nix`). Firebase creds via two
  new agenix secrets (`datax-monitor-fb-{email,key}`); OpenSearch enrichment
  reuses existing `opensearch-{host,user,pw}` (optional, degrades to null).
- 2026-06-11: README rewritten — this file previously contained the AI-MCP
  domain readme by mistake. Business enables now come from the business
  role rather than machines/server/config.nix.
