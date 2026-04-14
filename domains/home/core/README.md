# Home Core

## Purpose
Foundational Home Manager configuration shared across all apps.

## Boundaries
- Manages: Home Manager base settings, XDG directories, session variables
- Does NOT manage: App-specific config → `apps/`, theming → `theme/`

## Structure
```
core/
├── index.nix    # Core home configuration
└── options.nix  # Core home options
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
