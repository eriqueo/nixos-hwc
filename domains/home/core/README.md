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
- 2026-07-06: shell/parts/aliases.nix — repointed the `web-build` alias from
  the in-repo `domains/business/website/site_files` to `/opt/business/website-site`
  (swept in with the fleet-wide gotify decommission commit).
- 2026-06-26: shell/parts/ssh.nix — set `enableDefaultConfig = false` on the
  stable (HM 25.11) branch to silence the `programs.ssh` default-values
  deprecation; the `matchBlocks."*"` block already replicates HM's defaults.
- 2026-06-11: Structure section updated to reality (shell/ and development/
  are directories; namespaces moved under hwc.home.core.* per Law 2; the
  phantom options.nix/shell.nix flat files are gone).
