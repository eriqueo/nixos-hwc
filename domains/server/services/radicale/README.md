# Radicale — self-hosted CalDAV (tasks)

## Purpose
Self-hosted CalDAV server giving full two-way task sync **including list
creation**. iCloud pins the laptop's tasks pair to fixed collection IDs (lists
can only be created in Apple Reminders); Radicale permits MKCALENDAR, so lists
created in `todui` (`N`) are created server-side by vdirsyncer discovery, and
the iPhone reads/writes them through a native CalDAV account.

## Boundaries
- Manages: the Radicale service (localhost:5232), its htpasswd auth wiring,
  and the `tasks` Caddy vhost (tasks.hwc.iheartwoodcraft.com).
- Does NOT manage: the laptop's vdirsyncer pair (`domains/mail/tasks`,
  `hwc.mail.tasks.radicale.*`), the todui TUI (`domains/home/apps/todui`), or
  the phone's CalDAV account (manual, see runbook).
- Storage: upstream default `/var/lib/radicale/collections` (StateDirectory).

## Structure
```
radicale/
└── index.nix    # Module: options hwc.server.services.radicale.*,
                 #   services.radicale settings, secrets group, Caddy route
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
3. **Enable the laptop pair**: in `machines/laptop/home.nix` set
   `hwc.mail.tasks.radicale.enable = true`, run `hms`, then
   `vdirsyncer discover tasks_radicale` (answer y) and
   `vdirsyncer sync tasks_radicale`.
4. **Phone**: Settings → Apps → Reminders (or Calendar) → Accounts → Add
   Account → Other → Add CalDAV Account: server
   `tasks.hwc.iheartwoodcraft.com`, user `eric`, the password from step 1.
   (Phone reaches it over Tailscale.)
5. **Verify**: `todui` → `N` → new list → it appears on the server
   (`ls /var/lib/radicale/collections/collection-root/eric/`) and on the
   phone; add a task on the phone in that list → sync → visible in todui.

## Changelog
- 2026-06-11: Initial. Radicale on localhost:5232 behind the `tasks` Caddy
  vhost; htpasswd auth from the shared agenix secret (plain encryption inside
  the encrypted file); SupplementaryGroups=secrets for the radicale user.
  Companion laptop pair added as hwc.mail.tasks.radicale (off until deployed).
