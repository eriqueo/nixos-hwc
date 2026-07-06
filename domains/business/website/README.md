# Heartwood CMS

## Purpose
Content management dashboard for the customer-facing site at iheartwoodcraft.com. Node.js REST API that reads/writes markdown files and JSON in the site_files 11ty repo, processes images via ImageMagick, builds the site, and deploys to Hostinger via SFTP. Vanilla JS frontend served as static files.

## Boundaries
- Manages: systemd service for the CMS API server (port 8095)
- Does NOT manage: the site_files repo itself -> git
- Does NOT manage: agenix secret declarations -> domains/secrets
- Does NOT manage: reverse proxy -> needs separate Caddy/Tailscale config

## Structure
```
domains/business/website/
├── index.nix        # NixOS module with systemd service
├── webapps/         # webapps directory module (option-declaring leaf, Law 9/10)
├── calculator/      # calculator webapp source
├── site_files       # symlink → /opt/business/website-site (11ty source, out of repo)
├── site_files.pre-eviction-leftovers/  # snapshot of the previously in-repo site_files
├── docs/            # website docs
├── website_ui_kit_design/
├── form-contact.njk, heartwood_system_map.html  # loose assets
└── README.md        # This file
```

Application files live at `/opt/business/heartwood-cms/` (not in the NixOS repo).
The 11ty site source is now the out-of-repo `/opt/business/website-site` (reached
via the `site_files` symlink), not tracked in the NixOS repo.

## Changelog
- 2026-07-06: Evicted the in-repo `site_files/` — it's now a symlink to the out-of-repo `/opt/business/website-site`, with the old contents kept as a `site_files.pre-eviction-leftovers/` snapshot (built HTML, images, calculator bundle). Large content-only dump; no NixOS module logic changed.
- 2026-07-06: `index.nix` touched by the gotify-stack decommission sweep (audit 2.6) — mechanical, no behavior change here.
- 2026-06-09: `webapps.nix` → `webapps/index.nix` (directory-module conversion, Law 9/10, history-preserving `git mv`).
- 2026-06-09: Law 3 path sweep — `index.nix` derives its paths from `hwc.paths` with null-safe fallbacks; drv hash unchanged.
- 2026-06-02: Tailnet rename sweep — `hwc.ocelot-wahoo.ts.net` → `hwc-server.ocelot-wahoo.ts.net` (mechanical).
- 2026-04-01: Rename heartwood-site to site_files, update paths in index.nix
- 2026-03-30: Initial creation — systemd service for Heartwood CMS Dashboard
