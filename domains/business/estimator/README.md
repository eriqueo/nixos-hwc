# domains/business/estimator/

## Purpose

Heartwood Estimate Assembler — a static React PWA (Vite-built) served via Caddy on a dedicated Tailscale HTTPS port. Provides a cost estimation tool for woodworking projects.

## Boundaries

- **Manages**: Caddy virtual host configuration, firewall rules, SPA routing
- **Does NOT manage**: Build process (manual npm build), catalog data (→ `workspace/business/`), Caddy service itself (→ `domains/networking/`)

## Structure

```
domains/business/estimator/
├── index.nix     # Options, Caddy config, firewall
└── README.md     # This file
```

### Workspace

```
workspace/business/estimator-pwa/
├── dist/              # Built output served by Caddy
├── scripts/           # export_catalog.sh
└── src/data/          # catalog_export.json
```

## Namespace

`hwc.business.estimator.*`

## Configuration

```nix
hwc.business.estimator = {
  enable = true;
  distDir = "/home/eric/.nixos/workspace/business/estimator-pwa/dist";
  port = 13443;
  webhookUrl = "";   # Optional n8n webhook URL (VITE_WEBHOOK_URL)
};
```

## Access

`https://hwc.ocelot-wahoo.ts.net:13443`

## Rebuild Steps

```bash
cd ~/.nixos/workspace/business/estimator-pwa
./scripts/export_catalog.sh   # After catalog.db changes
npm install && npm run build
sudo systemctl reload caddy
```

## Caddy Features

- TLS via Tailscale certificate
- SPA fallback (`try_files {path} /index.html`)
- Immutable caching for `/assets/*` (1 year)
- No-cache for service worker (`/sw.js`) and index

## Changelog

- 2026-03-25: Created README per Law 12
- 2026-03-23: Moved from webapps domain into business domain
