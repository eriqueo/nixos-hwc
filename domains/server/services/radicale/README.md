# Radicale — self-hosted CalDAV (tasks + calendars)

## Purpose
Self-hosted CalDAV server giving full two-way sync **including collection
creation**, for both VTODO (tasks) and VEVENT (calendars). It is the single
source of truth for both: the iCloud CalDAV paths were deleted from the client
modules on 2026-09-24. Radicale permits MKCALENDAR, so lists created in `todui`
(`N`) and calendars created in khalt are created server-side by vdirsyncer
discovery, and the iPhone reads/writes them through native CalDAV accounts. The
same service, vhost, and `radicale-htpasswd` secret serve both component types
— the VTODO pair (`domains/mail/tasks`) and the VEVENT pair
(`domains/mail/calendar`, `hwc.mail.calendar.radicale.*`) just differ by
`item_types`.

## Boundaries
- Manages: the Radicale service (localhost:5232), its htpasswd auth wiring,
  the read-only calendar mirrors, and the `tasks` Caddy vhost
  (tasks.hwc.iheartwoodcraft.com).
- Does NOT manage: the machines' vdirsyncer pairs (`domains/mail/tasks`,
  `domains/mail/calendar`), the todui TUI (`domains/home/apps/todui`), or
  the phone's CalDAV account (manual, see runbook).
- Storage: upstream default `/var/lib/radicale/collections` (StateDirectory).

## Structure
```
radicale/
├── index.nix         # Module: options hwc.server.services.radicale.*,
│                     #   services.radicale settings, secrets group, Caddy route
└── parts/
    └── mirrors.nix   # radicale-mirror timer: outside iCal feeds → read-only collections
```

## Secret
`domains/secrets/parts/services/radicale-htpasswd.age` — one line,
`eric:<password>` (htpasswd "plain" encryption; the file is age-encrypted at
rest and mounted 0440 root:secrets). The same secret serves both sides: the
server reads it as the htpasswd file; the laptop's vdirsyncer extracts the
password (`cut -d: -f2-`).

## Deploy runbook (in order)
1. **Create the secret** (laptop, in `~/.nixos`):
   `agenix -e domains/secrets/parts/services/radicale-htpasswd.age`
   → enter exactly one line: `eric:<password>` (pick the password; you'll
   type it into the iPhone too). Commit the .age file.
2. **Deploy the server**: on hwc-server, pull main and
   `sudo nixos-rebuild switch --flake .#hwc-server`. Check:
   `systemctl status radicale` and
   `curl -u eric:<password> https://tasks.hwc.iheartwoodcraft.com/eric/` (401 without auth = auth on).
3. **Enable a machine's pairs**: set `hwc.mail.calendar.enable` and
   `hwc.mail.tasks.enable` (the mail role sets both), run `hms`, then
   `yes | vdirsyncer discover`, `vdirsyncer sync`, and `vdirsyncer metasync`.
4. **Phone**: Settings → Apps → Reminders (or Calendar) → Accounts → Add
   Account → Other → Add CalDAV Account: server
   `tasks.hwc.iheartwoodcraft.com`, user `eric`, the password from step 1.
   (Phone reaches it over Tailscale.) Make this account the default for new
   events and reminders, and turn off iCloud Calendars and Reminders, so the
   phone does not show a second copy.
5. **Verify**: `todui` → `N` → new list → it appears on the server
   (`ls /var/lib/radicale/collections/collection-root/eric/`) and on the
   phone; add a task on the phone in that list → sync → visible in todui.

## Changelog
- 2026-09-24: Radicale is the only calendar + tasks backend on every machine
  (client-side iCloud paths deleted; see `domains/mail/calendar` and
  `domains/mail/tasks`). The retired `cal/migrated` collection (a 07-16 copy
  superseded by `eric/work|family|personal`) was moved out of the collection
  root to `/var/lib/radicale/archive/cal-migrated-2026-09-24`; delete after
  2026-10-24 if nothing needed it. Runbook step 3 and the phone step updated;
  Structure now lists `parts/mirrors.nix`.
- 2026-09-21: **Read-only mirrors of outside calendars** (`parts/mirrors.nix`,
  `hwc.server.services.radicale.mirrors`). A system timer (`radicale-mirror`,
  every 15 min, DynamicUser + `secrets` group) copies each secret iCal address
  (agenix) into its own collection under `/eric/` with vdirsyncer's `http`
  storage; `partial_sync = "revert"` undoes edits made on the Radicale side, so
  the mirror stays one-way. Live: `cto`, `proton-work`, `google-family` (the
  same three secrets the CRM's `busyFeeds` read). The phone's existing CalDAV
  account discovers them by itself; khal machines pin the ids in
  `hwc.mail.calendar.radicale.extraCollections` and run once
  `yes | vdirsyncer discover calendar_radicale && vdirsyncer sync calendar_radicale && vdirsyncer metasync calendar_radicale`
  (done on hwc-server 2026-09-21; the laptop after its next `hms`). Failure →
  `hwc-service-failure-notifier` (added to the alerts blessed list); vdirsyncer
  output is passed through a redactor that replaces every feed URL, because
  the notifier forwards journal lines. The vdirsyncer config, holding the URLs
  and the password, is written to RuntimeDirectory (tmpfs, 0700) and removed
  after each run. Feed quirks seen: the Microsoft (ContractorCTO) feed carries
  few UIDs, so vdirsyncer keys most items by content hash; DTSTAMP changes on
  every fetch and is ignored by the hash, so an unchanged feed uploads nothing.
- 2026-06-15: Now also hosts the **calendar** (VEVENT) backend, not just tasks.
  No server-side change required (Radicale is generic CalDAV) — the laptop adds
  a `calendar_radicale` vdirsyncer pair (`hwc.mail.calendar.radicale.enable`)
  and the server enables it headlessly so the MCP's `hwc_calendar` has data.
  See `domains/mail/calendar` (pair + one-time migration script) and
  `domains/home/apps/khalt`. README purpose/title updated to tasks + calendars.
- 2026-06-11: Initial. Radicale on localhost:5232 behind the `tasks` Caddy
  vhost; htpasswd auth from the shared agenix secret (plain encryption inside
  the encrypted file); SupplementaryGroups=secrets for the radicale user.
  Companion laptop pair added as hwc.mail.tasks.radicale (off until deployed).
