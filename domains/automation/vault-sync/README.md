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

# Laptop: timer-only too, as of 2026-08-20. The watcher is OFF on both hosts —
# see the Changelog. Enable it only where a HUMAN is the dominant write source.
hwc.automation.vaultSync.watch.enable = false;     # debounce 3s (watch.debounceSec)
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

- 2026-08-20: **Watcher disabled on hwc-laptop** (`watch.enable = false`); both hosts are
  now timer-only. The 3s debounce was correct when humans were the dominant write source;
  agents now are — 475 of 621 vault commits in the prior 30 days were
  `vault-sync: hwc-laptop auto-commit`, peaking at 125 in one day. An agent mid-edit
  produces incoherent intermediate states, and at 3s the watcher commits and pushes the
  half-state under a generic message (observed twice on 2026-08-20: four edits became two
  commits in the same minute). The existing flock serializes git-against-git — timer,
  watcher, brain-mcp — but an agent editing files is not a participant and holds nothing,
  so the lock never covered this. A new agent-scoped lock was rejected: it needs every
  write path as a participant, and its failure mode inverts to a SILENT sync stall, worse
  than a wrong commit message under R3. The 15-min timer is longer than most edit bursts
  and still provides the periodic pull. Re-enable only if the vault stops being
  agent-written, or alongside a lock with a timeout and a staleness surface.
- 2026-06-15: Created. Replaces Syncthing as the laptop↔server vault transport (Tier-2
  migration). Root-cause fix follow-on to the declarative `.stignore` work in
  domains/data/syncthing.
- 2026-06-15: Added optional event-driven `brain-vault-watch` service (`watch.enable`,
  `watch.debounceSec`) — pushes within seconds of any vault CRUD via a debounced `inotifywait`
  loop that runs the same sync script. Enabled on the laptop; server stays timer-only.
- 2026-07-22: Auto-commit message now interpolates `${config.networking.hostName}` instead of the
  hardcoded `server` literal, so hub history is attributable per clone. Requires a rebuild on each
  host to take effect (message is baked at build time).
