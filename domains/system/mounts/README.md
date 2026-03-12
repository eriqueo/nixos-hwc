# System Storage

## Purpose
Storage tier management for hot, media, and backup volumes.

## Boundaries
- Manages: Mount points, tmpfiles rules, external drive auto-mount, storage tier organization
- Does NOT manage: Path abstractions → `domains/paths/`, backup jobs → `services/borg/`

## Structure
```
mounts/
└── index.nix    # Storage implementation (mounts, udev, tmpfiles) with options inlined
```

## Changelog
- 2026-02-28: Merged storage tiers from infrastructure domain (Charter v10.5)
- 2026-03-12: Inlined options.nix into index.nix; removed separate options.nix
