# Agent harness

The agent harness gives Claude Code, Codex, Pi, T3, and Herdr one static policy
source and one mutable state store.

## Structure

The fleet control list names hwc-home, hwc-work and hwc-laptop.

- `index.nix` installs the pinned policy, state links, health CLI, the `ws` workspace allocator, the state-sync timer (which re-renders `LEDGER.md` after each run), and the opt-in `agent-cli-update` timer. Its `agentWorkspace` activation creates `workspaceRoot` (`~/800_agents`) and moves the state clone into `state/` once, leaving `stateDir` as a link.
- `sys.nix` installs machine-wide Claude policy under `/etc`, and generates Claude Code's MCP config as tmpfiles store symlinks: `~/.mcp.json` (`userMcp`, read by every project under the home directory: shared servers, `hwc-sys` over HTTP at `hwc.system.mcp.url`, `brain` at `userMcp.brainUrl`) and the nixos repo's `.mcp.json` (`projectMcp`: `git` plus per-host `extraServers`). The host running brain-mcp asserts `brainUrl` names its route. Every host asserts that no Syncthing folder overlaps `hwc.paths.user.agents`.
- `contract.nix` defines the ownership and revision contract shared by both lanes.
- `control.sh` implements local and fleet health checks plus policy publication.
- `control.test.sh` checks split revisions, mutable runtime references, fleet names, and publication to all hosts and source remotes.
- `state-sync.sh` synchronizes only memories, the mistakes ledger, and the agent-workspace `ledger/` and `guard/` files, with one bounded validation case under `.git`.
- `state-validate.sh` owns the memory contract for both full-store scans and projected writes on stdin.
- `state-sync.test.sh` verifies import, links, validation blocking, recovery, commit, pull, and push against a throwaway hub.

## State ownership

Nix pins static instructions, skills, hooks, and provider adapters. The Git clone
at `~/800_agents/state` (still reachable as `~/.agent-state` until S8) holds
mutable memories, `MISTAKES.md`, each host's workspace ledger
(`ledger/<host>.json`, written only by that host) and the workspace guard's
`guard/arm.json` and `guard/budgets.json`. Project repositories still own their
local `AGENTS.md` or `CLAUDE.md` files.

The agent workspace (`~/800_agents`: `projects/`, `closed/`, `log/`,
`LEDGER.md`) is local to each host. Its allocator, guard and worktree hooks are
static policy in claude-config (`bin/ws`, `hooks/workspace-*.sh`); the design
is `~/000_inbox/downloads/agent/tech/agent-workspace/design.md`.

New or changed memories declare `authority: observation|reference|decision` and
a non-empty `source:`, at the top level or directly under `metadata:` (where
Claude Code's memory writer moves them). Standing policy belongs in the static harness or a
project repository and is rejected from changed memory files.

The private `eriqueo/claude-config` GitHub repository publishes static revisions
for both root evaluators. The server bare repository remains an authoring mirror.

## Operations

Run `agent-harness` for the interactive menu. Session launchers run the local
doctor automatically. `agent-harness doctor --fleet` compares every configured host with
the local desired revision. `agent-harness publish` checks and pushes static
policy, updates the Nix pin, builds and switches the configured fleet, and finishes with
the fleet doctor. `agent-harness sync` validates and synchronizes mutable state.

On a host with `cliUpdates.enable`, `agent-cli-update` runs daily. Run it by
hand with `systemctl --user start agent-cli-update`. Read the version changes
with `journalctl --user -u agent-cli-update`. To roll back a bad release, run
`npm install -g <package>@<previous version>` with the version from that log.

The doctor verifies actual provider paths, system and Home Manager ownership
manifests, state shape, Codex hook trust, commands, and the sync timer. A dirty
authoring checkout is a warning; a runtime reference to it is a failure.

## Changelog
- 2026-09-30: `agent-harness publish` ends with the fleet doctor from the newly installed CLI. Re-running its own pre-switch copy compared every freshly switched host with the old revision and reported false FAILs.
- 2026-09-30: `agent-harness publish` builds each remote host in its own store (`--eval-store auto --store ssh-ng://<host>`). Building hwc-home on hwc-work refetched its CUDA archives and a dropped NVIDIA download failed publication twice. `control.test.sh` checks the remote store flag.
- 2026-09-30: Agent workspace S2. Add `workspaceRoot` (from `hwc.paths.user.agents`), the one-time move of the state clone to `~/800_agents/state` behind a `~/.agent-state` link, the `ws` package, a `LEDGER.md` render after each sync, and `ledger/*.json` and `guard/*.json` in the state contract (`contract.nix`, validator, fingerprint, staging; `state-sync.test.sh` covers them). `sys.nix` asserts no Syncthing folder overlaps the root.

- 2026-09-26: Rename the home fleet target to hwc-home; keep the shared harness pin and per-host session stores.

- 2026-09-25: Fleet health and publication include hwc-work. Publication builds
  and switches the configured host list instead of a separate two-host list.
- 2026-09-25: Publication updates the server's static-policy mirror before
  remote switches, then fast-forwards each host's authoring checkout. The
  publication test checks both remotes and all three build/switch targets.
- 2026-09-25: `.mcp.laptop.json`/`.mcp.server.json` were tracked (committed in
  2025, gitignored later), so the tmpfiles `r` rules that deleted them left
  every checkout dirty. They are now removed from the repo and the rules are
  gone. Their tracked contents were placeholders, never live keys.
- 2026-09-25: `state-validate.sh` accepts `authority`/`source`/`standing` as
  direct children of `metadata:`. Claude Code rewrites each newly written memory
  that way, so every new memory failed the store check and blocked sync (twice
  on 2026-09-25). `state-sync.test.sh` pins the accepted and rejected forms.
- 2026-09-25: `sys.nix` also generates `~/.mcp.json` (`userMcp`), replacing
  the HM shell module's copy on hwc-laptop and a hand-kept file on hwc-server.
  Both named brain on hwc-server, where it no longer runs since service-split
  wave 1; `brainUrl` now derives from the hosts registry (hwc-work), and hwc-work
  asserts it matches brain-mcp's route. The shared servers moved from the repo
  file to this one.
- 2026-09-25: `sys.nix` generates `~/.nixos/.mcp.json` (`projectMcp`), replacing
  the hand-kept `.mcp.laptop.json`/`.mcp.server.json` copies and their setup
  script. The server copy spawned a stale checkout build of the MCP gateway
  (dist/ from 2026-09-21) and held inline keys; the laptop copy had no gateway.
  Every host now reaches the Nix-built gateway service over HTTP, and the
  GitHub server reads its token from `gh auth token` at launch.
- 2026-09-24: Added opt-in `cliUpdates`: a daily user timer (04:30) that
  installs the npm-global `claude` and `codex` at `@latest` and logs each
  version change. It alerts through `hwc-notify` once on failure and once on
  recovery. It is on for hwc-server only, where nothing else updated them. On
  2026-09-24 claude 2.1.274 hid Opus 5.5 in T3, which needs 2.1.280.
  `bash` is on the unit's PATH because npm runs lifecycle scripts through `sh`.
- 2026-09-22: Unified store and pre-write memory validation behind
  `agent-state-validate memory-stdin`. Repeated invalid state now exits 75 from
  one fixed-size case projection without rerunning validation or touching the
  network; content changes retry, and only block/recovery transitions notify.
- 2026-09-17: Added the ownership manifest, changed-memory schema gate, fleet
  doctor, managed static-policy commit hook, and a publication command with a
  location-independent preflight and a Bash-owned final doctor handoff. The state service invokes its packaged
  validator directly so its minimal systemd `PATH` is sufficient. Sync failure
  and recovery alerts are emitted once per transition through `hwc-notify`.
- 2026-09-17: Added the shared control plane, separate mutable state sync,
  machine-wide Claude settings, provider health checks, and interactive CLI.
- 2026-09-17: Quoted interactive command assignments for shellcheck compliance.
- 2026-09-17: Replace stale memory symlinks during the state-store cutover.
- 2026-09-17: Publish static policy through private GitHub so both root evaluators can fetch it.
