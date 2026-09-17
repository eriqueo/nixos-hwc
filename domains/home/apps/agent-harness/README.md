# Agent harness

The agent harness gives Claude Code, Codex, Pi, T3, and Herdr one static policy
source and one mutable state store.

## Structure

- `index.nix` installs the pinned policy, state links, health CLI, and user timer.
- `sys.nix` installs machine-wide Claude policy under `/etc`.
- `state-sync.sh` synchronizes only memories and the mistakes ledger.
- `state-sync.test.sh` verifies import, links, commit, pull, and push against a throwaway hub.

## State ownership

Nix pins static instructions, skills, hooks, and provider adapters. The Git clone
at `~/.agent-state` holds mutable memories and `MISTAKES.md`. Project repositories
still own their local `AGENTS.md` or `CLAUDE.md` files.

## Operations

Run `agent-harness` for the interactive menu. Run `agent-harness doctor` before
starting a T3 or Herdr session. Run `agent-harness sync` for immediate state sync.

## Changelog

- 2026-09-17: Added the shared control plane, separate mutable state sync,
  machine-wide Claude settings, provider health checks, and interactive CLI.
