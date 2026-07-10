# claude-code

## Purpose
Installs the Claude Code CLI (Nix package + Obsidian MCP cert trust) and, independently, symlinks the shared `~/.claude-config` git repo (skills/agents/commands/CLAUDE.md/engineering-principles) into `~/.claude/` so all hosts share one config. Enable via `hwc.home.apps.claude-code.enable`; `shareConfig.enable` can be turned on standalone (e.g. hwc-server, which runs claude from npm).

## Boundaries
- ✅ `pkgs.claude-code`, `NODE_EXTRA_CA_CERTS` pointing at the Obsidian Local REST API cert, `mkOutOfStoreSymlink` links for `shareConfig.items`, optional `claude-config-pull` user service+timer (ff-only pull, default 15min).
- ❌ Does not manage the claude-config repo contents or clone it; does not touch host-local `~/.claude/{plans,docs,memory}`; never auto-commits/pushes the config repo.

## Structure
- `index.nix` — options (`enable`, `shareConfig.{enable,repoPath,items,autoPull}`), package + cert var, symlink generation, auto-pull timer, assertions.

## Changelog
- 2026-07-09: `claude-config-pull` ExecStart now fetches then `merge --ff-only @{u}`, treating a diverged/ahead/dirty tree as a clean no-op (exit 0) instead of `pull --ff-only`'s exit-128 failure every interval — was generating ~96 failed-oneshot journal errors/day under `user@1000.service`.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
