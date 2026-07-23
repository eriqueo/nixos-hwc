# domains/automation/vault-sync/

## Purpose

Git **commit + pull + push** of the brain vault against the bare hub repo
(`/var/lib/vault-backups/git/brain.git`, the vault's `origin` remote). This is
the heartbeat of the Tier-2 "git is the only vault sync" architecture. Runs both
on a periodic **timer** and — when `watch.enable` is set — on an **event-driven**
filesystem watcher that fires within seconds of any vault CRUD.

## Boundaries

- **Manages**: a systemd service+timer that syncs a vault clone with the hub, plus an
  optional event-driven watcher service that triggers the same sync on filesystem changes
- **Does NOT manage**: the bare hub repo itself (-> domains/data/borg / manual), Syncthing
  topology (-> domains/data/syncthing), the brain-mcp service (-> domains/server/native/ai/brain-mcp)

## Structure

```
domains/automation/vault-sync/
├── index.nix     # Module: hwc.automation.vaultSync.* (sync service + timer + watch service)
└── README.md
```

## Configuration

```nix
# Server: timer-only is fine (overnight automation + brain-mcp commit on their own).
hwc.automation.vaultSync.enable = true;            # every 15 min by default

# Laptop: add the event-driven watcher so interactive edits push in seconds.
hwc.automation.vaultSync.watch.enable = true;      # debounce 3s (watch.debounceSec)
```

## Design Decisions

- **Tier-2 context**: laptop + server are git clones of the bare hub; the phone is a
  receive-only Syncthing mirror fed by the server. Syncthing no longer carries the vault
  between laptop and server — this timer does, via git.
- **Event-driven `watch`**: a long-running `inotifywait` loop (`brain-vault-watch`) runs the
  **same** sync script within `watch.debounceSec` of any create/update/delete/move, so local
  edits reach the hub in seconds instead of up to a full timer interval. It invokes syncScript
  **directly** (not `systemctl start`), so it needs no privilege and takes the same flock. The
  watch excludes `.git/` (otherwise the sync's own commit would re-trigger it forever), the sync
  lock, and high-churn non-note state (Obsidian `workspace*`, `.stversions/`, `.trash/`). The
  **timer stays on** even with watch enabled: it provides the periodic *pull* (remote changes
  while the laptop is idle) and a backstop if the watcher dies.
- **Concurrency**: all git access is serialized through `flock` on `<vault>/.git/.sync.lock`.
  `brain-mcp` and the watcher take the **same** lock, so the timer, the watcher, and brain-mcp's
  checkpoint commits can never collide on `index.lock`.
- **Order**: commit local changes → `pull --no-rebase --autostash` → `push`. A merge that
  conflicts is aborted (not left half-applied) and retried next cycle.
- **Attributable commit messages**: the auto-commit message interpolates
  `${config.networking.hostName}` (`vault-sync: <host> auto-commit <ts>`) so hub history shows
  which clone authored each commit. Previously the literal was hardcoded `server`, so every
  laptop commit masqueraded as a server commit — hub history was useless for provenance and a
  recon misread it as a stalled laptop→hub transport. The string is metadata only; nothing routes
  on it.
- **`git add -A` is safe**: the raw-import dirs (`business/wiki/06-contractor`,
  `_library/04-transcripts`) are embedded repos and are skipped; per-device state
  (`.stignore`, `.obsidian/plugins/*/data.json`) is gitignored.

## Changelog

- 2026-06-15: Created. Replaces Syncthing as the laptop↔server vault transport (Tier-2
  migration). Root-cause fix follow-on to the declarative `.stignore` work in
  domains/data/syncthing.
- 2026-06-15: Added optional event-driven `brain-vault-watch` service (`watch.enable`,
  `watch.debounceSec`) — pushes within seconds of any vault CRUD via a debounced `inotifywait`
  loop that runs the same sync script. Enabled on the laptop; server stays timer-only.
- 2026-07-22: Auto-commit message now interpolates `${config.networking.hostName}` instead of the
  hardcoded `server` literal, so hub history is attributable per clone. Requires a rebuild on each
  host to take effect (message is baked at build time).
