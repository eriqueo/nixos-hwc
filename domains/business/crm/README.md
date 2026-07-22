# domains/business/crm — hwc-crm

Front-of-funnel CRM layered on the shipped hwc-leads service. Funnel stages
with gated transitions over the canonical `hwc.leads` Postgres store,
follow-up sequences (file/SMTP transports), next-action surfacing, and a
funnel board UI. App repo: `~/600_apps/hwc-crm` (run-from-checkout,
lead-scout pattern).

**Ownership contract**: hwc-leads owns `hwc.leads.status` (intake pipeline);
hwc-crm owns `funnel_stage` + the CRM tables (`lead_events`,
`sequence_enrollments`, `email_log`, `crm_settings`). The migration is
additive-only + idempotent and runs as `ExecStartPre`.

**Safety gates** (all default-off): `emailTransport = "file"` renders to a
spool dir instead of sending; DB `crm_settings.sequences_enabled` defaults
false; go-live cutoff prevents retro-enrolling pre-existing leads; 30-day
hard guard on first-contact sends.

## Structure

```
crm/
├── README.md      # This file.
└── index.nix      # hwc.business.crm.* options + service + tick timer
                   #   + lead_scout ingest timer + route.
```

## NixOS options

| Option | Default | Notes |
|---|---|---|
| `hwc.business.crm.enable` | false | Enabled via profiles/business. |
| `.projectDir` | `/home/eric/600_apps/hwc-crm` | Live checkout. |
| `.port` | `11660` | Loopback (11600 notify, 11650 leads). |
| `.postgresDsn` | `postgresql:///hwc` | Socket peer auth as eric. |
| `.notifyUrl` | `http://127.0.0.1:11600` | hwc-notify base; web-form leads ping #hwc-leads. |
| `.emailTransport` | `file` | Flip to `smtp` (Proton Bridge) to go live. |
| `.smtp.passwordSecretRef` | `proton-bridge-password` | agenix. |
| `.jtGrantKeyRef` | `jobtread-grant-key` | Manual-lead JT create. |
| `.tick.enable` / `.tick.onCalendar` | true / hourly | Persistent timer. |
| `.leadscoutIngest.enable` | true | lead_scout → funnel board ingest timer. |
| `.leadscoutIngest.onCalendar` | `*:00/30` | Every 30 min, persistent. |
| `.leadscoutIngest.sinceDays` | 14 | Rescan window (skip pre-filter makes overlap free). |
| `.leadscoutIngest.routes` | job + network | Route table: profile→pipeline+source+tiers+emailPrefix (JSON env). |
| `.leadscoutIngest.dataxDsn` | `postgresql:///datax` | READ-ONLY by contract. |
| `.calendar.enable` | false | Write appointment events to Radicale. |
| `.calendar.caldavUrl` | loopback Radicale | CalDAV base URL. |
| `.calendar.user` | `cal` | Radicale user (pw from `radicale-htpasswd`). |
| `.calendar.collection` | `cal/migrated` | Collection PATH (displayname `hwc`). |
| `.calendar.organizerEmail` | — | ORGANIZER on the `.ics` invite. |

Ingress: Caddy vhost `crm.hwc.iheartwoodcraft.com` (tailnet-private) for the
board UI + admin API; public Cloudflare Tunnel exposes ONLY
`^/hooks/(contact|appointment|availability)`.

## Changelog
- **2026-07-22** — Web-form contact leads now ping #hwc-leads (Discord).
  Leads entering via `crm.iheartwoodcraft.com/hooks/contact` (the JobTread
  web-form-embed mirror) landed on the funnel board but never notified anyone
  — only hwc-leads' calculator/appointment captures pinged hwc-notify. The app
  (`~/600_apps/hwc-crm`) gained a `NotifyClient` adapter that POSTs a
  `topic="leads"` payload to hwc-notify on new (non-duplicate) contact leads,
  stamping `notify_sent_at` (NULL-guarded — no double-ping). New
  `.notifyUrl` option → `HWC_CRM_NOTIFY_URL` (default matches the Python
  fallback, so the ping was already live on service restart; the export just
  makes it declarative). A tick reconciliation sweep (`_notify_unannounced`,
  mirroring `_t0_retry`) backstops the inline ping — any lead with
  `notify_sent_at IS NULL` for a web-form source (contact/appointment) is
  announced on the next tick, so a crashed inline POST or a future
  forgotten insert path can't silently drop a lead again. The drip was never
  broken — both missed real leads were already enrolled in `contact_followup`.
- 2026-07-11: `projectDir` default derives from `hwc.paths.user.home` (`${paths.user.home}/600_apps/hwc-crm`, brainvec precedent) instead of a hardcoded `/home/eric` literal (Law 3 migration, value unchanged).

- **2026-07-10** — Initial module: hwc-crm service (Python/FastAPI from
  nixpkgs `python3.withPackages`, run-from-checkout), additive migration as
  ExecStartPre, hourly persistent tick timer, vhost route, agenix secrets
  (JT grant key; Proton Bridge password when smtp transport selected).
  Enabled in profiles/business. See app repo BUILD-NOTES.md / DECISIONS.md.
- **2026-07-10** — Deployed to hwc-server: service healthy, migration applied,
  smoke test passed. Go-live: `emailTransport = "smtp"` (Proton Bridge loopback)
  set in profiles/business; live sends still DB-gated by
  `hwc.crm_settings.sequences_enabled`.
- **2026-07-10** — Appointment flow: `hwc.business.crm.calendar.*` writes
  calculator "Request a call" appointments to the Radicale calendar (loopback,
  `cal/migrated`) with day-before + hour-before VALARMs → syncs to khal +
  iPhone, and emails the customer an `.ics` invite. The `cal` password is
  extracted from the shared `radicale-htpasswd` into `/run/hwc-crm/caldav-pw`
  by a root `ExecStartPre` (RuntimeDirectory). Public path widened to
  `/hooks/(contact|appointment)`.
- **2026-07-10** — Public intake surface completed: `/hooks/contact` (web-form
  mirror → CRM append), `/hooks/appointment` (appointment → CRM append +
  Radicale calendar event + customer `.ics` invite), and `GET /hooks/availability`
  (Calendly-style free/busy computed from the Radicale calendar: Mon–Fri 9–4 MT
  minus real conflicts, 30-min slots). The `calendar` collection's CalDAV
  displayname is `hwc` while its PATH stays `cal/migrated` — the availability
  query + event PUTs use the URL PATH, so they are unaffected by the displayname.
  `hwc.business.crm.calendar.*` options (enable/caldavUrl/user/collection/
  organizerEmail) write events on loopback; the `cal` password is extracted from
  the shared `radicale-htpasswd` into `/run/hwc-crm/caldav-pw`. Public ingress
  path is `^/hooks/(contact|appointment|availability)`.
- **2026-07-10** — Automated lead_scout funnel (app D22):
  `hwc-crm-leadscout-ingest` oneshot + 30-min persistent timer pulls hot/warm
  classified FB posts from datax (READ-ONLY) onto the funnel board. The app's
  `ingest()` pre-filters already-known posts (no `duplicate_submission` event
  spam under rescans); hot leads get `next_action_date = today`; payload now
  carries lead_scout's situation/angle/scores and the board renders a hot/warm
  badge. `OnFailure` → `hwc-service-failure-notifier@` (Discord via
  hwc-notify) so datax schema drift is loud, not a silent lead drought.
- **2026-07-10** — Multi-pipeline CRM (app D23): hwc-crm now hosts multiple
  funnels over one store — `job` (unchanged) + `network`
  (connect → conversation → meet → active/pass, ungated) — discriminated by
  `hwc.leads.pipeline` (app migration 002, applied by ExecStartPre). The
  single-profile `leadscoutIngest.profile` option became
  `leadscoutIngest.routes`: a data-driven route table (profile → pipeline +
  source + tier sets + placeholder-email prefix) rendered to
  `HWC_CRM_INGEST_ROUTES` JSON; one timer iterates all routes. Default
  routes: `hwc_bozeman_v1`→job (byte-identical to the pre-D23 behavior) and
  `hwc_network_v1`→network (`source=network_scrape`, never auto-emailed per
  D13). Board UI gained pipeline tabs; `crm_*` MCP tools gained `pipeline`
  params. Adding another funnel = app registry entry + CHECK migration +
  one route here.
