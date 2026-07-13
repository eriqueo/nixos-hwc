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
- 2026-07-13: Two big threads land. (1) **hwc-crm** — a front-of-funnel service on `hwc.business.leads` (`funnel_stage`): SMTP go-live via Proton Bridge, public web-form intake, appointment/availability booking wired to the website calculator ("Schedule a call" shows real slots), a lead_scout → funnel-board ingest timer with a multi-pipeline route table, and a board vhost renamed `hwc-crm` → `crm`. (2) **morning-briefing** matured from placeholder to real data + drill-down: HTML email with per-section deep links and email↔dashboard parity, an overnight-ops digest (pg backup status, mail delta, alert-fatigue pass), a `config_drift` section, a refinery-board section, and a **Today Queue** (`hwc_today` gateway tool + actionable TODAY panel). Plus a mail canonical-taxonomy registry with on-demand retriage, an alert-actionability pass (kill false-firing/noise), Uptime Kuma decommissioned in favor of Grafana service-health, and website-metrics fixes (live `hwc.leads` counts, umami v3 API shapes).
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
