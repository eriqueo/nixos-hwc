# Agent harness

The agent harness gives Claude Code, Codex, Pi, T3, and Herdr one static policy
source and one mutable state store.

## Structure

- `index.nix` installs the pinned policy, state links, health CLI, the state-sync timer, and the opt-in `agent-cli-update` timer.
- `sys.nix` installs machine-wide Claude policy under `/etc`, and generates the nixos repo's `.mcp.json` (`projectMcp`): a tmpfiles store symlink with the shared servers, `hwc-sys` over HTTP at `hwc.system.mcp.url`, and per-host `extraServers`.
- `contract.nix` defines the ownership and revision contract shared by both lanes.
- `control.sh` implements local and fleet health checks plus policy publication.
- `control.test.sh` seeds split revisions and mutable runtime references against the doctor.
- `state-sync.sh` synchronizes only memories and the mistakes ledger, with one bounded validation case under `.git`.
- `state-validate.sh` owns the memory contract for both full-store scans and projected writes on stdin.
- `state-sync.test.sh` verifies import, links, validation blocking, recovery, commit, pull, and push against a throwaway hub.

## State ownership

Nix pins static instructions, skills, hooks, and provider adapters. The Git clone
at `~/.agent-state` holds mutable memories and `MISTAKES.md`. Project repositories
still own their local `AGENTS.md` or `CLAUDE.md` files.

New or changed memories declare `authority: observation|reference|decision` and
a non-empty `source:`. Standing policy belongs in the static harness or a
project repository and is rejected from changed memory files.

The private `eriqueo/claude-config` GitHub repository publishes static revisions
for both root evaluators. The server bare repository remains an authoring mirror.

## Operations

Run `agent-harness` for the interactive menu. Session launchers run the local
doctor automatically. `agent-harness doctor --fleet` compares both hosts with
the local desired revision. `agent-harness publish` checks and pushes static
policy, updates the Nix pin, builds and switches both hosts, and finishes with
the fleet doctor. `agent-harness sync` validates and synchronizes mutable state.

On a host with `cliUpdates.enable`, `agent-cli-update` runs daily. Run it by
hand with `systemctl --user start agent-cli-update`. Read the version changes
with `journalctl --user -u agent-cli-update`. To roll back a bad release, run
`npm install -g <package>@<previous version>` with the version from that log.

The doctor verifies actual provider paths, system and Home Manager ownership
manifests, state shape, Codex hook trust, commands, and the sync timer. A dirty
authoring checkout is a warning; a runtime reference to it is a failure.

## Changelog

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
