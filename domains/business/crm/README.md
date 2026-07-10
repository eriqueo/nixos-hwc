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
└── index.nix      # hwc.business.crm.* options + service + tick timer + route.
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

Ingress: Caddy vhost `crm.hwc.iheartwoodcraft.com` (tailnet-private).

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
