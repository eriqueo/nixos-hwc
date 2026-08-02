# claude-code

## Purpose
Installs the Claude Code CLI (Nix package + Obsidian MCP cert trust) and, independently, symlinks the shared `~/.claude-config` git repo (skills/agents/commands/CLAUDE.md/engineering-principles) into `~/.claude/` so all hosts share one config. Enable via `hwc.home.apps.claude-code.enable`; `shareConfig.enable` can be turned on standalone (e.g. hwc-server, which runs claude from npm).

## Boundaries
- ✅ `pkgs.claude-code`, `NODE_EXTRA_CA_CERTS` pointing at the Obsidian Local REST API cert, `mkOutOfStoreSymlink` links for `shareConfig.items`, optional `claude-config-pull` user service+timer (ff-only pull, default 15min), append-only self-heal of the four gate-hook entries into `~/.claude/settings.json` at activation (`shareConfig.wireGateHooks`).
- ❌ Does not manage the claude-config repo contents or clone it; does not touch host-local `~/.claude/{plans,docs,memory}`; never auto-commits/pushes the config repo; never edits or removes existing settings.json entries (heal is append-only — Claude Code stays the file's primary writer).

## Structure
- `index.nix` — options (`enable`, `shareConfig.{enable,repoPath,items,autoPull,wireGateHooks}`), package + cert var, symlink generation, auto-pull timer, settings.json gate-hook heal activation, assertions.

## Changelog
- 2026-08-02: `shareConfig.wireGateHooks` (default true) — home.activation jq-merges the four gate-hook entries (enforce-tools, premortem-gate, track-evidence ×2, claim-guard) plus `SLASH_COMMAND_TOOL_CHAR_BUDGET` into `~/.claude/settings.json`, append-only and idempotent, keyed on script filename, pre-heal backup kept. Supersedes the 2026-07-19 "wiring remains per-host by design" stance: hwc-server was found scripts-present-but-unwired on 2026-08-02, so per-host hand wiring demonstrably rots. principles-lint.sh Check 4 (claude-config `935f040`) independently verifies the same five points each session.
- 2026-07-29: `shareConfig.items` gains `hooks/principles-lint.sh` — the digest drift check named in the principles doc's Appendix C (rev 3). Invoked loud-but-non-fatal at the top of principles-primer.sh; the primer also gains Part VI genre injection (`HWC_SESSION_GENRE=create|fix|ops|docs` selects a digest subset; unset/unknown → full primer, unchanged behavior).
- 2026-07-19: `shareConfig.items` gains `hooks/principles-{primer,gate}.sh` as per-file symlinks — the principle-enforcement hooks now ride claude-config to every host (whole `hooks/` dir stays unmanaged: it holds host-local hooks like herdr-agent-state.sh). settings.json PreToolUse wiring remains per-host by design.
- 2026-07-09: `claude-config-pull` ExecStart now fetches then `merge --ff-only @{u}`, treating a diverged/ahead/dirty tree as a clean no-op (exit 0) instead of `pull --ff-only`'s exit-128 failure every interval — was generating ~96 failed-oneshot journal errors/day under `user@1000.service`.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
