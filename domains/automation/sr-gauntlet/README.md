# SR Gauntlet (schedule module)

Daily unattended investigation of DataX support requests. The pipeline itself
lives in its own repo at `~/700_datax/sr_gauntlet` (fetch → per-SR customer
context pack → headless read-only Claude investigation → REPORT.md → Discord);
this module contributes only the systemd service + timer that launch it.

Read-only by construction: agents work in disposable `origin/main` worktrees
of datax/jt-mcp, get zero MCP servers, and write only into their run dir. The
launcher verifies worktrees stayed clean. No code changes, no customer
replies — the human reviews each `investigations/<date>-<srId>/REPORT.md`.

## Structure

```
sr-gauntlet/
└── index.nix    # hwc.automation.srGauntlet.{enable,onCalendar,maxSrs,gauntletDir}
                 # systemd service `sr-gauntlet` (oneshot, User=eric) + daily
                 # timer (default 06:30, Persistent=true)
```

Enabled in `machines/server/config.nix` (host one-off: the pipeline checkout
and its credential sources — sr_analyzer/.env, datax/.env.local — only exist
on hwc-server).

## Changelog

- **2026-06-13**: Syncthing shared folder renamed `apps` → `600_apps` (2771f0c3). Pipeline path comments and READMEs that referenced the old name swept; no service unit changes.
- **2026-06-12**: Created. Daily 06:30 timer (7d/wk) wrapping
  `~/700_datax/sr_gauntlet/run.sh`; maxSrs=5 default; creds late-bound at
  runtime (nothing secret in the Nix store). Modeled on nightly-builds with
  two deltas: Persistent=true (read-only runs make mid-day catch-up safe) and
  no worktree-of-nixos (pipeline manages its own datax/jt-mcp worktrees).
