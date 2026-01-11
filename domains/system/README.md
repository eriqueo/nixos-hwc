# System Domain

## Scope & Boundary
- Core OS lane: accounts, networking, filesystem scaffolding, base services, and packages other domains rely on.
- Namespaces match paths (`hwc.system.*`, `hwc.filesystem.*` shortcut for core/filesystem) per Charter Law 2.
- No Home Manager logic lives here; cross-lane assertions are guarded so the system lane stands alone.

## Layout
```
domains/system/
├── apps/                 # System-lane app shims
├── core/
│   ├── filesystem/       # Filesystem paths + tmpfiles (namespace: hwc.filesystem.*)
│   ├── parts/
│   └── validation/       # Domain-wide assertions
├── packages/             # Base/server/desktop package bundles
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
- **filesystem/** – Defines `hwc.filesystem.paths` and `hwc.filesystem.structure`; enforces absolute paths and renders tmpfiles entries. All path consumers should use `config.hwc.paths.*` facades defined in the paths module.
- **services/** – Backup, monitoring, networking, ntfy, VPN, Proton Bridge, session, shell, and hardware behavior live here. Each subdirectory exposes its own options under `hwc.system.services.<name>.*` (or Charter-approved short names).
- **storage/** – Houses storage policy modules (tiers, cleanup/retention timers) to satisfy the data retention contract.
- **validation/** – Central assertions to keep the domain self-consistent and Charter-compliant.
- **apps/** / **packages/** / **users/** – System-level apps, package bundles, and account definitions required by other domains.

## Usage
- Import `domains/system/index.nix` from machine configs; enable modules via `hwc.system.*` and `hwc.filesystem.*` options.
- Keep home-lane references guarded with `osConfig ? hwc` per the Handshake Protocol when mirrored into `sys.nix` files elsewhere.
