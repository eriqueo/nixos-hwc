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
- URL: `https://vaultwarden.hwc.iheartwoodcraft.com`
- Admin panel: `https://vaultwarden.hwc.iheartwoodcraft.com/admin` (uses `vaultwarden-admin-token` secret)

## Dependencies
- agenix secret: `vaultwarden-admin-token`
- Podman + media network (when `network.mode = "media"`)
- Caddy reverse proxy via `networking/routes.nix`

## Changelog
- 2026-07-06: Image pinned to `vaultwarden/server:1.35.4` (Law 15 v12.4 critical tier — password vault), replacing the `:latest` default. A follow-up fix repaired the pin's inline comment, which had eaten the `mkOption` closing brace.
- 2026-06-09: Access moved from tailnet port `:15443` to name-based vhost `vaultwarden.hwc.iheartwoodcraft.com` (shared `*.hwc.iheartwoodcraft.com` wildcard cert). Container `DOMAIN` env updated to the new origin — Vaultwarden pins WebAuthn/passkeys to `DOMAIN`, so it must equal the browser URL. `reverseProxy.port` is now vestigial (vhost opens only :443). See `domains/networking/README.md`.
- 2026-03-26: Initial scaffolding — container, env file, reverse proxy, secret integration
