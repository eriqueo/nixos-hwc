# System Core

## Purpose
Foundational system configuration: identity, filesystem structure, boot, and cross-cutting defaults.

## Boundaries
- Manages: User identity (PUID/PGID), tmpfiles structure, thermal management, boot config
- Does NOT manage: Networking → `networking/`, user accounts → `users/`

## Structure
```
core/
├── authentik/       # SSO/Identity Provider (hwc.system.core.authentik.*)
│   ├── index.nix
│   └── parts/
│       └── config.nix
├── identity/        # User identity options (puid, pgid, user, group) - inlined
├── filesystem.nix   # Filesystem structure via tmpfiles
├── index.nix        # Core aggregator
├── packages.nix     # Base system packages
├── thermal.nix      # Thermal/power management
└── validation.nix   # Cross-cutting assertions
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
- 2026-03-12: Inlined options.nix into index.nix for identity, polkit, session, shell; removed separate options.nix files
- 2026-03-26: Added Authentik SSO/Identity Provider module
