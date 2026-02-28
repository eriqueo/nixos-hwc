# System Virtualization

## Purpose
Virtual machine and container orchestration infrastructure.

## Boundaries
- Manages: QEMU/KVM, libvirtd, Podman, SPICE, WinApps Windows integration
- Does NOT manage: Container workloads → `server/containers/`, GPU passthrough config → `hardware/gpu/`

## Structure
```
virtualization/
├── winapps/
│   ├── index.nix           # WinApps RDP integration
│   ├── options.nix         # WinApps settings
│   └── parts/              # Helper scripts
│       ├── install-winapps.sh
│       ├── vm-manager.sh
│       └── winapps-helper.sh
├── index.nix               # Virtualization implementation
└── options.nix             # Virtualization options
```

## Changelog
- 2026-02-28: Created from infrastructure domain migration (Charter v10.5)
