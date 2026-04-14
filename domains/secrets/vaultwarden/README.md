# Vaultwarden

## Purpose
Self-hosted Bitwarden-compatible password manager. Provides secure credential storage accessible via Bitwarden clients (browser extension, mobile app, desktop).

## Boundaries
- Namespace: `hwc.secrets.vaultwarden.*`
- Manages: Podman container, env file generation, reverse proxy route, data persistence
- Does NOT manage: Secrets declarations (→ `secrets/declarations/services.nix`), networking routes (→ `networking/routes.nix`)

## Structure
```
vaultwarden/
└── index.nix    # Options + container config (single-file module)
```

## Configuration
| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable Vaultwarden |
| `image` | `docker.io/vaultwarden/server:latest` | Container image |
| `port` | `8222` | Internal container port mapping |
| `reverseProxy.port` | `15443` | External Tailscale HTTPS port |
| `network.mode` | `"media"` | Podman network mode |

## Access
- URL: `https://hwc.ocelot-wahoo.ts.net:15443`
- Admin panel: `https://hwc.ocelot-wahoo.ts.net:15443/admin` (uses `vaultwarden-admin-token` secret)

## Dependencies
- agenix secret: `vaultwarden-admin-token`
- Podman + media network (when `network.mode = "media"`)
- Caddy reverse proxy via `networking/routes.nix`

## Changelog
- 2026-03-26: Initial scaffolding — container, env file, reverse proxy, secret integration
