# codex

## Purpose
Installs the OpenAI Codex CLI (stock `pkgs.codex` by default, overridable via `package`), optional extra session env vars, creates the `~/.config/codex/` directory, and exposes selected cross-harness skills from the shared `~/.claude-config/skills` source through `~/.codex/skills` symlinks. Enable via `hwc.home.apps.codex.enable`.

## Boundaries
- ✅ Package selection with null-check assertion, `env` → `home.sessionVariables`, `codex/.keep` config-dir placeholder, and selected out-of-store skill symlinks from one shared source. `parts/package.nix` is an opt-in pin of the upstream 0.146.0 static-musl release binary for machines that set `package = pkgs.callPackage ./parts/package.nix { }`.
- ❌ Does not manage API keys/auth or any `config.toml` contents inside `~/.config/codex/`; the pinned package is NOT the default (server intentionally uses stock pkgs.codex).

## Structure
- `index.nix` — options (`enable`, `package`, `env`, shared skill source/list), install, config dir, selected skill symlinks, assertion.
- `parts/package.nix` — optional pinned codex 0.146.0 derivation from the upstream static-musl release tarball.

## Changelog
- 2026-08-31: Exposed the shared `delegate` skill to Codex alongside Herdr and Project Director, enabling bounded native Claude Code, Codex, and DX1 workers from T3 sessions that lack Herdr pane context. HM-only → `hms`.
- 2026-08-31: Added `sharedSkillSource` plus the selected `herdr` and `project-director` skill symlinks under `~/.codex/skills`; Claude and Codex now consume one source rather than copied orchestration instructions. HM-only → `hms`.
- 2026-07-29: `parts/package.nix` bumped 0.101.0 → 0.146.0. Upstream flipped the x86_64-linux asset from dynamic `-gnu` to static-pie `-musl`, so the `-musl` URL + new sha256, the `mv` source rename, and dropping `autoPatchelfHook` + glibc/openssl/zlib/libcap inputs all moved together. 0.146 supports the gpt-5.6 Sol/Terra/Luna models. HM-only (laptop pin) → `hms`.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
