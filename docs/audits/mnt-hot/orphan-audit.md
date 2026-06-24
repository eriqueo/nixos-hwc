# `/mnt/hot` Orphan / Crust Audit — 2026-06-24

> **NOTHING WAS CHANGED.** This is a *report-only* audit. No file, directory,
> mount, or service was created, modified, moved, or deleted. Every proposal
> below is **human-gated**. Card 02 of the `mnt-hot-reconcile` goal explicitly
> forbids any mutation under `/mnt`. Treat this document as a worksheet for the
> next (gated) reconciliation card.

## How the active-paths set was derived

The active set was self-derived from the live nixos modules in `~/.nixos`,
filtered to those enabled on `hwc-server` (`config.hwc.server.enable = true` ⇒
`paths.nix` selects the server branch). No sibling card's output was consulted.

Commands:

```
rg '/mnt/hot' ~/.nixos --glob '!**/node_modules/**'
rg 'paths\.hot\.|hot\.downloads|hot\.surveillance|hot\.receipts|hot\.root|hotRoot|downloadsRoot' \
   ~/.nixos/domains --glob '**/*.nix'
```

Then each hit was traced back to the declaring module (paths primitive,
container, systemd-tmpfiles, watchDir, container volume mount) and verified to
be reachable on `hwc-server` via `machines/server/config.nix`.

### Active paths (declared & enabled on hwc-server)

| Path                                | Declaring module(s)                                                       |
| ----------------------------------- | ------------------------------------------------------------------------- |
| `/mnt/hot/`                         | `domains/paths/paths.nix` — `hwc.paths.hot.root`                          |
| `/mnt/hot/downloads/`               | `paths.nix` (auto-derived `hot.downloads`); mounted by sonarr / radarr / lidarr / readarr / qbittorrent / sabnzbd / slskd / books / calibre / soularr / downloaders |
| `/mnt/hot/downloads/incomplete/`    | `domains/data/storage/index.nix`; `_shared/directories.nix`               |
| `/mnt/hot/downloads/{tv,movies,music,books,scripts}/` | `_shared/directories.nix`; `domains/media/directories.nix`    |
| `/mnt/hot/events/`                  | qbittorrent & sabnzbd container volumes; `media/orchestration/media-orchestrator` |
| `/mnt/hot/processing/sonarr-temp/`  | `domains/data/storage/index.nix`                                          |
| `/mnt/hot/processing/radarr-temp/`  | `domains/data/storage/index.nix`                                          |
| `/mnt/hot/processing/lidarr-temp/`  | `domains/data/storage/index.nix`                                          |
| `/mnt/hot/processing/tdarr-temp/`   | `domains/media/tdarr/parts/config.nix`                                    |
| `/mnt/hot/processing/tdarr-backups/`| `domains/media/tdarr/parts/safety.nix`                                    |
| `/mnt/hot/surveillance/frigate/buffer/` | `machines/server/config.nix:701`; `domains/media/frigate`             |
| `/mnt/hot/inbox/`                   | `machines/server/config.nix:554` (`watchDirs`); `domains/ai/local-workflows` |
| `/mnt/hot/documents/{consume,export,staging}/` | `domains/business/paperless/index.nix`                         |
| `/mnt/hot/backups/{containers,databases,system}/` | `domains/data/backup/parts/server-backup-scripts.nix`          |
| `/mnt/hot/receipts/`                | `paths.nix` (auto-derived `hot.receipts`) — declared but no consumer found |

> Note: `hot.receipts` is a declared sub-path with no consumer in the current
> tree. It's listed as *active-by-declaration*; the next reconciliation card
> may demote it.

## Classification

Method: for each path *actually present* under `/mnt/hot`, classify as
**active** (is or sits under an entry in the active-paths table above) or
**orphan/legacy** (not declared, not consumed). For each, record media-file
count (extensions: `mkv mp4 avi m4v mov mp3 flac m4a opus epub pdf cbz jpg
png`), apparent size (`du -sh`), file count, last-mtime.

| Dir / subtree                                                                       | Class   | Has media | Size | Files   | Last mtime  | Note |
| ----------------------------------------------------------------------------------- | ------- | --------- | ---- | ------- | ----------- | ---- |
| `/mnt/hot/ai/`                                                                      | orphan  | no        | 2.2G | 14      | 2025-09-21  | Stale Ollama models + ssh keypair from pre-`/opt/ai` migration |
| `/mnt/hot/backups/`                                                                 | active  | no        | 132K | 6       | 2026-03-05  | Backup script root; mostly empty (`databases/`) + 2 PG dumps |
| `/mnt/hot/cache/`                                                                   | orphan  | no        | 48K  | 0       | 2026-04-06  | 6 empty subdirs: frigate, gpu, immich, jellyfin, qbittorrent, tensorrt |
| `/mnt/hot/documents/`                                                               | active  | no        | 8K   | 0       | 2026-06-20  | Paperless `consume/` exists; `export/` `staging/` not yet created |
| `/mnt/hot/downloads/`                                                               | active  | yes       | 192G | 728     | 2026-06-24  | See sub-breakdown below |
| `/mnt/hot/downloads/books/`                                                         | active  | yes       | 7.5G | 436     | —           | Active sonarr/readarr inbox |
| `/mnt/hot/downloads/complete/`                                                      | orphan  | no        | 4K   | 0       | —           | Empty; not in declared subtree (active is `incomplete/`, not `complete/`) |
| `/mnt/hot/downloads/movies/`                                                        | active  | yes       | 91G  | 42      | —           | Active radarr inbox |
| `/mnt/hot/downloads/music/`                                                         | active  | no        | 4K   | 0       | —           | Empty active dir |
| `/mnt/hot/downloads/readarr/`                                                       | active  | yes       | 2.2M | 1       | —           | Active readarr inbox |
| `/mnt/hot/downloads/scripts/`                                                       | active  | no        | 56K  | 4       | —           | media-orchestrator + qbt/sab hooks + audiobook-copier |
| `/mnt/hot/downloads/software/`                                                      | orphan  | no        | 33G  | 110     | —           | Not declared anywhere; Nintendo Switch firmware, .iso, etc. |
| `/mnt/hot/downloads/tv/`                                                            | active  | yes       | 58G  | 132     | —           | Active sonarr inbox |
| `/mnt/hot/downloads/www.UIndex.org    -    Melody Time 1948 1080p BluRay x264-MonteDiaz/` | orphan  | yes (1 mkv) | 3.0G | 3       | 2026-04-06  | Loose torrent dir at the wrong level; should be under `movies/` or imported |
| `/mnt/hot/events/`                                                                  | active  | no        | 24K  | 3       | 2026-02-21  | qbt.ndjson / sab.ndjson / slskd.ndjson event spools |
| `/mnt/hot/games/eXoDOS/`                                                            | orphan  | yes (rom-likes count as media — mp3/jpg/png cover art) | 35G  | 145,381 | bogus (2108-01-01 future mtime, eXoDOS archive artifact) | DOS games collection; no RetroPie/eXoDOS module declared |
| `/mnt/hot/library/`                                                                 | orphan  | yes       | 13G  | 145     | 2026-06-01  | Humble Bundle 2024 ebooks + `windows_isos/` |
| `/mnt/hot/processing/tdarr-{temp,backups}/`                                         | active  | no        | 12K  | 0       | 2026-06-20  | Tdarr scratch; sonarr/radarr/lidarr-temp not yet created |
| `/mnt/hot/surveillance/frigate/`                                                    | active  | no        | 12K  | 0       | 2026-04-07  | Frigate buffer dir (currently empty / not actively buffering) |
| `/mnt/hot/transcript-text/`                                                         | orphan  | no        | 4K   | 0       | 2026-04-08  | Empty; transcript output canonical is `/mnt/media/transcripts/` per `machines/server/config.nix:1005` |

### Totals

| Bucket                              | Size  |
| ----------------------------------- | ----- |
| Active subtrees                     | ~157G |
| Orphan / legacy subtrees            | ~86G  |
| **Reclaimable if all orphans go**   | **~86G** |
| Reclaimable from empty-only orphans | <1MB  |
| Reclaimable from "safe to delete"   | ~33G  (cache + transcript-text + downloads/complete + downloads/software + downloads/www.UIndex…) |
| Pending consolidation to `/mnt/media` (largest, most contentious) | ~50G (ai/models + games/eXoDOS + library/) |

## Proposal A — Consolidate to `/mnt/media` (HUMAN REVIEW)

These orphans contain media or media-adjacent content that probably belongs on
the cold tier. **Nothing here will be moved by this audit.** Each row needs a
human green-light.

| Source (`/mnt/hot/...`)                                                       | Bytes | Proposed destination                  | Rationale |
| ----------------------------------------------------------------------------- | ----- | ------------------------------------- | --------- |
| `library/Humble Bundle 2024 - Hacking, Math, Python/`                         | ~13G* | `/mnt/media/books/` (or a dedicated `learning/` subtree) | PDF/EPUB bundle, fits books taxonomy |
| `library/windows_isos/`                                                       | (part of 13G) | `/mnt/media/software/` **or** `/mnt/backup/isos/` | Not media; might prefer cold/backup tier |
| `games/eXoDOS/`                                                               | 35G   | `/mnt/media/retroarch/` *(NEW subtree)* **or** keep on hot if actively played | RetroArch ROMs canonical is `media.retroarch.roms` per `paths.nix`; eXoDOS may need its own bucket |
| `ai/models/` + `ai/.ollama/` + `ai/ollama/`                                   | 2.2G  | `/opt/ai/models/` (canonical AI root) | Pre-migration leftovers; verify `/opt/ai/models` already holds current data before moving |
| `downloads/www.UIndex.org    -    Melody Time 1948 1080p BluRay x264-MonteDiaz/Melody Time 1948 1080p BluRay x264-MonteDiaz.mkv` | 3.0G  | `/mnt/media/movies/Melody Time (1948)/` (or radarr import) | One-off torrent that escaped the radarr import path |

\* `library/` size of 13G is the whole directory; split between Humble Bundle
and `windows_isos/` not measured individually here to stay within budget.

## Proposal B — Safe to delete (HUMAN REVIEW)

These contain **no media** and either are empty or hold non-media cruft whose
origin is documented above.

| Path                                  | Bytes | Why it's safe |
| ------------------------------------- | ----- | ------------- |
| `/mnt/hot/cache/`                     | 48K   | 6 empty subdirs; no module declares any path under it |
| `/mnt/hot/transcript-text/`           | 4K    | Empty; canonical transcripts dir is `/mnt/media/transcripts` |
| `/mnt/hot/downloads/complete/`        | 4K    | Empty; active sibling is `incomplete/` (not `complete/`) |
| `/mnt/hot/downloads/software/`        | 33G   | Not declared; Switch firmware + .isos; archive to `/mnt/backup/software/` then delete, OR delete outright if Eric has the originals |
| `/mnt/hot/downloads/www.UIndex.org…/` (the `.nfo` + the `.txt`, after the `.mkv` is consolidated) | trivial | Torrent cruft |

Total reclaimable from "safe to delete" if all are removed: **~33G**.

## Other findings

1. **`hot.receipts` declared but unused** (`paths.nix:133` auto-derives
   `/mnt/hot/receipts`; no consumer found). Either wire it up (paperless?
   business?) or remove the option — a separate, gated card.
2. **`/mnt/hot/inbox/` is referenced by `local-workflows` and `machines/server/config.nix:554` (`watchDirs`) but does not exist on disk.** Whatever watches it currently watches a non-existent path silently; surface in the next card.
3. **`processing/sonarr-temp` / `radarr-temp` / `lidarr-temp` declared in `data/storage/index.nix` but do not exist on disk** — the systemd-tmpfiles rules should be creating them; investigate why they're absent.
4. **The `eXoDOS` mtime of `2108-01-01`** is an archive-artifact future date that breaks any `find -mtime` heuristic; flagged for the next card.
5. **`downloads/movies/` and `downloads/tv/`** hold 91G + 58G respectively — outside this audit's scope to classify file-by-file (active download landing zone, but lingering completed media should be promoted by sonarr/radarr to `/mnt/media`).

## Out of scope (explicitly not done)

- No file or directory was deleted, moved, renamed, or chmod'd.
- No nixos module was edited.
- No `nixos-rebuild`, `systemctl`, or any state-changing command was run.
- Sizes are `du -sh` apparent sizes; not space-on-disk after dedup/sparse.

## Next-card hooks

A follow-up card (card 03 or later in the `mnt-hot-reconcile` goal) should:

1. Take **Proposal A** row-by-row through Eric, then execute the moves with
   `rsync --remove-source-files` + dest-verify.
2. After A is complete, execute **Proposal B** with `rm -rfv` and a pre-emptive
   `du` snapshot for an auditable diff.
3. Wire or remove `hot.receipts`, fix `inbox/` missing, and investigate the
   missing `processing/*-temp/` tmpfiles entries.
