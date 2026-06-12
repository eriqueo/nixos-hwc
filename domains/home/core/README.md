# Home Core

## Purpose
Foundational Home Manager configuration shared across all apps: the CLI
environment and user directory layout.

## Boundaries
- Manages: shell/CLI env (`hwc.home.core.shell.*`), development toolchains
  (`hwc.home.core.development.*`), XDG user directories.
- Does NOT manage: app-specific config → `apps/`, theming → `theme/`.

## Structure
```
core/
├── index.nix          # Aggregator
├── shell/             # hwc.home.core.shell — zsh, aliases, fzf, starship,
│   ├── index.nix      #   git, ssh, MCP config (options + wiring)
│   └── parts/         #   aliases, ssh, zsh-init, prompt, fzf
├── development/       # hwc.home.core.development — language toolchains
└── xdg-dirs.nix       # XDG user directory layout (000_inbox, 100_hwc, …)
```

## Changelog
- 2026-06-11: Structure section updated to reality (shell/ and development/
  are directories; namespaces moved under hwc.home.core.* per Law 2; the
  phantom options.nix/shell.nix flat files are gone).
- 2026-06-11: `core/shell/index.nix` — `aliases` option default flipped to `{}` so per-machine definitions *merge* over the base set from `parts/aliases.nix` instead of silently replacing it (`1a78f22d`). Fixes the laptop SUPER+E aerc keybind regression that surfaced the bug.
