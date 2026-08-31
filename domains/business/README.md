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
├── datax-monitor/     # hwc.business.dataxMonitor — DX1 diagnostic dashboard on :4400
├── estimator/         # hwc.business.estimator — React PWA on :13443
├── firefly/           # hwc.business.firefly — Firefly III finance
├── leads/             # hwc.business.leads — unified lead pipeline
├── morning-briefing/  # hwc.business.morningBriefing — 6am Claude agent
├── paperless/         # hwc.business.paperless — Paperless-NGX documents
└── website/           # hwc.business.website — Heartwood CMS + 11ty + webapps
```

## Changelog
- 2026-08-29: morning-briefing rebuilt around the notifications CEO information
  contract (`dc0fce28`) — `gather-today.mjs`, `run.sh` and the dashboard now
  lead with what needs a decision. The email subject followed (`7f332a78`):
  it reads "N need you" from `sections.today.items` (capped at 5) and falls
  back to "N to watch" from the alert count, replacing the flat "N alert(s)".
  Detail in `morning-briefing/README.md`.
- 2026-08-28: **Postgres postStart purge reached this domain.** `databases`,
  `firefly` and `paperless` each carried `$PSQL` GRANT blocks that never ran —
  `$PSQL` is undefined in the generated post-start script and `|| true`
  swallowed the command-not-found (`e82ca994`). Deleted rather than repaired,
  because every grant targeted a role that already owned the objects. The
  follow-on (`53e84228`) declared `business_user` in `databases/index.nix` —
  `schema.sql` and `001-catalog-schema-split.sql` grant to it by name and
  nothing else in the repo mentions it, so it was the module's to claim. The
  rationale lives in `domains/data/databases/README.md`.
- 2026-08-28: Corrected the DataX-leftovers audit: `fb-group-scraper/node_modules` is a 15 MB ignored working-tree artifact, not checked-in content; the tracked scraper sources remain unreferenced.
- 2026-08-26: `datax/` module deleted — `hwc.business.datax` is gone. The module owned the postgres role + database that lead-scout connects to, and after `ALTER DATABASE datax RENAME TO lead_scout` (85b44464) its name named nothing it owned, which is a Law 2 break. The role + database declaration moved into `domains/server/native/ai/lead-scout/index.nix`, where home-scout and research-scout already keep theirs. Two behaviour changes went with the move, both verified against the live cluster first: `ensureDBOwnership = true` now aligns lead_scout's database owner with its role (every table in it was already owned by that role, so nothing moved), and the old module's six raw GRANTs plus its `fb-monitor-bak/schema.sql` apply were dropped as redundant and stale. The per-database backup registration was dropped, matching the other two scouts — `postgresql-db-backup` was retired wholesale the same day (85b60856), so a registration into it would have been dead config reading as a backup. lead_scout is covered by the borg pre-hook's nightly `pg_dumpall` into `/var/lib/backups`, which carries every database. The `datax/` directory still holds unreferenced 2026-05 scraper leftovers (`dashboard/`, `fb-classifier/`, `fb-group-scraper/`, `fb-monitor-bak/`); its 15 MB `node_modules` is ignored and untracked, not checked in. Removing these leftovers is a separate change.
- 2026-08-20: morning briefing reads `/var/lib/hwc/gluetun/*/status.json` and surfaces VPN tunnel state (`failed` → critical, `degraded` → warning, plus a stale-monitor warning if a check has not run in an hour). This is the second half of making the gluetun health check alert on transitions rather than state: transition-only alerting means a tunnel that degraded at 21:00 and is still down at 06:00 is deliberately silent overnight, and something has to hold that standing state. The briefing is where Eric actually looks, so it holds it — the same reasoning as the existing still-down vs auto-recovered split for service failures.
- 2026-08-20: paperless — migrated from the `/docs` subpath to a name-based vhost; see that module's README for the CSRF-origin coupling that makes this a three-setting change rather than a route flip.
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
