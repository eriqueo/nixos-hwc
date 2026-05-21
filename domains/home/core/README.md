# Home Core

## Purpose
Foundational Home Manager configuration shared across all apps.

## Boundaries
- Manages: Home Manager base settings, XDG directories, session variables
- Does NOT manage: App-specific config → `apps/`, theming → `theme/`

## Structure
```
core/
├── index.nix        # Core home aggregator
├── options.nix      # Core home options
├── shell.nix        # zsh/bash/git, aliases, sn/tn/bnix rebuild helpers, modern-unix tools
├── development.nix  # Language toolchains (js, etc.)
└── xdg-dirs.nix     # XDG user directory layout
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-05-21: shell.nix — add `hash -r` zsh precmd hook to refresh command hash table after every prompt. Fixes the recurring `zsh: no such file or directory: ~/.nix-profile/bin/<tool>` issue triggered by HM-as-module activation wiping the legacy nix-env user profile (this host runs both HM-as-module via `snix` and HM-as-flake via `hms`)
