# docs/audits — audit artifacts

One-shot, dated audit reports produced by nightly-builds cards. Each
sub-directory is a single audit; reports are static (not regenerated on
rebuild). The goal is to give later cards a stable, machine-readable source of
truth they can re-derive against.

## Structure

| Path | Purpose |
|---|---|
| `mnt-hot/` | `/mnt/hot` reconcile audit — funnel map, orphan list, deletion plan |
| `mnt-hot/active-paths.md` | Card 01: declarative active-paths map (load-bearing paths under `/mnt/hot` and `/mnt/media` on `hwc-server`) |

## Changelog

- 2026-06-24 — initial creation. Card 01 (`audit/hot-funnel-map`) wrote
  `mnt-hot/active-paths.md` from a static read of the nixos modules.
