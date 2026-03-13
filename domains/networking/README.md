# domains/networking/ — Networking Domain

## Purpose

Provides network infrastructure that other domains depend on:
- Caddy reverse proxy with route aggregation (subpath + port modes)
- Podman media-network creation
- Gluetun VPN container for download stack
- Pi-hole DNS container
- Centralized route definitions for all services

## Boundaries

- Owns: reverse proxy config, VPN, DNS, podman networking
- Does NOT own: individual service containers (those live in their own domains)
- Route definitions: currently centralized in `routes.nix`, will be distributed to individual domains as they migrate

## Structure

```
networking/
├── index.nix           # Domain aggregator
├── README.md           # This file
├── reverseProxy.nix    # Caddy NixOS service + route rendering
├── routes-lib.nix      # Route accumulator option + mkRoute helper
├── routes.nix          # Centralized service route definitions
├── podman-network.nix  # media-network systemd service
├── gluetun/            # VPN container (WireGuard via ProtonVPN)
│   ├── index.nix
│   ├── options.nix
│   ├── sys.nix
│   └── parts/
└── pihole/             # DNS container
    ├── index.nix
    ├── options.nix
    ├── sys.nix
    └── README.md
```

## Changelog
- 2026-03-13: Enable shared port-sync service access across multiple Gluetun containers

- 2026-03-04: Namespace migration hwc.server.{reverseProxy,shared,containers.gluetun,containers.pihole} → hwc.networking.*
- 2026-03-04: Created networking domain; moved reverseProxy, routes, podman-network, gluetun, pihole from domains/server/ (Phase 3 of DDD migration)
