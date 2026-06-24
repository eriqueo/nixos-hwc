# /mnt/media inventory + classification

**Generated:** 2026-06-24
**Source of truth for:** /mnt/hot reconcile checks, media cleanup cards, future
`audit/media-*` work.

Classification rules:

- **managed** — at least one module under `domains/media/**` (or
  `domains/paths/paths.nix` media options) declares the path as a library root,
  category, mount, or tmpfiles rule.
- **staging** — funnel buffers: blackhole / downloads / incomplete pickups for
  the *arr stack and adjacent processors.
- **unknown** — no module references this path; candidate for cleanup or
  promotion to a declared library.

Sizes via `du -sh`, item counts via `find -maxdepth 1 -mindepth 1`. Total
`/mnt/media` footprint: **5.0T**.

## Top-level directories

| dir                    | class   | declaring module / path option                                                                                                | size  | items | note                                                                                                |
| ---------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------- | ----- | ----- | --------------------------------------------------------------------------------------------------- |
| backups                | unknown | —                                                                                                                             | 8.0K  | 1     | not referenced by any media module; only borg uses `/var/lib/backups`. Watch-list.                  |
| blackhole              | staging | —                                                                                                                             | 4.0K  | 0     | conventional *arr/qbittorrent blackhole dir; no module currently mounts it (empty).                 |
| books                  | managed | `paths.nix:496` `media.books`; `directories.nix:53` tmpfiles; `calibre`, `readarr`, `books`, `audiobookshelf`, `media-orchestrator/audiobook-copier` | 13G   | 3     | contains `ebooks/`, `audiobooks/`, `.audiobookshelf-metadata/` per tmpfiles.                        |
| courses                | unknown | —                                                                                                                             | 36G   | 6     | no module declares it. Watch-list.                                                                  |
| documents              | unknown | —                                                                                                                             | 32K   | 1     | no module declares it. Watch-list.                                                                  |
| downloads              | staging | —                                                                                                                             | 4.0K  | 0     | empty; canonical downloads root is `hwc.paths.hot.downloads` (`/mnt/hot/downloads`), not here.      |
| incomplete             | staging | —                                                                                                                             | 4.0K  | 0     | empty; canonical incomplete dir lives under `/mnt/hot/downloads/incomplete`.                        |
| movies                 | managed | `radarr/sys.nix:21`; `tdarr/parts/config.nix:81`                                                                               | 1.5T  | 305   | radarr library root.                                                                                |
| music                  | managed | `paths.nix:495` `media.music`; `lidarr/sys.nix:21`; `tdarr/parts/config.nix:83`; `navidrome-container/sys.nix:21`; `slskd/sys.nix:23`; `beets-container` | 71G   | 53    | lidarr/navidrome/beets share this root.                                                              |
| photos                 | managed | `paths.nix:57` `serverPhotos`; `immich-container/parts/config.nix:205,253` (bind-mounts `/external`, `/archive`)               | 198G  | 8     | immich library root.                                                                                |
| podcasts               | managed | `paths.nix:498` `media.podcasts`; `directories.nix:56` tmpfiles; `audiobookshelf/index.nix:47`                                 | 4.0K  | 0     | declared but empty.                                                                                 |
| prepper-disk-staging   | unknown | —                                                                                                                             | 124G  | 4     | no module declares it. Watch-list.                                                                  |
| retroarch              | managed | `paths.nix:500-501` `media.retroarch.{roms,system}`                                                                            | 165G  | 3     | declared in paths; gaming/webdav uses a *separate* sync dir under `/var/lib/hwc/retroarch`.         |
| software               | unknown | —                                                                                                                             | 14G   | 3     | no module declares it. Watch-list.                                                                  |
| surveillance           | managed | `frigate/index.nix:52` `mediaPath = "${media.root}/surveillance/frigate/media"`                                                | 592G  | 2     | frigate recordings root.                                                                            |
| transcripts            | managed | `paths.nix:499` derived via youtube; `youtube/index.nix:26` `outputDirectory = "${media.root}/transcripts"`                    | 1.6M  | 28    | pinchflat/youtube transcript output.                                                                |
| tv                     | managed | `sonarr/sys.nix:21`; `tdarr/parts/config.nix:81`                                                                               | 2.4T  | 44    | sonarr library root.                                                                                |
| youtube                | managed | `paths.nix:499` `media.youtube`; `pinchflat/sys.nix:20,31`                                                                     | 66G   | 2     | pinchflat download root.                                                                            |
| .Trash-1000            | unknown | —                                                                                                                             | 4.0K  | 0     | GNOME/Nautilus trash for uid 1000; not module-declared. Empty.                                      |

## Class counts

- **managed:** 10 — books, movies, music, photos, podcasts, retroarch, surveillance, transcripts, tv, youtube
- **staging:** 3 — blackhole, downloads, incomplete
- **unknown:** 6 — backups, courses, documents, prepper-disk-staging, software, .Trash-1000

Total dirs: 19. Total size: 5.0T.

## Unknown / legacy candidates (watch-list)

These directories have no module reference and should be triaged before the
/mnt/hot reconcile work expects them to be managed:

- `/mnt/media/backups` (8.0K) — empty placeholder; borg targets `/var/lib/backups`, not here.
- `/mnt/media/courses` (36G) — 6 items; classify as a library candidate (course content vault) or relocate.
- `/mnt/media/documents` (32K) — 1 item; almost certainly belongs in `~/01-documents/` or the brain vault.
- `/mnt/media/prepper-disk-staging` (124G) — 4 items; one-shot disk staging, candidate for cleanup once consumed.
- `/mnt/media/software` (14G) — 3 items; ISO/install media — promote to a declared `software`/`isos` library or move.
- `/mnt/media/.Trash-1000` — trash sink; can be emptied.

## Staging notes

- `blackhole`, `downloads`, `incomplete` under `/mnt/media` are vestigial: the
  canonical funnel for the *arr stack is under `/mnt/hot/downloads/{complete,
  incomplete}` per `directories.nix:30-38`. The empty `/mnt/media/{downloads,
  incomplete,blackhole}` dirs are safe-to-remove once confirmed unused by any
  hot-path workflow.

## How to refresh this report

```sh
# Top-level dirs + sizes + counts
for d in /mnt/media/*/; do
  name=$(basename "$d"); size=$(du -sh "$d" | cut -f1)
  count=$(find "$d" -maxdepth 1 -mindepth 1 | wc -l)
  printf '%s|%s|%s\n' "$name" "$size" "$count"
done

# Module path references
rg -n 'paths.media|/mnt/media' domains/media/ domains/paths/paths.nix
```
