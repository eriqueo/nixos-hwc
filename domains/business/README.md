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
├── estimator/         # hwc.business.estimator — React PWA on :13443
├── firefly/           # hwc.business.firefly — Firefly III finance
├── leads/             # hwc.business.leads — unified lead pipeline
├── morning-briefing/  # hwc.business.morningBriefing — 6am Claude agent
├── paperless/         # hwc.business.paperless — Paperless-NGX documents
└── website/           # hwc.business.website — Heartwood CMS + 11ty + webapps
```

## Changelog
- 2026-06-16: Law-12 sweep also refreshed `datax/fb-group-scraper/`,
  `morning-briefing/`, `paperless/`, and `website/` sub-READMEs.
- 2026-06-16: `cc40b6a9` — land the golden-master parity oracle for
  `business/estimator` on main (precondition for the nightly-builds
  estimator refactor card; pre-existing parity tests were fake-green).
- 2026-06-11: README rewritten — this file previously contained the AI-MCP
  domain readme by mistake. Business enables now come from the business
  role rather than machines/server/config.nix.
