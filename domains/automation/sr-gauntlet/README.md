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

**Claude auth (dedicated token).** The headless `claude -p` authenticates with a
dedicated long-lived subscription token (`claude setup-token`), stored as the
`sr-gauntlet-claude-oauth` agenix secret (plaintext `CLAUDE_CODE_OAUTH_TOKEN=…`)
and sourced via `EnvironmentFile` — never through the Nix store. Critically,
`CLAUDE_CONFIG_DIR` is pointed at a service-owned dir (`/var/lib/sr-gauntlet/
claude-config`) that holds **no** `credentials.json`: with `HOME=/home/eric` the
on-disk interactive credentials otherwise *shadow* the env token (verified — a
bogus env token still authed off the on-disk creds), which would make the token
inert. This also removes the interactive↔headless contention on the shared
`~/.claude/.credentials.json` that caused 5 straight 401s (2026-07-21/22).
Rotate by re-running `claude setup-token` and re-encrypting the secret; oneshot
units re-read it each run, so no restart is needed.

## Changelog

- **2026-07-22**: **Dedicated Claude subscription token.** The gauntlet had 5
  consecutive investigations fail with `401` (2026-07-21/22) — every one died at
  the `claude -p` exec. Root cause: the headless agent was relying on the
  interactive OAuth token in `~/.claude/.credentials.json`, whose ~8h access
  token + rotating refresh token was kept fresh only by Eric's interactive
  sessions; the unattended timer lapsed once the server went a day without one.
  Fix: a dedicated long-lived token (`claude setup-token`) in the new
  `sr-gauntlet-claude-oauth` agenix secret, sourced via `EnvironmentFile`, PLUS
  an isolated `CLAUDE_CONFIG_DIR` (`/var/lib/sr-gauntlet/claude-config`, no
  `credentials.json`) — required because on-disk creds otherwise shadow the env
  token. Stays on the Max subscription (no API billing). `check-creds.mjs` now
  also validates Claude auth (token-or-on-disk) so a future lapse aborts loudly.
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
