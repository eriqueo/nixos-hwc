# domains/automation/brain-sweep/

## Purpose

The **brain janitor** — a nightly mechanical sweep of the Obsidian brain vault. Runs
`brain sweep --report` (the brain CLI at `~/600_apps/brain`) to detect structural + convention
drift and write a dated, append-only report to `_inbox/janitor/`. A **detector, not a fixer**:
it reads the vault and edits nothing. vault-sync then carries the report to the hub.

## Boundaries

- **Manages**: a oneshot systemd service + nightly timer that runs the sweep under the vault's
  shared `.git/.sync.lock` flock, and a fail-soft hwc-notify ping on alert/failure.
- **Does NOT manage**: the check logic (that lives in the brain CLI repo, `~/600_apps/brain`,
  `lib/vault` · `lib/checks` · `lib/sweep` · `lib/report`), the vault sync
  (→ domains/automation/vault-sync), or the semantic index (→ domains/server/native/ai/brainvec).

## Structure

```
domains/automation/brain-sweep/
├── index.nix     # Module: hwc.automation.brainSweep.* (sweep service + nightly timer)
└── README.md
```

## Configuration

```nix
hwc.automation.brainSweep.enable = true;         # nightly at 03:30 by default
# hwc.automation.brainSweep.interval  = "*-*-* 03:30:00";
# hwc.automation.brainSweep.repoDir   = "/home/eric/600_apps/brain";
# hwc.automation.brainSweep.notifyUrl = "http://127.0.0.1:11600";  # "" disables notify
```

## Design Decisions

- **Code-in-checkout, Nix-only-schedules** — same pattern as brainvec: the check logic lives in
  its own repo at `~/600_apps/brain`; this module only schedules it + supplies the environment.
  A missing/unbuilt checkout (`dist/bin/brain.js` absent) logs the clone/build command and exits 0
  — a rebuild without the code degrades gracefully instead of failing the unit.
- **Single source of truth for the check set** — the `janitor` unit in `_charter/janitor.md`
  declares which checks exist and each trip threshold; `brain sweep` reads that note and dispatches
  each metric `id` to its coded check. Add/adjust a check by editing that note + the CLI, not this module.
- **Shared flock** — takes `<vault>/.git/.sync.lock` (blocking) so it never races vault-sync or
  brain-mcp on the vault's git state.
- **Notify only when it matters** — exit-code contract from `brain sweep`: `0` = clean or
  review-level trips (the report is the deliverable, no 3am push), `2` = an alert-severity trip
  (`stversions_bloat`) → high-priority hwc-notify, other = the sweep failed → notify + fail the unit.

## Changelog

- 2026-07-23: Created. Operationalizes the long-designed-but-never-deployed janitor
  ([[janitor]] in the vault). Replaces the mythical `brain-janitor-nightly` scheduled prompt with
  a real deterministic sweep. Enabled on hwc-server (`machines/server/config.nix`).
