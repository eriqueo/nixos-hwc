# Repository Guidelines

## Project Structure & Module Organization
Repo drives the HWC NixOS deployment. `flake.nix` pins inputs and exports `nixosConfigurations`; `machines/<host>/` holds host facts and imports profiles. Modules live in `domains/<domain>/<concern>/index.nix`, and each folder must mirror its `hwc.*` namespace. Profiles in `profiles/` keep `BASE` and `OPTIONAL FEATURES` banners. Secrets stay encrypted as `.age` files in `domains/secrets/parts/`. Use `docs/` for reference material and `workspace/` for automation, lints, and utilities.

## Build, Test, and Development Commands
- `nix flake check` — evaluates every system and module; run before pushing.
- `sudo nixos-rebuild test --flake .#hwc-laptop` (or `hwc-server`) — stage changes without switching.
- `sudo nixos-rebuild switch --flake .#hwc-laptop` — apply confirmed changes on the target host.
- `./workspace/utilities/lints/charter-lint.sh domains/system --fix` — enforce charter rules; swap the path per domain and omit `--fix` for CI.

## Coding Style & Naming Conventions
Use two-space indentation and keep attributes aligned within the banner blocks. Preserve the chartered order (`# IMPORTS`, `# IMPLEMENTATION`, `# VALIDATION`, etc.) and move option declarations into sibling `options.nix` files. Module identifiers follow `hwc.<domain>.<category>.<module>` to mirror the folder path; match commit scopes to the same pattern. Keep filenames lowercase-hyphenated and comments instructional. Only run formatters already established for the touched module.

## Testing Guidelines
Every module must assert its dependencies in `# VALIDATION` so misconfigurations fail builds, not switches. When adding toggles, exercise them in a staging machine file under `machines/`. Smoke-test with `nixos-rebuild test` before `switch`, and place runtime probes in `workspace/automation/` only when needed. Keep `nix flake check` and the charter lint green before requesting review.

## Commit & Pull Request Guidelines
Follow the conventional-commit pattern from history, e.g., `fix(home.apps.firefox): clarify profile defaults`. Keep the scope aligned with the module path touched and split unrelated changes into separate commits. PRs must summarize the impact, list the rebuild command executed, flag new secrets or migrations, and link related docs. Attach screenshots or logs when altering UI-facing services such as Hyprland or Waybar, and wait for review plus green CI before merging.

## Security & Configuration Tips
Never commit decrypted material; store secrets as `.age` artifacts and document rotation steps in `docs/infrastructure/`. Keep hardened workloads in `domains/server/containers/` unless host access is mandatory. When unsure about boundaries, consult `CHARTER.md` and favor reorganizing modules over rewriting them.
