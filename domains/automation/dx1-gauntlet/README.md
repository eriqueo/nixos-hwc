# DX1 Gauntlet (schedule module)

Unattended investigation of open DX1 health-ledger cases (`dx1Cases`) —
sr-gauntlet's sibling. The pipeline itself lives in its own repo at
`~/700_datax/dx1_gauntlet` (fetch open cases → per-case transcript/OpenSearch
context pack → headless read-only Claude investigation → REPORT.md +
`dx1Investigations` Firestore doc → Discord); this module contributes only the
systemd service + timer that launch it, plus the drain behind the refinery
board's `/dx1` "▶ re-investigate now" button.

Read-only by construction (same containment model as sr-gauntlet): agents work
in disposable pinned worktrees of datax/jt-mcp, get zero MCP servers, and
write only into their run dir; the launcher verifies worktrees stayed clean.
No code changes, no customer contact — the human reviews each
`investigations/<fingerprint>_<stateHash>/REPORT.md`.

## Structure

```
dx1-gauntlet/
└── index.nix    # hwc.automation.dx1Gauntlet.{enable,onCalendar,maxCases,gauntletDir}
                 # systemd service `dx1-gauntlet` (oneshot, User=eric) + daily
                 # poll timer (strangler-fig cadence), PLUS the run-now drain
                 # (service + path unit on /var/lib/refinery/dx1-run-now;
                 # spool filenames carry the case fingerprint with ":" encoded
                 # as "+" — the drain decodes before `run.sh --id`).
```

Declared in `machines/server/config.nix` with **`enable = false`**: the board
page ships now (its reads are missing-tolerant), the schedule flips on once
the pipeline checkout exists on hwc-server (the repo is laptop-authored with
no remote yet). Credentials, service clones (`/var/lib/sr-gauntlet/{datax,
jt-mcp}`), the isolated `CLAUDE_CONFIG_DIR`, and the `sr-gauntlet-claude-oauth`
agenix token are all **shared with sr-gauntlet** — one credential and one
worktree source, two consumers.

## Changelog

- 2026-08-16: Module created (DX1 automation-gauntlet Phase 2b). Mirrors
  sr-gauntlet's unit anatomy: oneshot + timer (daily, `Persistent = true`),
  EnvironmentFile agenix Claude token, DXG_* env late-binding creds/repos/caps
  (`DXG_CAPS_FILE=/var/lib/refinery/caps.json`, board-written key `dx1`), and
  the spool path-unit for board-triggered targeted runs. Shipped disabled
  pending server provisioning of `~/700_datax/dx1_gauntlet`.
