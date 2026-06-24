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
- 2026-06-22: Shell — gate prompt re-bake on interactive shell in snix/tnix/hms; rebind starship after rebuild (not just hash -r); use HOME=/root not ~root in _hwc_rebuild; add `wb-reload` alias to re-apply workbench layout edits. MCP — run git/time/fetch via uvx, drop brave-search. Workbench — SUPER+W keybind + `workbench` alias. Aerc — SUPER+E keybind fix (hwc→server); alias `aerc` to server aerc on laptop.
