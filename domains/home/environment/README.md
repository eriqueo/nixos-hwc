# Home Environment

## Purpose
Shell environment, aliases, and development tooling.

## Boundaries
- Manages: Shell config, environment variables, dev tools (direnv, starship)
- Does NOT manage: System shell → `system/services/shell/`

## Structure
```
environment/
├── index.nix    # Environment configuration
└── options.nix  # Environment options
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
