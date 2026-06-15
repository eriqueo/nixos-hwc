# domains/automation/vault-sync/

## Purpose

Periodic git **commit + pull + push** of the brain vault against the bare hub
repo (`/var/lib/vault-backups/git/brain.git`, the vault's `origin` remote). This
is the heartbeat of the Tier-2 "git is the only vault sync" architecture.

## Boundaries

- **Manages**: a systemd service+timer that syncs the server's vault clone with the hub
- **Does NOT manage**: the bare hub repo itself (-> domains/data/borg / manual), Syncthing
  topology (-> domains/data/syncthing), the brain-mcp service (-> domains/server/native/ai/brain-mcp)

## Structure

```
domains/automation/vault-sync/
├── index.nix     # Module: hwc.automation.vaultSync.* (service + timer)
└── README.md
```

## Configuration

```nix
# In machines/server/config.nix:
hwc.automation.vaultSync.enable = true;   # every 15 min by default
```

## Design Decisions

- **Tier-2 context**: laptop + server are git clones of the bare hub; the phone is a
  receive-only Syncthing mirror fed by the server. Syncthing no longer carries the vault
  between laptop and server — this timer does, via git.
- **Concurrency**: all git access is serialized through `flock` on `<vault>/.git/.sync.lock`.
  `brain-mcp` takes the **same** lock, so the timer and brain-mcp's checkpoint commits can
  never collide on `index.lock`.
- **Order**: commit local changes → `pull --no-rebase --autostash` → `push`. A merge that
  conflicts is aborted (not left half-applied) and retried next cycle.
- **`git add -A` is safe**: the raw-import dirs (`business/wiki/06-contractor`,
  `_library/04-transcripts`) are embedded repos and are skipped; per-device state
  (`.stignore`, `.obsidian/plugins/*/data.json`) is gitignored.

## Changelog

- 2026-06-15: Created. Replaces Syncthing as the laptop↔server vault transport (Tier-2
  migration). Root-cause fix follow-on to the declarative `.stignore` work in
  domains/data/syncthing.
