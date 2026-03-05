# System Storage

## Purpose
Storage tier management for hot, media, and backup volumes.

## Boundaries
- Manages: Mount points, tmpfiles rules, external drive auto-mount, storage tier organization
- Does NOT manage: Path abstractions → `domains/paths/`, backup jobs → `services/borg/`

## Structure
```
storage/
├── index.nix    # Storage implementation (mounts, udev, tmpfiles)
└── options.nix  # Storage tier options (hot/media/backup)
```

## Changelog
- 2026-02-28: Merged storage tiers from infrastructure domain (Charter v10.5)
