# System Hardware

## Purpose
Hardware acceleration and driver configuration for GPU, display, and compute workloads.

## Boundaries
- Manages: GPU drivers (NVIDIA/Intel/AMD), hardware acceleration, container GPU passthrough
- Does NOT manage: Audio/peripherals → `services/hardware/`, storage devices → `storage/`

## Structure
```
hardware/
├── gpu/
│   └── index.nix      # GPU driver implementation (options inlined)
├── index.nix          # Auto-discovery aggregator
└── services/
    └── index.nix      # Hardware services implementation (options inlined)
```

## Changelog
- 2026-02-28: Created from infrastructure domain migration (Charter v10.5)
- 2026-03-12: Inlined options.nix into index.nix for gpu and services; removed separate options.nix files
