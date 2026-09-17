# herdr

## Purpose
Installs herdr, a terminal agent multiplexer ("tmux for AI agents"). Since herdr is not in nixpkgs, the module packages the upstream x86_64-linux release binary itself via `parts/package.nix` (fetchurl + autoPatchelfHook), with a `package` option to substitute a different build.

## Boundaries
- ✅ Manages: the herdr package on `home.packages`; `hwc.home.apps.herdr.enable` and an optional `package` override (null → build from upstream release binary).
- ✅ Reconciles Herdr's Claude and Pi status integrations at activation.
- ❌ Does not rewrite Codex's Nix-owned hooks file; that file already carries Herdr's status hook.
- ❌ Does not manage: agent policy or state; the agent-harness module owns those.

## Structure
- `index.nix` — options (`enable`, `package`), installs the resolved package, asserts it is non-null.
- `parts/package.nix` — derivation wrapping the upstream v0.8.2 release binary (patchelf'd, installed to `bin/herdr`).

## Changelog

- 2026-09-17: Stop asking Herdr to rewrite the Nix-owned Codex hooks file; Claude and Pi remain reconciled by Herdr.
- 2026-09-17: Reconcile Claude, Codex, and Pi integrations at every activation.
- 2026-08-30: bumped `parts/package.nix` from v0.6.2 to v0.8.2 (upstream latest stable, released 2026-08-19). Version string + `hash` only; derivation shape unchanged.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
