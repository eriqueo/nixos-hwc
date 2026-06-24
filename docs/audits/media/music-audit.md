# Music library audit — `/mnt/media/music`

Date: 2026-06-24
Library root: `/mnt/media/music` (managed by Lidarr; see `domains/media/lidarr/`)
Total size: **71 GB** (25 GB of which is `_unsorted-quarantine-2025-11/`)
Mode: **read-only** — no files moved or deleted by this audit.

## Target standard

Per nightly card `01 — music library audit`:

```
Artist/Album/NN - Title.ext
```

i.e. two directory levels (`Artist/`, then `Album/`), and each track file named
`<two-digit track number><space><dash><space><title>.<ext>`.

> Note: the actual main-library convention on disk is `Artist/Album/NN Title.ext`
> (space-only separator, no dash). 2 795 of 2 875 main-library tracks use the
> `NN <title>` form; only 102 already match the card's `NN - Title.ext` form.
> Whether to normalise *to* the card spec or *to* current disk practice is a
> human decision and is left explicit in the dry-run script.

## Totals

| | Count |
|---|---|
| Top-level entries | 53 (52 artist dirs + 1 quarantine dir) |
| Artist dirs (main library) | 52 |
| Album dirs (main library, depth 2) | 245 |
| Audio tracks (main library) | 2 875 |
| Audio tracks (`_unsorted-quarantine-2025-11/`) | 1 018 |
| Audio tracks total | 3 893 |
| Non-audio sidecars (.jpg/.log/.cue/.m3u/.nfo etc) | ~520 |

Counts derived from:

```
find /mnt/media/music -mindepth 1 -maxdepth 1 -type d -not -name '_unsorted-quarantine-2025-11' | wc -l   # 52
find /mnt/media/music -mindepth 2 -maxdepth 2 -type d -not -path './_unsorted-quarantine-2025-11/*' | wc -l   # 245
find /mnt/media/music -mindepth 3 -type f \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' \) -not -path './_unsorted-quarantine-2025-11/*' | wc -l   # 2875
find /mnt/media/music/_unsorted-quarantine-2025-11 -type f \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' \) | wc -l   # 1018
```

## Audit method & limitations

* **Tag readers (`ffprobe`/`exiftool`/`mediainfo`) are NOT available in this
  audit venue** (sandboxed nightly worktree on hwc-server with no `nix-shell`
  in PATH). So tag-gap detection in this report is **filename-derived only**.
  A true tag audit (missing `artist`/`album`/`title`/`tracknumber` frames) must
  be run on a host that has those tools — the dry-run script emits the
  exact commands.
* The audit otherwise enumerates the tree with `find` and `du` only; **no audio
  payload bytes were read**.
* No beets library DB was found, so beets-side enumeration was not attempted;
  the dry-run script emits `beet ls`/`beet import -p` commands that have to
  be run on the host where the beets config + library db live.

---

## Duplicates

### A. Same album in ≥ 2 paths (32 dir-name collisions)

Detected by matching basenames across the tree. The dominant pattern is **a
quarantine copy under `_unsorted-quarantine-2025-11/music-cleanup-20251110/`
that mirrors an album in the main library**, e.g.:

```
./Rush/Roll the Bones
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Roll the Bones
---
./Rush/Power Windows
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Power Windows
---
./Rush/Presto
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Presto
---
./Rush/Caress of Steel (1975)
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Caress of Steel (1975)
---
./Brian Eno/Music for Films
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Music for Films
---
./Brian Eno/Music for Civic Recovery Centre
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Music for Civic Recovery Centre
---
./Brian Eno/Music for Prague
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Music for Prague
---
./John Fahey/America
./_unsorted-quarantine-2025-11/music-cleanup-20251110/America
---
./John Fahey/Christmas Guitar
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Christmas Guitar
---
./John Fahey/City of Refuge
./_unsorted-quarantine-2025-11/music-cleanup-20251110/City of Refuge
---
./John Fahey/Fare Forward Voyagers (Soldier's Choice)
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Fare Forward Voyagers (Soldier's Choice)
---
./John Fahey/God, Time and Causality
./_unsorted-quarantine-2025-11/music-cleanup-20251110/God, Time and Causality
---
./John Fahey/Old Fashioned Love
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Old Fashioned Love
---
./John Fahey/Old Girlfriends and Other Horrible Memories
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Old Girlfriends and Other Horrible Memories
---
./John Fahey/Red Cross, Disciple of Christ Today
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Red Cross, Disciple of Christ Today
---
./Ivor Cutler/Ludo
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Ludo
---
./Kurt Vile/10 Songs
./_unsorted-quarantine-2025-11/music-cleanup-20251110/10 Songs
---
./Panda Bear _ Excepter/Carrots _ KKKKK
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Panda Bear _ Excepter/Carrots _ KKKKK
```

Recommendation: for each pair, **diff the two trees and keep the higher-quality
copy** (prefer the one with embedded tags and proper track numbers, all else
equal). The dry-run script emits a per-pair `diff -r --brief` line so the
reviewer can see what differs before deleting.

### B. Self-nested artist dirs (`Artist/Artist/...`)

Eight artists have a redundant inner directory of the same name:

```
./Brian Wilson/Brian Wilson
./Dan Reeder/Dan Reeder
./Dirty Projectors/Dirty Projectors
./Os Mutantes/Os Mutantes
./Panda Bear/Panda Bear
./Rush/Rush
./This Heat/This Heat
./Ivor Cutler and Linda Hirst/Privilege/Privilege
```

These are most likely the **artist's self-titled album** (so the on-disk shape
is `Artist/Artist/01 …`, which is actually correct under the card's standard:
artist `Artist` → album `Artist`). The script flags each for human eyeball but
does **not** propose to move them.

### C. Other intra-library dir collisions

These collide between the quarantine and another deep path; almost certainly
the quarantine copy is the redundant one:

```
./Brian Eno/Drums Between the Bells (2011)/CD 01
./_unsorted-quarantine-2025-11/music-cleanup-20251110/CD 01
---
./Brian Eno/Drums Between the Bells (2011)/CD 02
./_unsorted-quarantine-2025-11/music-cleanup-20251110/CD 02
---
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Various Classical/101 Essential Classics V0/Disc 3
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Disc 3
---
./_unsorted-quarantine-2025-11/music-cleanup-20251110/GIRAFFES_ GIRAFFES!/Live In Toronto
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Live In Toronto
```

---

## Tag gaps (filename-inferred)

No tag reader was available in this venue, so only filename-derived signals
are recorded. The dry-run script includes the **real tag-audit commands** to
run on a host that has `beet`, `ffprobe`, or `exiftool`.

### Tracks without a leading track number — **56 files**

These are tracks whose basename does not start with digits; they almost
certainly lack a `tracknumber` tag and/or were named off the file's tags. All
56 are in the main library, mostly two albums where the filename embeds the
full `Artist - Album - NN - Title.flac` form (sortable but redundant):

```
./Brian Eno/Untold (FOREVERANDEVERNOMORE)/Brian Eno - FOREVERANDEVERNOMORE - 01 - Who Gives a Thought.flac
…
./Brian Eno/Untold (FOREVERANDEVERNOMORE)/Brian Eno - FOREVERANDEVERNOMORE - 10 - Making Gardens Out of Silence.flac
./Fred Frith/Cut Up the Border/Fred Frith - Cut Up the Border - 01 - Just Call Her Nagra.flac
…
```

### Legacy `Artist_Album_NN_Title.mp3` filenames — **14 files** (loose at artist root)

```
./Aretha Franklin/Aretha Franklin_A Brand New Me_12_You're All I Need to Get By.mp3
./Aretha Franklin/Aretha Franklin_A Brand New Me_01_Think.mp3
… (12 more)
./Scientist/Scientist_1999 Dub_01_Work To Go Dub.mp3
./Scientist/Scientist_1999 Dub_02_Solomon The Great.mp3
./Scientist/Scientist_1999 Dub_03_Revolutionist.mp3
```

These are simultaneously a **mis-path** (no album dir) and a **filename-format**
violation. They should be foldered into `Artist/Album/NN - Title.mp3`.

### Real tag-audit (NOT run here — emit only)

A proper "missing artist/album/title/tracknumber" pass requires a tag reader.
The dry-run script emits the commands; rerun on a host that has them:

```
beet list -p missing:1                  # albums beets thinks are incomplete
beet list -p ^artist::.                 # tracks without an artist tag
beet list -p ^album::.                  # tracks without an album tag
beet list -p ^track::[0-9]              # tracks without a numeric track tag
```

---

## Mis-paths (files not at `Artist/Album/NN - Title.ext`)

### Loose tracks at artist root (depth 2, not inside an album dir) — **17 files**

```
./Aretha Franklin/Aretha Franklin_A Brand New Me_*.mp3      (14 tracks)
./Scientist/Scientist_1999 Dub_*.mp3                         (3 tracks)
```

→ Move each set into an album dir: `Aretha Franklin/A Brand New Me/` and
`Scientist/1999 Dub/`, and rename to `NN - Title.mp3`.

### Incomplete downloads — **12 `.mp3.part`**

All under `_unsorted-quarantine-2025-11/music-cleanup-20251110/Various Classical/`.
Recommendation: delete (they are interrupted classical rips, not partial copies
of files the main library wants).

### Junk sidecars — **2 files**

```
./Sun City Girls/Sun City Girls - 330,003 Crossdressers/.DS_Store
./_unsorted-quarantine-2025-11/music-cleanup-20251110/Music for Films [1978]/.12 Brian Eno - CD-01 - 'There Is Nobody'.flac.I6Jwkt
```

→ Delete.

### Filename-format mismatches (entire main library) — **~2 795 files**

The main library predominantly uses `NN <title>.ext` (no dash), while the card
target is `NN - <title>.ext`:

| Pattern | Count | Example |
|---|---|---|
| `^NN <title>` (current default) | 2 795 | `Bob Dylan/Blood on the Tracks/01 Tangled Up in Blue.flac` |
| `^NN - <title>` (card target) | 102 | (current minority) |
| `^[A-Z]` (no leading track #) | 56 | `Brian Eno - FOREVERANDEVERNOMORE - 01 - Who Gives a Thought.flac` |

→ The dry-run script offers **two modes** (see `MODE=` in the script):
  * `MODE=card` — rename every `NN <title>` → `NN - <title>` (matches card spec)
  * `MODE=current` — leave `NN <title>` as-is, only fix the 56 non-numeric and
    14 underscore-named files. This is the lower-churn option.

The agent does **not** decide which to run — that's an Eric call.

### Inconsistent collaboration-artist separators (whole library)

Lidarr replaces `/` in artist names with `_`, so collaborations show up with
three different separators:

```
./Fred Frith _ Amanda Miller        ← was "Fred Frith / Amanda Miller"
./Fred Frith and Arte Quartett
./Fred Frith & Hardy Fox
./Panda Bear _ Excepter
./Panda Bear & Sonic Boom
./Brian Wilson and Van Dyke Parks
./Neil Young & Crazy Horse
./Ivor Cutler and Linda Hirst
```

This is a **tag-source** problem, not a filesystem problem: the cure is to fix
the MusicBrainz `artist credit` upstream (or pin Lidarr's "Standard Track
Format" to a normalised form). Flagged for the reviewer; not auto-fixed.

---

## Quarantine sub-structure (informational)

`_unsorted-quarantine-2025-11/music-cleanup-20251110/` is 25 GB and 1 018
tracks, with 109 immediate children — a mix of album dirs (most), nested
artist dirs (`GIRAFFES_ GIRAFFES!/`, `Panda Bear _ Excepter/`, `Various
Classical/`), and oddly-named sentinels (`_`, `__`). The bulk of the work
hiding in here is the **32 duplicate-of-main-library albums** listed above;
the remainder are albums never re-imported. Recommendation: re-run beets
import on the quarantine root **after** the duplicates above are resolved.

---

## What the dry-run script does

`docs/audits/media/music-reorg.sh` is a single dry-run-by-default bash script.
It honours `DRY_RUN=0` to act, and `MODE={card,current}` to pick the rename
target. It does **all four** of: list duplicate-album diffs, propose moves for
the 17 loose-at-artist tracks, delete the 12 `.part` and 2 junk files, and emit
the beets/file renames for the 56 + 14 filename-format violations. It does
**not** touch the 2 795 "NN <title>" tracks unless `MODE=card` is set. It also
emits a stand-alone `beet` block to run the real tag-gap audit on a host that
has `beet`.

The script is committed *unrun*. The agent does not execute it.
