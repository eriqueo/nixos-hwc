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
├── monitoring/      # operator health scripts (not Nix-wired); frigate-health.sh
│                    #   emits read-only camera/storage evidence for issue #100
├── nixos-dev/       # Repo dev tools: charter-lint, grebuild, add-home-app,
│                    #   graph/ (referenced by flake.nix hwc-graph), audits, lints,
│                    #   tests/ (executable regression suites for the tools here)
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
| `media/youtube-services/` | `domains/media/youtube/parts/transcripts` |
| `tools/readme-freshness.sh` | `domains/automation/readme-freshness` |
| `system/secret-manager.sh` | `secret` alias (`domains/home/core/shell/parts/aliases.nix`) |
| `utilities/lints/permission-lint.sh` | `CHARTER.md` §3.1 (Law 4) |
| `plans/` | `CHARTER.md` §6 (proposals convention) |

---

## Frigate field evidence

For the first post-change Frigate storage window, run on hwc-server after
2026-09-25 13:23 America/Denver:

```bash
bash workspace/monitoring/frigate-health.sh --since 2026-09-24T13:23:00-06:00 --hours 24
```

Run earlier to inspect a partial window (`window.complete` stays false).
The default without `--since` is the previous 24 hours, not a post-change claim.
The tool requires Python 3 and noninteractive sudo access to the Frigate
container. Exit zero means collection and current enabled-camera health passed;
it does not certify a full window or field coverage. Compare `present_samples`
and `online_samples` with `expected_samples` before comparing storage.
Missing samples and outages prevent a like-for-like comparison. Retention can
delete older footage, so collect the first-day result before three days pass.
Counts use retained database segments and event metadata; they do not prove
that a person walking every approach gets detected or notified.

## Changelog

- 2026-09-24: Repaired `monitoring/frigate-health.sh`: use the live API on port
  5000, omit raw logs and process arguments, return nonzero on collection/health
  failure, and emit JSON containing bounded recording/event totals and camera
  availability samples. No cron job, service restart, notification, or data write.
- 2026-09-22: Completed the `add-home-app.sh` v3.0 repair after the recovered
  nightly branch exposed three uncovered seams. Interactive `s` now re-enters
  search under `set -e`; machine enablement preserves both grouped and direct
  assignment shapes already used in `machines/*/home.nix`; and a failed
  integration restores every scoped file. The executable regression suite now
  carries 70 assertions, including both machine shapes and byte-identical
  rollback.
- 2026-09-15: `nixos-dev/add-home-app.sh` v3.0 — repaired against Charter v12.6.
  Four live breakages: machine detection walked every flake output via
  `nix flake show`; package search resolved against the moving `nixpkgs`
  registry instead of this repo's locked revision; `--no-interactive` set a flag
  nothing read, so every prompt still blocked; and generation emitted a Law-10
  `options.nix` and wrote to the deleted `profiles/home.nix`. Now: targeted
  `nix eval #nixosConfigurations --apply builtins.attrNames`, search and
  validation against the flake.lock nixpkgs, a real non-interactive contract
  (one exact top-level attribute or a loud failure with stable exit codes
  3/4/5), and generation through `domains/lib/mkSimpleApp.nix` or a Law-6
  native adapter plus per-app README, apps README index, and the enable in
  `machines/<machine>/home.nix`. On `main` it diverts to a dedicated worktree.
  New: `nixos-dev/tests/test-add-home-app.sh` regression suite driving
  the real script against isolated git + Nix fixtures.
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
