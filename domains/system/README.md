# System Domain

## Scope & Boundary
- Core OS lane: accounts, networking, filesystem scaffolding, base services, and packages other domains rely on.
- Namespaces match paths (`hwc.system.*`, `hwc.filesystem.*` shortcut for core/filesystem) per Charter Law 2.
- No Home Manager logic lives here; cross-lane assertions are guarded so the system lane stands alone.

## Layout
```
domains/system/
├── core/
│   ├── filesystem.nix    # Filesystem tmpfiles; options at hwc.system.core.filesystem (alias: hwc.filesystem)
│   ├── packages.nix      # Base/server/security package bundles (hwc.system.core.packages.*)
│   ├── paths.nix         # Path source of truth (hwc.paths.*)
│   ├── polkit.nix (moved to services/polkit)
│   ├── thermal.nix
│   └── validation.nix    # Domain-wide assertions
├── services/
│   ├── backup/           # Backup timers/services
│   ├── hardware/         # Input/audio/system behavior
│   ├── monitoring/       # Prometheus/node-exporter/etc. hooks
│   ├── networking/       # Network stack helpers (per Charter exception: hwc.networking)
│   ├── ntfy/             # ntfy relay service
│   ├── protonmail-bridge/        # Proton Bridge service lane
│   ├── protonmail-bridge-cert/   # Certificate helper for Proton Bridge
│   ├── session/          # Display/login/session policies
│   ├── shell/            # System shell defaults
│   └── vpn/              # VPN client/service wiring
├── storage/              # Storage-tier policies and retention helpers
└── users/                # Account and group management
```

## Subdomain Notes
- **filesystem.nix** – Creates tmpfiles scaffolding from `hwc.paths.*` plus extra dirs (`hwc.filesystem.structure.dirs` alias).
- **services/** – Backup, monitoring, networking, polkit, ntfy, VPN, Proton Bridge, session, shell, and hardware behavior live here. Each subdirectory exposes its own options under `hwc.system.services.<name>.*` (or Charter-approved short names).
- **storage/** – Houses storage policy modules (tiers, cleanup/retention timers) to satisfy the data retention contract.
- **packages.nix** – Core package bundles (base/server/security) under `hwc.system.core.packages.*`.
- **users/** – System-level accounts required by other domains.

## Usage
- Import `domains/system/index.nix` from machine configs; enable modules via `hwc.system.*` and `hwc.filesystem.*` options.
- Keep home-lane references guarded with `osConfig ? hwc` per the Handshake Protocol when mirrored into `sys.nix` files elsewhere.
