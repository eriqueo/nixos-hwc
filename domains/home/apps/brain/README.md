# brain

## Purpose
Puts `brain` on PATH — the vault janitor/fixer CLI (`units`, `check`, `sweep`, `fix`, `resolve`, `charter`, `log`). A Nix wrapper exports `BRAIN_VAULT` and execs the pre-built `dist/bin/brain.js` from the checkout at `~/600_apps/brain`. Nix supplies the environment; it never builds the app. Enable via `hwc.home.apps.brain.enable`.

The module exists because the documented name and the usable name disagreed. `package.json` declares `bin.brain` and the repo README documents every command as `brain <cmd>`, but no such executable was on PATH on either machine until 2026-08-27 — every real invocation had to be `node .../dist/bin/brain.js`.

## Boundaries
- ✅ The `brain` wrapper: exports `BRAIN_VAULT`, supplies the three binaries the CLI shells out to (`git` for `commitFixes`, `flock` for the vault's shared `.sync.lock`, `du` for the `.stversions` measurement), and fails loud with the clone+build command when `dist/bin/brain.js` is absent.
- ❌ Does not build, clone, or update the checkout (that is `deploy.sh` in the app repo); does not own the check logic or the trip thresholds (the app repo and `_charter/janitor.md` do); does not schedule the nightly sweep (`hwc.automation.brainSweep`, system lane).

## Structure
- `index.nix` — enable option, `repoDir`/`vaultDir` options, the wrapper, package install.

## Sibling modules ruled out
- `domains/automation/brain-sweep` — closest fit, and it already declares `repoDir`/`vaultDir` for this same checkout. Rejected on Law 16: it is the system lane, a timer running one subcommand as a service. `brain` is an interactive command and needs `home.packages`. The duplicated defaults are deliberate; promote to `domains/paths` if a third consumer appears.
- `domains/home/apps/doctl` — wraps a nixpkgs binary and injects an agenix secret. `brain` has neither.
- `domains/home/apps/dxlog` — nearest in shape, but it vendors its script into this repo. The brain CLI's code lives outside the repo and must not be copied in.
- `domains/home/core/shell` — declares an `mcp.brain` entry. That is the brain MCP HTTP server, a different artifact. No name collision.

## Changelog
- 2026-08-27: Module added. Enabled on laptop + server only, not in the base role — the CLI needs the `~/600_apps/brain` checkout and the vault, which the other three hosts lack.
