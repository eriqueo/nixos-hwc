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
                 # systemd service `sr-gauntlet` (oneshot, User=eric) + poll
                 # timer (default every 15 min) for auto-investigation, PLUS
                 # the run-now drain (service + path unit) behind the refinery
                 # board's "▶ re-investigate now" button.
```

Enabled in `machines/server/config.nix` (host one-off: the pipeline checkout
and its credential sources — sr_analyzer/.env, datax/.env.local — only exist
on hwc-server).

**Auto-investigation (poll).** The timer fires every 15 min; `run.sh` Phase A
fetches waiting SRs from Firestore and the thread-hash ledger dedups, so most
ticks find nothing and exit fast. A genuinely new/changed waiting SR is
investigated within ~15 min of arrival. `run.sh`'s lock prevents overlap.

**Run-now (board trigger).** The hardened refinery board can't run `run.sh`
itself, so the SR page's "▶ re-investigate now" button drops an `<srId>` file in
the shared spool `/var/lib/refinery/sr-run-now`; the `sr-gauntlet-runnow` path
unit drains it and runs `run.sh --id <srId>` out-of-band. This mirrors the
nightly-builds run-now pattern exactly. The board sets
`REFINERY_SR_RUNNOW_SPOOL` to the same path.

## Changelog

- **2026-07-13**: Decoupled the long-running service from Eric's `~/700_datax`
  dev tree — source clones now point at service-owned `/var/lib/sr-gauntlet/{datax,jt-mcp}`
  (official elstruck repos, fetch-only, `origin/main` worktrees in `/tmp`), and
  creds move to a trimmed 0600 `/var/lib/sr-gauntlet/datax.env` (now 9 keys:
  the required Firebase/OpenSearch set plus optional `SRG_PUSH_URL`/`SRG_PUSH_SECRET`
  for report push into the datax admin UI, skipped gracefully when absent).
  `check-creds.mjs` preflight alerts Discord with the name of any missing key.
  Dropped `python3` from the unit PATH — the ledger/prompt/verdict heredocs it
  served are now node subcommands in the pipeline's `lib.mjs`.
- **2026-06-16**: Auto-investigation + run-now. Timer changed from daily 06:30
  to a **15-min poll** (Persistent=false) so new SR tickets are investigated on
  arrival (the ledger makes idle ticks cheap). Added the **run-now drain**:
  `sr-gauntlet-runnow` oneshot + a `systemd.path` watching
  `/var/lib/refinery/sr-run-now`, executing `run.sh --id <srId>` — the executor
  behind the refinery board's "▶ re-investigate now" button. Shared env/path
  factored into `srgEnv`/`srgPath`. Mirrors nightly-builds run-now.
- **2026-06-12**: Created. Daily 06:30 timer (7d/wk) wrapping
  `~/700_datax/sr_gauntlet/run.sh`; maxSrs=5 default; creds late-bound at
  runtime (nothing secret in the Nix store). Modeled on nightly-builds with
  two deltas: Persistent=true (read-only runs make mid-day catch-up safe) and
  no worktree-of-nixos (pipeline manages its own datax/jt-mcp worktrees).
