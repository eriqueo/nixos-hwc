# HWC Workspace Directory

**Runtime-editable scripts and repo tooling.** Folders loosely mirror the
`domains/` hierarchy where a domain reference exists. Rule of thumb: if a
path in here is not referenced from a `.nix` file, a shell alias, or
CHARTER.md, it is a deletion candidate — the 2026-07-05 audit removed a
full layer of copy-not-move reorg debris on exactly that test.

---

## Structure

```
workspace/
├── ai/              # domains/ai/ — bible automation (canonical copy), AI docs
├── automation/      # domains/automation + media orchestration hooks (CANONICAL
│                    #   hooks dir — referenced by domains/media/orchestration/*)
├── home/            # domains/home — scraper (nix-wired), mail, photo-dedup
├── media/           # domains/media — youtube-services (nix-wired), beets helpers,
│                    #   manifests/ (generated reorg/dedupe scripts, see its README)
├── monitoring/      # health-check scripts (NOT nix-wired; overlaps domains/monitoring —
│                    #   candidates for retirement as declarative coverage grows)
├── nixos-dev/       # Repo dev tools: charter-lint, grebuild, add-home-app,
│                    #   graph/ (referenced by flake.nix hwc-graph), audits, lints
├── plans/           # Dated architecture proposals (CHARTER §6) + audit reports
├── projects/        # Standalone app code parked here — Phase-2 eviction candidates
│                    #   (each wants its own repo; see 2026-07-05 audit)
├── system/          # secret-manager.sh (the `secret` alias), secrets-parity,
│                    #   couchdb/zfs utilities, diagnostics/, setup/
├── tools/           # readme-freshness.sh (Law-12 drift detector), web-speed.sh
└── utilities/       # lints/ (charter lints incl. permission-lint.sh — CHARTER §3.1),
                     #   audit/ (drift.py), setup-uptime-kuma.py
```

Load-bearing paths (verified 2026-07-05 — do not move without updating the
referencing site):

| Path | Referenced by |
|---|---|
| `nixos-dev/graph/` | `flake.nix` (hwc-graph package) |
| `nixos-dev/add-home-app.sh`, `nixos-dev/graph/hwc_graph.py` | `domains/home/core/shell/parts/zsh-init.nix` |
| `automation/hooks/*` | `domains/media/orchestration/{media-orchestrator,audiobook-copier}` |
| `home/scraper/*.py` | `domains/home/apps/scraper` |
| `media/youtube-services/` | `domains/media/youtube/parts/yt-transcripts-api` |
| `tools/readme-freshness.sh` | `domains/automation/readme-freshness` |
| `system/secret-manager.sh` | `secret` alias (`domains/home/core/shell/parts/aliases.nix`) |
| `utilities/lints/permission-lint.sh` | `CHARTER.md` §3.1 (Law 4) |
| `plans/` | `CHARTER.md` §6 (proposals convention) |

---

## Changelog

- 2026-07-05: Audit cleanup (see `plans/2026-07-05-systems-process-audit.md`).
  Deleted reorg-debris duplicates: `hooks/` + `media/hooks/` (stale forks of
  `automation/hooks/`), `diagnostics/` + `setup/` (dups of `system/*`),
  `bible/` (subset of `ai/bible/`), `nixos/` (fork of `nixos-dev/`; flake
  graph ref repointed), 9 `utilities/*` scripts duplicated from `system/` and
  `nixos-dev/` (incl. the stale divergent `utilities/secret-manager.sh`),
  `claude_plans/` (session scratch), `prompts/`, `migrations/`. Added
  `media/manifests/` (generated ops scripts moved out of docs/). README
  rewritten to match reality (old version described a `business/` dir that
  didn't exist and omitted half the tree).
- 2026-06-12: Added `tools/readme-freshness.sh` — Law-12 drift detector.
- 2026-06-09: `secret-manager.sh` multi-recipient encryption; added
  `secrets-parity.sh`. See `domains/secrets/README.md`.
- 2026-03-25: Restructured to mirror domains/ hierarchy.
- 2025-12-10: Reorganized from arbitrary categories to purpose-driven structure.
