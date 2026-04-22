# domains/business/estimator/

## Purpose

Heartwood Estimate Assembler — a static React PWA (Vite-built) served via Caddy on a dedicated Tailscale HTTPS port. Provides a cost estimation tool for woodworking projects.

## Boundaries

- **Manages**: Caddy virtual host, firewall rules, SPA routing, build service
- **Does NOT manage**: Catalog data, Caddy service itself (→ `domains/networking/`), n8n webhook workflows

## Structure

```
domains/business/estimator/
├── index.nix     # Options, build service, Caddy config, firewall
├── app/          # Vite + React source (copied to Nix store at eval time)
│   ├── src/      # React components
│   ├── public/   # Static assets, manifest
│   └── ...       # package.json, vite.config.js, etc.
└── README.md     # This file
```

### Runtime paths (on server)

```
/var/lib/estimator/dist          # Symlink → current build
/var/lib/estimator/builds/       # Versioned builds (last 3 kept)
/var/lib/estimator-build/app/    # Working directory for npm builds
```

## Namespace

`hwc.business.estimator.*`

## Configuration

```nix
hwc.business.estimator = {
  enable     = true;
  port       = 13443;
  webhookUrl = "https://hwc.ocelot-wahoo.ts.net/webhook/estimate-push";
  apiKeyFile = config.age.secrets.estimator-api-key.path;
};
```

## Build + Deploy

The build is a NixOS-managed systemd oneshot service. It reads the API key from agenix at runtime, bakes it into the Vite bundle, and deploys with atomic symlink swap.

```bash
# Rebuild after source changes (requires nixos-rebuild switch first)
estimator-build

# Force rebuild (bypass hash check)
sudo rm /var/lib/estimator-build/.last-build-hash
estimator-build

# Rollback to a previous build
ls /var/lib/estimator/builds/
sudo ln -sfn /var/lib/estimator/builds/dist-YYYYMMDD-HHMMSS /var/lib/estimator/dist
```

## Access

`https://hwc.ocelot-wahoo.ts.net:13443`

## Caddy Features

- TLS via Tailscale certificate
- SPA fallback (`try_files {path} /index.html`)
- Immutable caching for `/assets/*` (1 year)
- No-cache for service worker (`/sw.js`) and index

## Changelog

- 2026-04-22: NixOS-managed build service with baked-in secrets, versioned deploys
- 2026-03-25: Created README per Law 12
- 2026-03-23: Moved from webapps domain into business domain
