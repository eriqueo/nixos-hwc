# Repository Guidelines

- Always align with the latest `CHARTER.md`; if in doubt, read it first and re-check for updates after changes.

## Project Structure & Module Organization
- Root `flake.nix` defines inputs/outputs and delegates to machine configs in `machines/*/config.nix` with matching `hardware.nix` per host.
- Domain modules live under `domains/*/` (e.g., `domains/server`, `domains/home`, `domains/secrets`); keep logic and options inside the relevant domain to avoid cross-coupling.
- Profiles in `profiles/*.nix` compose common stacks (base, security, media, ai, infrastructure). Extend profiles rather than duplicating options.
- Workspace scripts sit in `workspace/` (purpose-driven directories like `nixos/`, `monitoring/`, `hooks/`, `diagnostics/`); Tier 1 shell derivations in `domains/home/environment/shell/parts/` wrap these scripts.
- Repository scripts for maintenance and lints live in `scripts/`; see `scripts/lints/` for Charter and container checks.

## Build, Test, and Development Commands
- `nixos-rebuild test --flake .#hwc-laptop` (or `.#hwc-server`): dry-run system build and activate in a disposable generation.
- `nixos-rebuild switch --flake .#hwc-laptop`: build and switch the target host.
- `nix flake check`: run flake-level evaluations; use before commits.
- `./scripts/lints/charter-lint.sh`: verify Charter/module structure and lane purity.
- `./scripts/lints/container-lint.sh [--verbose] [name]`: validate container configs; run per-container, then full pass.
- For editing Tier 2 scripts, run directly from `workspace/...` (no rebuild); for Tier 1 commands, regenerate via `nixos-rebuild` after edits.

## Coding Style & Naming Conventions
- Nix files use 2-space indentation, lowercase attr names, and prefer `lib.mkIf`/`lib.mkDefault` patterns already in `domains/*/index.nix`.
- Module anatomy: keep `index.nix` (wiring), `options.nix` (interfaces), and `sys.nix` or `parts/` (implementation) aligned with Charter expectations; avoid mixing Home Manager logic in NixOS modules.
- Shell/Python scripts: shebang plus `set -euo pipefail` (bash) and clear usage output; place scripts in the correct workspace directory by purpose.
- Path canon: all filesystem paths defined in `domains/system/core/paths.nix` and consumed via `config.hwc.paths.*`; no hardcoded `/mnt`/`/opt` defaults except as explicit fallbacks.
- Permission model: services/containers run as `eric:users` (UID 1000/GID 100), containers use `PUID=1000`/`PGID=100`, secrets via `group = "secrets"` and `mode = "0440"`.
- Lane purity: system/home lanes stay separate; `sys.nix` lives with modules but exposes system-lane options under `hwc.system.*`; Home can assert system via `osConfig`, never the reverse.
- Validation: every toggleable module needs a `# VALIDATION` section with assertions for required dependencies.
- Complex services use config-first pattern: keep canonical YAML/TOML under `domains/server/<svc>/config/`, mount via Nix; Nix handles infra (image, mounts, env, ports) only.
- Data retention is declarative: define retention policies in Nix with fail-safe systemd timers; back up only critical/irreplaceable data.

## Testing Guidelines
- Prefer `nix flake check` before rebuilds; follow with `nixos-rebuild test` on the target host to catch activation issues.
- Run `./scripts/lints/charter-lint.sh` after adding or moving modules; run `./scripts/lints/container-lint.sh` whenever touching `domains/server/containers/*`.
- Name new tests/lints descriptively and keep outputs under `.lint-reports/` if applicable.

## Commit & Pull Request Guidelines
- Commit style follows Conventional Commit flavor seen in history: `fix(scope): description`, `refactor(scope): ...`, `feat(scope): ...`; keep scope aligned to domain or host (e.g., `server.containers`, `laptop`, `home.mail`).
- Commits should be small and reversible; include relevant lints/builds in the body if non-obvious.
- PRs: describe the change, affected hosts/profiles, and commands run (`nix flake check`, lints, rebuild). Link issues where applicable; include config diffs or screenshots for UI-facing changes (rare here).

## Security & Secrets
- Never commit secrets; use agenix files in `domains/secrets/` and follow `domains/secrets/SECRETS-MANAGEMENT-GUIDE.md`.
- Keep secrets wiring isolated to the secrets domain; reference age files rather than embedding credentials in modules or scripts.
