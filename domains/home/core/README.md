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
- 2026-05-21: shell.nix — promoted `hms` from alias to shell function. Now forwards extra args to `nix build`, runs `hash -r` after activation, and auto-runs `hyprctl reload` when invoked inside a Hyprland session so HM-touched hyprland.conf takes effect without a manual second step
- 2026-05-21: shell.nix — extended the same `hash -r` + `hyprctl reload` tail to `snix` and `tnix` (both activate HM-as-module via home-manager-eric.service, oneshot so the config is on disk by the time the command returns). `bnix` left alone — it only builds, no activation
- 2026-05-21: shell.nix — fix broken `add-zsh-hook precmd hash -r` line (printed `Usage: add-zsh-hook hook function` every new shell). add-zsh-hook needs a function name, not a command. Wrapped `hash -r` in `_hwc_hash_refresh()` and registered that instead
