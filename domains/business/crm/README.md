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
| `.emailTransport` | `file` | Flip to `smtp` (Proton Bridge) to go live. |
| `.smtp.passwordSecretRef` | `proton-bridge-password` | agenix. |
| `.jtGrantKeyRef` | `jobtread-grant-key` | Manual-lead JT create. |
| `.tick.enable` / `.tick.onCalendar` | true / hourly | Persistent timer. |
| `.leadscoutIngest.enable` | true | lead_scout → funnel board ingest timer. |
| `.leadscoutIngest.onCalendar` | `*:00/30` | Every 30 min, persistent. |
| `.leadscoutIngest.sinceDays` / `.profile` | 14 / `hwc_bozeman_v1` | Rescan window + classifier profile. |
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
