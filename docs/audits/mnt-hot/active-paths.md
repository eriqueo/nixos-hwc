# /mnt/hot + /mnt/media — active-paths map (hwc-server)

Static read of the nixos modules on `audit/hot-funnel-map`, branched from
`origin/main` at 8c97d928. This is the canonical source of truth that cards
02/03 will re-derive against. A path absent from the ENABLED block below is a
deletion candidate; a path present is load-bearing.

**Methodology** — read-only. `rg -n '/mnt/(hot|media)|paths\.(hot|media)\.'`
across `domains/`, `machines/`, `profiles/`, then trace each declaration to the
machine root (`machines/server/config.nix`) and the imports it pulls in. No
`nix eval` / build was run. Enabled-on-hwc-server = the option that controls
the declaring module is set true (or `lib.mkDefault true` with no override) on
`hwc-server`. The hot/media roots themselves come from
`machines/server/config.nix:730-733`:

```nix
hwc.paths = {
  hot.root = "/mnt/hot";
  media.root = "/mnt/media";
};
```

`hwc.paths.hot.downloads`, `.surveillance`, `.receipts` and
`hwc.paths.media.{music,books,audiobooks,podcasts,youtube,retroarch.*}` are
auto-derived from those roots in `domains/paths/paths.nix:488-516`.

## Table

| path | mount | role | declaring module | enabled on hwc-server |
|---|---|---|---|---|
| `/mnt/hot` | `/mnt/hot` | mount root (SSD hot tier) | `domains/system/mounts/index.nix` (via `hwc.system.mounts.hot`); `domains/paths/paths.nix:55`; pinned in `machines/server/config.nix:731` | ✅ |
| `/mnt/hot/downloads` | `/mnt/hot` | download (auto-derived: `hwc.paths.hot.downloads`); shared volume mounted as `/downloads` into qbt, sabnzbd, sonarr, radarr, lidarr, readarr, books, calibre, soularr | `domains/paths/paths.nix:490`; bound in `domains/media/{qbittorrent,sabnzbd,sonarr,radarr,lidarr,readarr,books,calibre,soularr,downloaders/parts/downloaders}.nix` | ✅ (downloaders/parts/downloaders.nix is NOT enabled — `hwc.media.downloaders.enable` unset — same path bound by the per-service modules) |
| `/mnt/hot/downloads/incomplete` | `/mnt/hot` | download/incomplete (qbt + slskd staging; storage-cleanup target) | `domains/media/directories.nix:32`; `domains/media/slskd/sys.nix:21`; `domains/data/storage/index.nix:28` | ✅ |
| `/mnt/hot/downloads/complete` | `/mnt/hot` | download/complete | `domains/media/directories.nix:33` | ✅ |
| `/mnt/hot/downloads/tv` | `/mnt/hot` | category root | `domains/media/directories.nix:34` | ✅ |
| `/mnt/hot/downloads/movies` | `/mnt/hot` | category root | `domains/media/directories.nix:35` | ✅ |
| `/mnt/hot/downloads/music` | `/mnt/hot` | category root + slskd `/downloads/music` bind | `domains/media/directories.nix:36`; `domains/media/slskd/sys.nix:22`; `domains/media/beets-container/index.nix:44` (beets disabled) | ✅ |
| `/mnt/hot/downloads/scripts` | `/mnt/hot` | hook scripts mounted RO into qbt + sabnzbd (`/scripts`, `/config/scripts`); writer = media-orchestrator-install + audiobook-copier-install | `domains/media/directories.nix:37`; `domains/media/qbittorrent/parts/config.nix:71`; `domains/media/sabnzbd/parts/config.nix:146`; `domains/media/orchestration/audiobook-copier/index.nix:51-55` | ✅ |
| `/mnt/hot/downloads/books` | `/mnt/hot` | audiobook source (audiobook-copier `sourceDir`, media-orchestrator `SOURCE_DIR`) | `domains/media/orchestration/audiobook-copier/index.nix:25`; `domains/media/orchestration/media-orchestrator/index.nix:63` | ✅ (audiobook-copier enabled; media-orchestrator NOT enabled — `hwc.media.orchestration.mediaOrchestrator.enable` unset) |
| `/mnt/hot/events` | `/mnt/hot` | event spool (qbt + sabnzbd post-process hooks: `${paths.hot.root}/events:/mnt/hot/events`) | `domains/media/directories.nix:42`; `domains/media/qbittorrent/parts/config.nix:72`; `domains/media/sabnzbd/parts/config.nix:145`; writer in `domains/media/orchestration/media-orchestrator/index.nix:27` (orchestrator disabled, but tmpfile is unconditional) | ✅ |
| `/mnt/hot/processing` | `/mnt/hot` | processing umbrella | `domains/media/directories.nix:43` | ✅ |
| `/mnt/hot/processing/sonarr-temp` | `/mnt/hot` | cache/processing (cleanup target) | `domains/media/directories.nix:44`; `domains/data/storage/index.nix:25` | ✅ |
| `/mnt/hot/processing/radarr-temp` | `/mnt/hot` | cache/processing (cleanup target) | `domains/media/directories.nix:45`; `domains/data/storage/index.nix:26` | ✅ |
| `/mnt/hot/processing/lidarr-temp` | `/mnt/hot` | cache/processing (cleanup target) | `domains/media/directories.nix:46`; `domains/data/storage/index.nix:27` | ✅ |
| `/mnt/hot/processing/tdarr-temp` | `/mnt/hot` | cache/processing (tdarr `/temp` bind) | `domains/media/directories.nix:47`; `domains/media/tdarr/parts/config.nix:84,103` | ⚠️ tmpfile created unconditionally; consumer `hwc.media.tdarr.enable = false` (`machines/server/config.nix:877`) |
| `/mnt/hot/processing/tdarr-backups` | `/mnt/hot` | cache/processing | `domains/media/directories.nix:48` | ⚠️ tmpfile created unconditionally; tdarr disabled |
| `/mnt/hot/surveillance` | `/mnt/hot` | surveillance buffer root (auto-derived: `hwc.paths.hot.surveillance`) | `domains/paths/paths.nix:491` | ✅ |
| `/mnt/hot/surveillance/frigate/buffer` | `/mnt/hot` | cache (Frigate ring buffer) | `domains/media/frigate/index.nix:53`; pinned in `machines/server/config.nix:690` | ✅ |
| `/mnt/hot/receipts` | `/mnt/hot` | receipts staging (auto-derived: `hwc.paths.hot.receipts`) | `domains/paths/paths.nix:492` | ⚠️ derived but no enabled consumer references it (latent) |
| `/mnt/hot/inbox` | `/mnt/hot` | watch dir (AI file-cleanup agent + local-workflows watchDirs default) | `machines/server/config.nix:543` (`hwc.ai.local-workflows.fileCleanup.watchDirs`); `domains/ai/local-workflows/index.nix:41` | ✅ |
| `/mnt/hot/documents/consume` | `/mnt/hot` | watch dir (Paperless consume) | `domains/business/paperless/index.nix:72` | ✅ (paperless enabled via business role) |
| `/mnt/hot/documents/export` | `/mnt/hot` | export dir (Paperless) | `domains/business/paperless/index.nix:78` | ✅ |
| `/mnt/hot/documents/staging` | `/mnt/hot` | staging dir (Paperless pre-processing) | `domains/business/paperless/index.nix:84` | ✅ |
| `/mnt/hot/backups/containers` | `/mnt/hot` | backup dest (rsync container backup) | `domains/data/backup/parts/server-backup-scripts.nix:12,224-227` | ❌ disabled: `hwc.data.backup.enable = false` (`machines/server/config.nix:389`); primary backup is Borg to `/mnt/backup/borg-hwc-server` |
| `/mnt/hot/backups/databases` | `/mnt/hot` | backup dest | same | ❌ disabled (same) |
| `/mnt/hot/backups/system` | `/mnt/hot` | backup dest | same | ❌ disabled (same) |
| `/mnt/media` | `/mnt/media` | mount root (HDD media tier) | `fileSystems."/mnt/media"` in `machines/server/config.nix:166-169`; `domains/paths/paths.nix:56`; pinned in `machines/server/config.nix:732` | ✅ |
| `/mnt/media/tv` | `/mnt/media` | library (sonarr `/tv` bind) | `domains/media/sonarr/sys.nix:21`; `domains/media/tdarr/parts/config.nix:81` (tdarr disabled) | ✅ |
| `/mnt/media/movies` | `/mnt/media` | library (radarr `/movies` bind) | `domains/media/radarr/sys.nix:21`; tdarr (disabled) | ✅ |
| `/mnt/media/music` | `/mnt/media` | library (auto-derived `hwc.paths.media.music`; lidarr RW, slskd RO, navidrome RO; tdarr disabled) | `domains/paths/paths.nix:495`; `domains/media/lidarr/sys.nix:21`; `domains/media/slskd/sys.nix:23`; `domains/media/navidrome-container/sys.nix:21` | ✅ |
| `/mnt/media/books` | `/mnt/media` | library (auto-derived `hwc.paths.media.books`; readarr `/books` bind, books container, calibre library default) | `domains/paths/paths.nix:496`; `domains/media/readarr/sys.nix:21`; `domains/media/books/sys.nix:22`; `domains/media/calibre/index.nix:20`; `domains/media/audiobookshelf/index.nix:53` | ✅ |
| `/mnt/media/books/ebooks` | `/mnt/media` | library subdir (calibre library default) | `domains/media/directories.nix:53`; `domains/media/calibre/index.nix:20` | ✅ |
| `/mnt/media/books/audiobooks` | `/mnt/media` | library subdir (auto-derived `hwc.paths.media.audiobooks`; audiobook-copier `destDir`; audiobookshelf books default) | `domains/paths/paths.nix:497`; `domains/media/directories.nix:54`; `domains/media/orchestration/audiobook-copier/index.nix:26`; `domains/media/orchestration/media-orchestrator/index.nix:64` | ✅ |
| `/mnt/media/books/.audiobookshelf-metadata` | `/mnt/media` | metadata (audiobookshelf) | `domains/media/directories.nix:55`; `domains/media/audiobookshelf/index.nix:53` | ✅ |
| `/mnt/media/podcasts` | `/mnt/media` | library (auto-derived `hwc.paths.media.podcasts`; audiobookshelf) | `domains/paths/paths.nix:498`; `domains/media/directories.nix:56`; `domains/media/audiobookshelf/index.nix:47` | ✅ |
| `/mnt/media/youtube` | `/mnt/media` | library (auto-derived `hwc.paths.media.youtube`; pinchflat `/downloads` bind) | `domains/paths/paths.nix:499`; `domains/media/pinchflat/sys.nix:20,31` | ✅ |
| `/mnt/media/transcripts` | `/mnt/media` | output dir (YouTube transcripts API) | `machines/server/config.nix:994`; `domains/media/youtube/index.nix:26` | ✅ |
| `/mnt/media/photos` | `/mnt/media` | photos root (`hwc.paths.photos` default for server; Immich; Borg-included) | `domains/paths/paths.nix:57`; `machines/server/config.nix:399` | ✅ |
| `/mnt/media/photos/immich` | `/mnt/media` | volume root (Immich `mediaLocation`/`storage.basePath`) | `machines/server/config.nix:956,960` | ✅ |
| `/mnt/media/photos/immich/library` | `/mnt/media` | volume (Immich originals) | `machines/server/config.nix:962` | ✅ |
| `/mnt/media/photos/immich/thumbs` | `/mnt/media` | cache (Immich thumbs; Borg-excluded) | `machines/server/config.nix:963,412` | ✅ |
| `/mnt/media/photos/immich/encoded-video` | `/mnt/media` | cache (Immich transcoded video; Borg-excluded) | `machines/server/config.nix:964,413` | ✅ |
| `/mnt/media/photos/immich/profile` | `/mnt/media` | volume (Immich profile pics) | `machines/server/config.nix:965` | ✅ |
| `/mnt/media/photos/external` | `/mnt/media` | volume (Immich RO external-library bind) | `domains/media/immich-container/parts/config.nix:205,253` | ✅ |
| `/mnt/media/photos/archive` | `/mnt/media` | volume (Immich RO archive bind) | `domains/media/immich-container/parts/config.nix:206` | ✅ |
| `/mnt/media/surveillance/frigate/media` | `/mnt/media` | volume (Frigate recordings) | `domains/media/frigate/index.nix:52`; `machines/server/config.nix:689` | ✅ |
| `/mnt/media/quarantine` | `/mnt/media` | beets quarantine bind | `domains/media/beets-container/sys.nix:20` | ❌ disabled: `hwc.media.beets.enable = false` (`machines/server/config.nix:869`) |
| `/mnt/media/retroarch/roms` | `/mnt/media` | library (auto-derived `hwc.paths.media.retroarch.roms`) | `domains/paths/paths.nix:500`; `domains/gaming/retroarch/index.nix:33` | ✅ (retroarch enabled) |
| `/mnt/media/retroarch/system` | `/mnt/media` | library (auto-derived `hwc.paths.media.retroarch.system`; BIOS) | `domains/paths/paths.nix:501`; `domains/gaming/retroarch/index.nix:39` | ✅ |
| `/mnt/media/documents/paperless` | `/mnt/media` | archive (Paperless originals/archive/thumbnails) | `domains/business/paperless/index.nix:90` | ✅ |

## ENABLED `/mnt/hot` paths (machine-readable)

This is the canonical list cards 02 and 03 re-derive against. One path per line;
no comments inside the fence.

```paths
/mnt/hot
/mnt/hot/downloads
/mnt/hot/downloads/incomplete
/mnt/hot/downloads/complete
/mnt/hot/downloads/tv
/mnt/hot/downloads/movies
/mnt/hot/downloads/music
/mnt/hot/downloads/scripts
/mnt/hot/downloads/books
/mnt/hot/events
/mnt/hot/processing
/mnt/hot/processing/sonarr-temp
/mnt/hot/processing/radarr-temp
/mnt/hot/processing/lidarr-temp
/mnt/hot/surveillance
/mnt/hot/surveillance/frigate/buffer
/mnt/hot/inbox
/mnt/hot/documents/consume
/mnt/hot/documents/export
/mnt/hot/documents/staging
```

### Declared-but-disabled `/mnt/hot` paths (NOT in the enabled set)

These are recorded so card 02/03 don't mis-classify them as orphans on a
re-enable. Each has a quoted reason in the table above.

- `/mnt/hot/processing/tdarr-temp` — tdarr disabled; tmpfile still created
- `/mnt/hot/processing/tdarr-backups` — tdarr disabled; tmpfile still created
- `/mnt/hot/receipts` — derived path, no enabled consumer
- `/mnt/hot/backups/containers` — `hwc.data.backup.enable = false`
- `/mnt/hot/backups/databases` — same
- `/mnt/hot/backups/system` — same

## Could-not-resolve

The static read resolved every path symbolically. The only sub-paths whose exact
on-disk shape cannot be predicted from the modules alone are the *contents* that
the running services create under the declared roots — they are load-bearing by
inheritance but card 02 (orphan scan) will need to walk the live tree to see
them:

- `/mnt/hot/downloads/<category>/<release-name>/...` — qbittorrent / sabnzbd write per-release subtrees under the category dirs. Only the category roots (`tv`, `movies`, `music`, `books`) are declarative.
- `/mnt/hot/downloads/incomplete/<release-name>` — qbt staging.
- `/mnt/hot/events/<event-id>.json` — orchestrator hook spool (writer is `media-orchestrator`, currently disabled; qbt/sab hooks still write here).
- `/mnt/hot/surveillance/frigate/buffer/<camera>/...` — Frigate-managed.
- `/mnt/hot/processing/<arr>-temp/<run>/...` — *arr-managed scratch.
- `/mnt/hot/inbox/<...>` — user/external drop zone (AI file-cleanup agent watches the root; sub-shape not declared).
- `/mnt/hot/documents/{consume,export,staging}/...` — Paperless-managed.

Nothing inside the nixos source uses an interpolation that this audit could not
resolve to a concrete path given `hot.root=/mnt/hot` and `media.root=/mnt/media`.
