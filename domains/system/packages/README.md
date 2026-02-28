# System Packages

## Purpose
Machine-specific system package sets.

## Boundaries
- Manages: Server-specific packages, machine-targeted package lists
- Does NOT manage: User packages → `home/`, base packages → `core/packages.nix`

## Structure
```
packages/
└── server.nix    # Server-specific system packages
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
