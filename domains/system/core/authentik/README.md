# Authentik

## Purpose
SSO/Identity Provider for centralized authentication across server services. Supports OAuth2/OIDC, SAML, LDAP, and proxy-based auth.

## Boundaries
- Namespace: `hwc.system.core.authentik.*`
- Manages: Server + worker containers, env file generation, custom Caddy block, PostgreSQL database provisioning
- Does NOT manage: Secrets declarations (→ `secrets/declarations/services.nix`), per-app SSO wiring (→ each app's own config)

## Structure
```
authentik/
├── index.nix          # Options definitions
├── parts/
│   └── config.nix     # Container configs, systemd deps, Caddy, DB provisioning
└── README.md
```

## Configuration
| Option | Default | Description |
|--------|---------|-------------|
| `enable` | `false` | Enable Authentik |
| `image` | `ghcr.io/goauthentik/server:2024.12` | Container image |
| `database.host` | `10.89.0.1` | PostgreSQL host (podman gateway) |
| `database.port` | `5432` | PostgreSQL port |
| `database.name` | `authentik` | Database name |
| `database.user` | `authentik` | Database role |
| `redis.host` | `10.89.0.1` | Redis host |
| `redis.port` | `6380` | Redis port |
| `reverseProxy.port` | `15543` | External Tailscale HTTPS port |
| `reverseProxy.internalPort` | `9200` | Internal HTTP port |
| `reverseProxy.internalHttpsPort` | `9201` | Internal HTTPS port |
| `network.mode` | `"media"` | Podman network mode |

## Access
- URL: `https://hwc.ocelot-wahoo.ts.net:15543`
- Admin: log in as `akadmin` (use recovery key if locked out: `sudo podman exec authentik-server ak create_recovery_key 10 akadmin`)

## Architecture Notes
- Two containers: `authentik-server` (HTTP/API) and `authentik-worker` (background tasks/Celery)
- Custom Caddy block in `parts/config.nix` (not in `networking/routes.nix`) — requires WebSocket headers (`Connection`, `Upgrade`) and `flush_interval -1`
- Known upstream bug (#16684): WebSocket connections may fail on non-standard ports — cosmetic only, app still functions
- DB role created via `postgresql.postStart` script

## Dependencies
- agenix secrets: `authentik-secret-key`, `authentik-db-password`
- PostgreSQL (`hwc.data.databases.postgresql`)
- Redis (host-level, port 6380)
- Podman + media network (when `network.mode = "media"`)

## Changelog
- 2026-03-26: Initial scaffolding — server/worker containers, DB provisioning, Caddy reverse proxy, secret integration
