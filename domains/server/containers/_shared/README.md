# Container Shared Infrastructure

## Purpose

Shared container directory structures (tmpfiles rules).

## Structure

```
_shared/
├── README.md        # This file
└── directories.nix  # Shared directory structures (tmpfiles)
```

Container helper functions (`mkContainer`, `mkInfraContainer`, `mkArrConfigScript`)
live in `lib/` at the repo root. All container modules import from `lib/` directly.

## Changelog

- 2026-03-04: Deleted re-export shims (pure.nix, infra.nix, arr-config.nix) — all callers now use lib/ directly
- 2026-03-04: Extracted pure helpers to lib/ at repo root
- 2026-02-28: Initial creation
