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
│   ├── index.nix      # GPU driver implementation
│   └── options.nix    # GPU options (type, accel, nvidia/intel settings)
├── index.nix          # Auto-discovery aggregator
└── options.nix        # Hardware root options
```

## Changelog
- 2026-02-28: Created from infrastructure domain migration (Charter v10.5)
