# TV library audit — `/mnt/media/tv`

Generated 2026-06-24 against the read-only library root mounted at
`/mnt/media/tv` (managed by the Sonarr container — see
`domains/media/sonarr/sys.nix`, which mounts `${hwc.paths.media.root}/tv` →
`/tv` inside the container).

This is an **audit**, not a remediation: nothing under `/mnt/media/tv` was
modified. The companion script `tv-reorg.sh` is dry-run-by-default and was
**not executed**.

## Standard

Sonarr's canonical layout (and the standard this audit measures against):

```
<library>/<Show Name> (<Year>)/Season NN/<Show Name> - SxxEyy[ - <Title>].<ext>
```

with these specifics:

- One folder per show at the library root; year-disambiguated when ambiguous
  (`Archer (2009)`).
- Seasons live under `Season NN` (two-digit, zero-padded). Specials live under
  `Season 00`.
- Each episode is a single file whose basename contains a parseable
  `SxxEyy`/`SxxxEyyy` token (case-insensitive).
- No loose video files at the library root or directly inside a show folder
  (`Show/foo.mkv`); everything is inside a `Season NN` directory.
- No editor / DS sidecar trash (`.DS_Store`, AppleDouble `._*`).
- Reserved extras subfolders (`featurettes/`, `trailers/`, `other/`) are not
  part of Sonarr's standard layout and confuse the indexer.

## Headline counts

| Metric                                             | Count |
|----------------------------------------------------|------:|
| Shows (top-level folders)                          |    42 |
| Total video files (mkv/mp4/avi/m4v/mov)            |  4389 |
| Episodes with parseable `SxxEyy`                   |  4277 |
| Files without parseable `SxxEyy` (incl. `._*`)     |   112 |
| Files without parseable `SxxEyy` (excl. `._*`)     |    82 |
| AppleDouble `._*` files (all extensions)           |    72 |
| `.DS_Store` files                                  |     2 |
| Loose files at library root                        |     1 (`.DS_Store`) |
| Shows with **no** `Season NN` directory at all     |     2 |
| Shows with **single-digit** `Season N` folders     |    11 |
| Shows using `Specials` instead of `Season 00`      |     7 |
| Shows with non-standard extras subfolders          |     9 |
| Shows with internal season-numbering gaps          |     4 |

(Source commands and quoted output appear in each section below.)

## 1. Shows not using `Season NN` layout

### 1a. No season folders at all (all episodes loose in show root)

```
A Real Bug's Life/  — 10 loose files at show root
Cars on the Road/   —  9 loose files at show root
```

Example:

```
A Real Bug's Life/A.Real.Bug's.Life.S01E01.The.Big.City.EAC3.5.1.1080p.WEBRip.x265-iVy.mkv
A Real Bug's Life/A.Real.Bugs.Life.S02E01.1080p.WEB.h264-EDITH.mkv
Cars on the Road/Cars.on.the.Road.S01E01.Dino.Park.1080p.DSNP.WEB-DL.DD.5.1.Atmos.H.264-playWEB.mkv
```

Both shows are missing year suffixes too (`A Real Bug's Life (2024)`,
`Cars on the Road (2022)`) and need a Sonarr rescan after restructuring.

### 1b. Single-digit `Season N` folders (should be `Season NN`)

```
Bluey (2018)/Bluey Season 1
Bluey (2018)/Bluey Season 2
Bluey (2018)/Bluey Season 3
Columbo/Season 1   Season 2   Season 3   Season 4   Season 5   Season 6
Dinosaur Train (2009)/Dinosaur Train Season 4
Dinosaur Train (2009)/Dinosaur Train Season 5
Garth Marenghi's Darkplace/Garth Marenghi's Darkplace Season 1
Grizzy & the Lemmings (2016)/Grizzy & the Lemmings Season {1..4}
Jeeves and Wooster/Jeeves and Wooster Season {1..4}
Life on Earth/Life on Earth Season 1
Parks and Recreation/Parks and Recreation Season {1..7}
Schoolhouse Rock (1973)/Schoolhouse Rock Season {1..7}
The Chair Company (2025)/The Chair Company Season 1
This is America, Charlie Brown/This is America, Charlie Brown Season 1
```

Many of these are also redundantly *prefixed* with the show name
(`Bluey Season 1` rather than just `Season 1`). Both pathologies should be
normalized to `Season 0N`.

Eleven shows; **42 season directories** in total need a rename.

Also missing year suffix: `Columbo`, `Garth Marenghi's Darkplace`,
`Jeeves and Wooster`, `Life on Earth`, `Parks and Recreation`,
`This is America, Charlie Brown`.

### 1c. Empty year suffix `()`

Year present but unfilled (likely a Sonarr add without TVDB year):

```
Detroiters ()
Ice Age - Scrat Tales ()
Mister Rogers' Neighborhood ()
Mystery Science Theater 3000 ()
The Busy World of Richard Scarry ()
The Stinky & Dirty Show ()
```

These should be re-resolved against TVDB and renamed to `(YYYY)`.

### 1d. `Specials` folder instead of `Season 00`

```
Band of Brothers (2001)/Specials
Looney Tunes (1930)/Specials
Mystery Science Theater 3000 ()/Specials
Nathan for You (2013)/Specials
Octonauts (2010)/Specials
Octonauts Above and Beyond (2021)/Specials
Sherlock (2010)/Specials
```

Sonarr's canonical name for specials is `Season 00`.

### 1e. Non-standard extras subfolders (`featurettes/`, `trailers/`, `other/`)

```
Archer (2009)/featurettes      Archer (2009)/trailers
It's Always Sunny in Philadelphia (2005)/other
It's Always Sunny in Philadelphia (2005)/trailers
It's Always Sunny in Philadelphia (2005)/S01 480p DVD   (and S02/S03 480p DVD)
Nathan for You (2013)/other
Octonauts (2010)/trailers
Peep Show (2003)/featurettes      Peep Show (2003)/other
Reading Rainbow (1983)/trailers
Sherlock (2010)/trailers
The Simpsons (1989)/trailers      The Simpsons (1989)/other
Transformers (1984)/other
```

These should be removed from the Sonarr-managed root entirely (move to
`/mnt/media/extras/` or delete), since Sonarr's import won't recognize them
and they pollute monitoring.

It's Always Sunny additionally uses `S01 480p DVD` / `S02 480p DVD` /
`S03 480p DVD` instead of `Season 01..03` — same root rename treatment as 1b.

## 2. Episodes without parseable `SxxEyy`

Counted as filenames lacking a case-insensitive `s<digits>e<digits>` token,
excluding macOS AppleDouble sidecars.

| Show                                | Files |
|-------------------------------------|------:|
| Mystery Science Theater 3000 ()     |    41 |
| Life on Earth                       |    11 |
| Nathan for You (2013)               |     8 |
| It's Always Sunny in Philadelphia   |     5 |
| Transformers (1984)                 |     4 |
| Octonauts Above and Beyond (2021)   |     3 |
| The Simpsons (1989)                 |     2 |
| Peep Show (2003)                    |     2 |
| Archer (2009)                       |     2 *(non-`._` only: 2 in extras dirs)* |
| Sherlock (2010)                     |     1 |
| Reading Rainbow (1983)              |     1 |
| Octonauts (2010)                    |     1 |
| Band of Brothers (2001)             |     1 |
| **Total (excl. AppleDouble)**       |  **82** |

Examples (quoted from `find`):

```
./Life on Earth/Season 1/Life.On.Earth.E09.720p.BluRay.x264-DERANGED.mkv
./Mystery Science Theater 3000 ()/Specials/MST3K - K10 - Cosmic Princess.avi
./Mystery Science Theater 3000 ()/Specials/MST3K - Mr. B's Lost Shorts.avi
./Octonauts Above and Beyond (2021)/Specials/Octonauts Above and Beyond - The Great Arctic Adventure.mkv
./Transformers (1984)/other/S3 Opening The Transformers Anne Bryant and Ford Kinder (Opening Credits).mkv
./Archer (2009)/featurettes/Archer's Best Travel Hijinks.mkv
./Reading Rainbow (1983)/trailers/PBS Kids Promo Reading Rainbow (2002).mkv
```

Root causes by show:

- **Life on Earth** — files use `E09` only (no `S01`). Add `S01` prefix:
  `Life.On.Earth.S01E09.720p.BluRay.x264-DERANGED.mkv`.
- **MST3K Specials** — files use one-token codes like `K10`, `S12` that
  collide with the SxxEyy regex but are actually catalog numbers, plus
  free-form names. Need explicit `S00E01..N` numbering.
- **Octonauts Above and Beyond Specials** — three named specials with no
  episode tokens; need `S00E01..03` assignment.
- **Extras dirs** — featurettes/trailers/other content. These are covered by
  section 1e; the right answer is to move them out of the Sonarr root rather
  than rename them.

## 3. Loose files at the library root

```
/mnt/media/tv/.DS_Store
```

That is the only loose file at the library root.

`find . -maxdepth 1 -type f` output:

```
./.DS_Store
```

## 4. Sidecar / OS trash

| Type                          | Count | Distribution |
|-------------------------------|------:|--------------|
| AppleDouble `._*` (all)       |    72 | Archer: 27, South Park: 44, Sherlock: 1 |
| `.DS_Store`                   |     2 | library root + one show |

These should all be deleted; they're macOS Finder droppings.

## 5. Season-number gaps

Internal gaps in the season sequence (seasons exist on disk but the run is
non-contiguous from 1 to max):

```
Mister Rogers' Neighborhood ()   have [4 5 6 10 11 12]      missing [1 2 3 7 8 9]
South Park (1997)                have [1..28 minus]         missing [6 8 9 14]
The Simpsons (1989)              have [1..37 minus]         missing [34 35]
Thomas the Tank Engine & Friends have [1..8, 14..17]        missing [9 10 11 12 13]
```

These are **content gaps** (missing seasons), not naming gaps — Sonarr should
be left to pick them up via Wanted / Cutoff Unmet. They're listed for
completeness; the dry-run script does not attempt to acquire content.

## Dry-run fix plan

The companion script `tv-reorg.sh` enumerates one rename/delete per finding:

1. Delete all `.DS_Store` and AppleDouble `._*` files (72 + 2 = 74 deletions).
2. `git mv`-style rename single-digit and prefixed season folders to
   `Season NN`: 11 shows, 42 season directories.
3. Rename every `Specials` folder to `Season 00` (7 shows).
4. Rename the malformed `S0N 480p DVD` folders in *It's Always Sunny* to
   `Season 0N` (3 dirs).
5. Print a manual-review block for non-Sonarr extras subdirs
   (`featurettes/`, `trailers/`, `other/`) — these need a human decision
   (delete vs. move to `/mnt/media/extras/`) and are not auto-renamed.
6. Print a manual-review block for `Life on Earth` episodes that need an
   `S01` prefix injected (regex pattern + 11 examples).
7. Print a manual-review block for `MST3K` and `Octonauts Above and Beyond`
   specials needing `S00E0N` assignment.
8. Print a manual-review block for `A Real Bug's Life` and `Cars on the Road`:
   create `Season 01`/`Season 02` and move files in.
9. Print a manual-review block for show folders missing year suffixes
   (`Columbo` → `Columbo (1971)`, etc.) and empty-year `()` shows.

The script never runs unless invoked with `DRY_RUN=0`, and even then it
operates only inside `/mnt/media/tv`.

## Out of scope

- Actually executing any rename or delete.
- Touching files anywhere outside `/mnt/media/tv` (the script does not write
  outside this root).
- Per-episode title normalization (Sonarr will do this on rescan once the
  folder layout is canonical).
- Acquiring missing seasons (section 5).
