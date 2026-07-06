# tuxedo

## Purpose
Installs tuxedo, the keyboard-driven todo.txt TUI (webstonehq/tuxedo), built
from the upstream release binary since it is not in the pinned nixpkgs. Sets
todo.txt-cli environment variables and seeds a writable config.

## Boundaries
- ✅ `hwc.home.apps.tuxedo.enable`; `package` override; `todoDir` (default `~/000_inbox/todo`) exported as `TODO_DIR`/`TODO_FILE`/`DONE_FILE`
- ✅ Activation creates todo dir + files and seeds `~/.config/tuxedo/config.toml` once — copy, not store symlink, because tuxedo rewrites it at runtime
- ❌ Does not manage config.toml after seeding — tuxedo owns UI state (theme, sort, saved searches)
- ❌ Not `tuxedo-rs` (the unrelated hardware daemon in nixpkgs)

## Structure
- `index.nix` — options, env vars, activation seeding, package assertion
- `parts/package.nix` — autoPatchelf derivation of the upstream release tarball
- `parts/config.nix` — seed contents for the writable config.toml

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
