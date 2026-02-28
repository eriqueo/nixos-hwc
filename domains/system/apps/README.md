# System Apps

## Purpose
System-level application support for Home Manager apps requiring NixOS configuration.

## Boundaries
- Manages: sys.nix companions for home apps (Hyprland, Waybar system deps)
- Does NOT manage: User-space app config → `home/apps/`

## Structure
```
apps/
└── (sys.nix modules imported from home/apps/*/sys.nix)
```

## Changelog
- 2026-02-28: Added README for Charter Law 12 compliance
