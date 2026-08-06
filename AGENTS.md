# nixos-hwc

NixOS flake managing the HWC fleet — hwc-laptop (Hyprland desktop) and
hwc-server (headless: Podman, Caddy, monitoring, media). Charter v12.4:
domains = capabilities, profiles = roles, machines = instances. Read
`CHARTER.md` before architectural work; each domain's `README.md` carries
its structure and changelog.

## Build & gate
- Commit BEFORE building. The tracked `.githooks/pre-commit` runs the nine
  charter-law checks (`core.hooksPath` is pinned there by activation);
  reproduce one with `nix build --no-link .#checks.x86_64-linux.charter-law<N>`.
  `nix flake check` runs them all — `--no-build` does NOT.
- Two activation lanes; run `hostname` first and state which lane applies:
  - HM-only (`domains/home/`, `profiles/*/home.nix`, `machines/*/home.nix`)
    → `hms` (fast, no sudo).
  - System or mixed → `sudo nixos-rebuild switch --flake .#hwc-<host>`.
  Don't alternate lanes casually — each keeps its own HM generation and
  will trip "existing file in the way" on files the other placed.
- A build without a switch changes nothing; never report "live" from a build.

## Rules no lint catches yet
- Secrets: `group = "secrets"; mode = "0440"`.
- Native services need `User = lib.mkForce "eric"`; container PGID is 100.
- Ports: check `domains/networking/routes.nix` before claiming one.
- Paths come from `config.hwc.paths.*` (`domains/paths/paths.nix`).

## On commit
Update the touched domain's `README.md` (`## Structure` + `## Changelog`)
in the same commit. Feature work lives in `~/.nixos-worktrees/<name>`;
this checkout stays on `main`.
