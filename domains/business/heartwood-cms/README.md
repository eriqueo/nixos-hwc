# Heartwood CMS

## Purpose
Content management dashboard for heartwoodcraft.me. Node.js REST API that reads/writes markdown files and JSON in the heartwood-site 11ty repo, processes images via ImageMagick, builds the site, and deploys to Hostinger via SFTP. Vanilla JS frontend served as static files.

## Boundaries
- Manages: systemd service for the CMS API server (port 8095)
- Does NOT manage: the heartwood-site repo itself -> git
- Does NOT manage: agenix secret declarations -> domains/secrets
- Does NOT manage: reverse proxy -> needs separate Caddy/Tailscale config

## Structure
```
domains/business/heartwood-cms/
├── index.nix       # NixOS module with systemd service
└── README.md       # This file
```

Application files live at `/opt/business/heartwood-cms/` (not in the NixOS repo).

## Changelog
- 2026-03-30: Initial creation — systemd service for Heartwood CMS Dashboard
