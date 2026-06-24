# docs/audits — read-only library / system audits

Each audit here is the output of a nightly-builds card that **enumerates**
some part of the system and proposes fixes via a dry-run-by-default script.
The agent that wrote an audit never executes the proposed fixes — Eric
reviews the audit doc, decides which sections to act on, and runs the
companion `*-reorg.sh` (or equivalent) by hand.

## Structure

| Path | Purpose |
|---|---|
| `media/music-audit.md` | 2026-06-24 audit of `/mnt/media/music` — duplicates, tag-gap signals, mis-paths. |
| `media/music-reorg.sh` | Dry-run-by-default companion script for `media/music-audit.md`. `DRY_RUN=0` to act; `MODE={current,card}` selects rename target. |

## Conventions

* Read the audit doc before running the script. The doc names the totals;
  the script proposes the moves/deletes.
* Every audit script must default to dry-run (`DRY_RUN="${DRY_RUN:-1}"`) and
  honour `DRY_RUN=0` to act.
* Audits never modify Nix modules or live systemd services; they only touch
  the data directory they audit, and only when explicitly opted-in.

## Changelog

* **2026-06-24** — initial audit: `media/music-audit.md` + `media/music-reorg.sh`
  (nightly card `2026-06-24-media-library-organization-01-music-audit`).
  Branch `audit/media-music`.
