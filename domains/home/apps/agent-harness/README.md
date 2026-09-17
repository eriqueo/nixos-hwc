# Agent harness

The agent harness gives Claude Code, Codex, Pi, T3, and Herdr one static policy
source and one mutable state store.

## Structure

- `index.nix` installs the pinned policy, state links, health CLI, and user timer.
- `sys.nix` installs machine-wide Claude policy under `/etc`.
- `contract.nix` defines the ownership and revision contract shared by both lanes.
- `control.sh` implements local and fleet health checks plus policy publication.
- `control.test.sh` seeds split revisions and mutable runtime references against the doctor.
- `state-sync.sh` synchronizes only memories and the mistakes ledger.
- `state-validate.sh` validates state ownership and changed memories.
- `state-sync.test.sh` verifies import, links, commit, pull, and push against a throwaway hub.

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

The doctor verifies actual provider paths, system and Home Manager ownership
manifests, state shape, Codex hook trust, commands, and the sync timer. A dirty
authoring checkout is a warning; a runtime reference to it is a failure.

## Changelog

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
