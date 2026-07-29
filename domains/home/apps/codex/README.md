# codex

## Purpose
Installs the OpenAI Codex CLI (stock `pkgs.codex` by default, overridable via `package`), optional extra session env vars, and creates the `~/.config/codex/` directory. Enable via `hwc.home.apps.codex.enable`.

## Boundaries
- ✅ Package selection with null-check assertion, `env` → `home.sessionVariables`, `codex/.keep` config-dir placeholder. `parts/package.nix` is an opt-in pin of the upstream 0.146.0 static-musl release binary for machines that set `package = pkgs.callPackage ./parts/package.nix { }`.
- ❌ Does not manage API keys/auth or any `config.toml` contents inside `~/.config/codex/`; the pinned package is NOT the default (server intentionally uses stock pkgs.codex).

## Structure
- `index.nix` — options (`enable`, `package`, `env`), install, config dir, assertion.
- `parts/package.nix` — optional pinned codex 0.146.0 derivation from the upstream static-musl release tarball.

## Changelog
- 2026-07-29: `parts/package.nix` bumped 0.101.0 → 0.146.0. Upstream flipped the x86_64-linux asset from dynamic `-gnu` to static-pie `-musl`, so the `-musl` URL + new sha256, the `mv` source rename, and dropping `autoPatchelfHook` + glibc/openssl/zlib/libcap inputs all moved together. 0.146 supports the gpt-5.6 Sol/Terra/Luna models. HM-only (laptop pin) → `hms`.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
