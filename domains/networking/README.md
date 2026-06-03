# domains/networking/ — Networking Domain

## Purpose

Provides network infrastructure that other domains depend on:
- Caddy reverse proxy with route aggregation (subpath + port modes)
- Cloudflare Tunnel for public ingress (MCPs, n8n, webhooks)
- Podman media-network creation
- Gluetun VPN container for download stack
- Pi-hole DNS container
- Centralized route definitions for all services

## Boundaries

- Owns: reverse proxy config, Cloudflare Tunnel (public ingress), VPN, DNS, podman networking
- Does NOT own: individual service containers (those live in their own domains)
- Route definitions: currently centralized in `routes.nix`, will be distributed to individual domains as they migrate

## Structure

```
networking/
├── index.nix           # Domain aggregator
├── README.md           # This file
├── hosts.nix           # Host registry: tailnetSuffix + servers + derived fqdn/url helper
├── reverseProxy.nix    # Caddy NixOS service + route rendering
├── routes-lib.nix      # Route accumulator option + mkRoute helper
├── routes.nix          # Centralized service route definitions
├── podman-network.nix  # media-network systemd service
├── cloudflared/        # Cloudflare Tunnel (public webhook ingress)
│   └── index.nix
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
- 2026-06-03: Add `hosts.nix` host registry — single source of truth for tailnet identities. `hwc.networking.hosts` declares one `tailnetSuffix` (`ocelot-wahoo.ts.net`), a `servers` alias→hostname map (`main`/`xps`, `work` reserved), derived `fqdn.<alias>`, and a `url { server?, scheme?, port?, path? }` helper. Two concepts now separated: **self serving domain** (`shared.{rootHost,tailscaleDomain}` + `reverseProxy.domain`) defaults derive from `${networking.hostName}.${tailnetSuffix}` (a server can only ever advertise its own name; xps's manual override dropped); **named cross-host references** use `hosts.url`/`fqdn.*` (migrated: server gotify `serverUrl`, estimator `webhookUrl`, xps gotify `serverUrl`). Port/subpath stay at the call site. Renaming the tailnet = one `tailnetSuffix` edit; renaming a box = its `servers` entry + `networking.hostName`.
- 2026-06-02: Server tailnet name changed `hwc` → `hwc-server`. Updated `reverseProxy.nix` option defaults (`domain`, `shared.tailscaleDomain`, `shared.rootHost`) and the `routes.nix` n8n Origin header from `hwc.ocelot-wahoo.ts.net` to `hwc-server.ocelot-wahoo.ts.net`. Part of a tree-wide rename; the Caddy TLS cert was reissued (see secrets domain). The old name no longer resolves, which had been failing `hwc-webhook-health` and breaking TLS SNI on :2443.
- 2026-05-26: Add sr_analyzer reverse-proxy route on :24443 → 127.0.0.1:8788 (standalone Podman container at ~/apps/sr_analyzer, host 8788 chosen because 8787 is Readarr's).
- 2026-05-22: Migrate all public ingress from Tailscale Funnel to Cloudflare Tunnel. Add n8n.heartwoodcraft.me route. Remove Funnel-era Caddy listeners (:18080, :10080). Caddy reclaims :443 with tailscale cert for direct tailnet access.
- 2026-04-29: Add Cloudflare Tunnel module (hwc.networking.cloudflared) for public webhook ingress via webhooks.heartwoodcraft.me
- 2026-04-04: Update gluetun gotify ref from `hwc.automation.gotify` to `hwc.notifications.send.gotify` (domain redistribution)
- 2026-03-18: Add CloudBeaver web-based database manager routing configuration with port mode and subpath-hostile handling.
- 2026-03-15: Add n8n flow routing configuration with Origin header stripping for security enhancement
- 2026-03-13: Enable shared port-sync service access across multiple Gluetun containers
- 2026-03-13: Enable shared port-sync service access across multiple Gluetun containers

- 2026-03-04: Namespace migration hwc.server.{reverseProxy,shared,containers.gluetun,containers.pihole} → hwc.networking.*
- 2026-03-04: Created networking domain; moved reverseProxy, routes, podman-network, gluetun, pihole from domains/server/ (Phase 3 of DDD migration)
