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
├── crm/               # hwc.business.crm — front-of-funnel CRM
├── databases/         # hwc.business.databases — business PostgreSQL layer
├── datax/             # hwc.business.datax — legacy postgres role/db (lead_scout),
│                      #   plus fb-group-scraper / fb-classifier / fb-monitor-bak
├── datax-monitor/     # hwc.business.dataxMonitor — DX1 diagnostic dashboard on :4400
├── estimator/         # hwc.business.estimator — React PWA on :13443
├── firefly/           # hwc.business.firefly — Firefly III finance
├── leads/             # hwc.business.leads — unified lead pipeline
├── morning-briefing/  # hwc.business.morningBriefing — 6am Claude agent
├── paperless/         # hwc.business.paperless — Paperless-NGX documents
├── umami/             # hwc.business.umami — cookieless self-hosted web analytics
└── website/           # hwc.business.website — Heartwood CMS + 11ty + webapps
```

## Changelog
- 2026-08-17: Structure block corrected — `crm/` and `umami/` were both missing, though
  `umami/` has its own changelog entry here from 2026-07-07 and `crm/` from 2026-08-11.
- 2026-08-11: `bbd1efab` — a failed CRM migration now stops the boot (`set -euo pipefail`
  in `crm/index.nix`); it previously carried on with a half-migrated schema.
- 2026-08-11: leads — `70926e98` resolves the case **before** writing it (hwc-crm D33,
  P21 law 1; `store-postgres.ts` +148, `main.ts` +118, `ports/store.ts`), and
  `7b1508db` recasts `SaveResult` as a tagged union to close the replay gap.
- 2026-08-10: `b424c8c2` — morning-briefing injects the case-ledger delta as
  `sections.today.changes` (`gather-today.mjs` +18).
- 2026-08-06: Law 10 burn-down — `umami/parts/weekly-report.nix`'s option block (`enable`, `onCalendar`, `recipient`) moved into `umami/index.nix`; the part is implementation only. Law 10 names "mkOption anywhere else, including `parts/*.nix`" as the violation. Namespace `hwc.business.umami.weeklyReport.*` unchanged. Surfaced by the corrected charter-law10 check (v12.6).
- 2026-07-07: Website metrics reporting — morning-briefing gains a `website` section (umami visitors/pageviews 24h+7d, top pages, calculator-lead counts from hwc.calculator_leads) in briefing.json, the dashboard, and the daily email; new umami/parts/weekly-report.nix sends a Monday 07:00 week-over-week email (traffic deltas, top pages/referrers, lead detail) via msmtp from office@. Umami option websiteId added.
- 2026-07-07: New `umami/` module (hwc.business.umami) — cookieless self-hosted web analytics for iheartwoodcraft.com. Podman container (mkContainer, media-network) on loopback :3009, Postgres db `umami` (role created in postStart, trust auth over the 10.89.0.1 gateway), agenix `umami-env` (APP_SECRET + DATABASE_URL). Public collect endpoint via cloudflared at stats.iheartwoodcraft.com (proxied CNAME → tunnel).
- 2026-07-06: morning-briefing email sender switched eric@ → office@iheartwoodcraft.com (`-a proton-office`): self-sent mail gets Proton's sent+auto-archive treatment and never reaches the Inbox (found on the first live 06:00 run; SMTP had been 250-OK all along).
- 2026-07-06: Website evicted (audit 2.3): site_files (183 MB, CMS-mutated 11ty working tree) → own repo eriqueo/hwc-website, runtime clone at /opt/business/website-site; siteDir/mcp/web-build refs repointed. History purge (filter-repo) same change-set.
- 2026-07-06: morning-briefing: Step 5 email delivery added (briefing.json → plain-text render → msmtp proton-hwc → eric@iheartwoodcraft.com, best-effort); unit PATH gains msmtp/pass/gnupg. Audit 2.1: bash pipeline is now the SOLE briefing producer.
- 2026-07-06: paperless: declare consume/export/staging/media dirs via tmpfiles (bind-mount sources vanished from /mnt/hot → 1600-restart crash-loop). Pin firefly core v6.4.22 + pico 1.10.1 (Law 15 v12.4 critical tier).
- 2026-07-05: morning-briefing grows a `config_drift` section (audit Pattern 6): HEAD vs deployed rev (`system.configurationRevision` now recorded by flake glue), unpushed/dirty counts, booted-vs-current kernel (reboot pending), generation count, 24h coredump count — plus matching warning alerts. Machine-computed replacement for the generation-table misreadings that happened twice during the audit. `git` added to the unit PATH.
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
