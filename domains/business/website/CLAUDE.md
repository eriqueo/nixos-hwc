# Heartwood CMS — Architecture Overview

## What This Is
Content management system for **heartwoodcraft.me** (Heartwood Craft remodeling business, Bozeman MT). Node.js REST API + vanilla JS frontend that manages an 11ty static site, processes images, and deploys via SFTP to Hostinger.

## Two Repos, One System

| Component | Path | Purpose |
|-----------|------|---------|
| CMS App | `/opt/business/heartwood-cms/` | Express 5 API + frontend dashboard |
| Site Repo | `/home/eric/.nixos/domains/business/website/site_files/` | 11ty source (markdown, templates, images) |
| NixOS Config | `domains/business/website/index.nix` | Systemd service, namespace `hwc.business.website` |
| Caddy Route | `domains/networking/routes.nix` | Reverse proxy entry, name `heartwood-cms`, port 18095 |

## CMS App (`/opt/business/heartwood-cms/`)
See `/opt/business/heartwood-cms/CLAUDE.md` for full CMS dev context.

### Key Facts
- **Express 5** (NOT Express 4 — path syntax differs, no `app.get('*')` catch-all)
- **Port**: 8095, binds `127.0.0.1`
- **Auth**: API key from `/run/agenix/cms-api-key`, sent via `x-api-key` header
- **Frontend**: Vanilla JS ES modules in `public/js/`, no build step, no framework
- **Theme**: Gruvbox Material Dark
- **Deploy**: Builds 11ty then SFTP uploads `dist/` to Hostinger

### API Routes
- `GET/PUT /api/pages/:slug` — page content (markdown + frontmatter)
- `GET/POST/DELETE /api/blog/:slug` — blog CRUD (soft delete to `.trash/`)
- `GET/PUT /api/reviews` — testimonials JSON array
- `GET /api/images/:dir`, `POST /api/images/upload`, `DELETE /api/images/:dir/:file`
- `POST /api/build` — 11ty build only
- `POST /api/deploy` — build + SFTP upload
- `GET /api/deploy/status` — last deploy record

## Site Repo (`site_files/`)

### 11ty Structure
```
src/
├── _data/site.json       # Global data (phone, email, webhook URLs)
├── _includes/
│   ├── layouts/           # Nunjucks page layouts
│   └── partials/          # Reusable components (form-contact.njk, etc.)
├── pages/                 # 16 pages: index, about, services, locations, etc.
├── blog/                  # 21 blog posts (flat .md files, no date prefix)
├── img/{hero,portfolio,blog,brand}/  # Images (WebP, processed by CMS)
├── css/                   # Site stylesheets
└── js/main.js             # Site frontend JS
```
- **Build command**: `npx @11ty/eleventy` (from site repo root)
- **Output**: `dist/` (NOT `_site/`)
- **Template engine**: Nunjucks (`.njk`), markdown rendered through Nunjucks

### Webhooks (n8n)
- Contact form: `https://hwc.ocelot-wahoo.ts.net/webhook/new-lead` (workflow #10)
- Calculator: `https://hwc.ocelot-wahoo.ts.net/webhook/calculator-lead`
- Configured in `src/_data/site.json`, referenced via `{{ site.webhookContact }}`

## NixOS Service

### Namespace
`hwc.business.website` with options: `enable`, `port`, `srcDir`, `siteDir`, `user`

### Secrets (agenix)
- `/run/agenix/cms-api-key` — API authentication key
- `/run/agenix/hostinger-sftp` — JSON with `host`, `port`, `username`, `privateKey` path, `remotePath`
- Both require `group = "secrets"; mode = "0440"` in secret declarations

### Service Details
- Runs as `eric` with `SupplementaryGroups = ["secrets"]`
- `path` includes `imagemagick` and `nodejs_22`
- Security hardened: `ProtectSystem = "strict"`, `ReadWritePaths` for srcDir/siteDir/tmp

## NixOS Gotchas
- **Shell for child_process**: Must use `shell: '/run/current-system/sw/bin/bash'` — NixOS has no `/bin/sh`
- **PATH for builds**: Must prepend `/run/current-system/sw/bin:` to `process.env.PATH`
- **Restart after code changes**: `sudo systemctl restart heartwood-cms`
- **Check logs**: `sudo journalctl -u heartwood-cms -f`

## Testing
```bash
# Health check
curl -H "x-api-key: $(sudo cat /run/agenix/cms-api-key)" http://localhost:8095/api/health

# Trigger deploy
curl -X POST -H "x-api-key: $(sudo cat /run/agenix/cms-api-key)" http://localhost:8095/api/deploy
```
