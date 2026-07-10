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
├── index.nix       # NixOS module with systemd service
├── site_files/     # 11ty site source (pages, blog, images, templates)
└── README.md       # This file
```

Application files live at `/opt/business/heartwood-cms/` (not in the NixOS repo).

## Changelog
- 2026-07-10: Calculator "Schedule a call" rebuilt. `leadsAppointmentWebhookUrl` default changed from the broken n8n `https://api.iheartwoodcraft.com/webhook/calculator-appointment` (which wrote an invalid status to the legacy `hwc.calculator_leads`) to the hwc-crm ingress `https://crm.iheartwoodcraft.com/hooks/appointment`. The "Request a call" fetch is now `no-cors`/`text/plain` fire-and-forget. The block-time select (morning/afternoon/evening) was replaced with Calendly-style availability: on date pick the form fetches free 30-min slots from hwc-crm `GET /hooks/availability` (Mon–Fri 9–4 MT, minus real calendar conflicts) into a real time dropdown, submitting an exact HH:MM. Calculator bundle rebuilt from `domains/business/website/calculator/app` (vite; `site_files` is a symlink to `/opt/business/website-site`) with `VITE_LEADS_WEBHOOK_URL` + `VITE_LEADS_WEBHOOK_APPT_URL`. **Cache-bust gotcha:** the bundle has a STABLE filename (`calculator.bundle.js`) that Cloudflare caches 7 days — bump the `?v=YYYYMMDDx` query in `src/pages/calculator.md` + `deck-calculator.md` on every calculator change (the `cloudflare-api-key` secret is DNS/read-scoped and CANNOT purge).
- 2026-07-07: leadsWebhookUrl/leadsAppointmentWebhookUrl defaults switched from the tailnet-only hwc-server.ocelot-wahoo.ts.net (unreachable for public visitors — every calculator lead was silently lost) to the public Cloudflare-tunnel ingress n8n.heartwoodcraft.me. Note: the CMS deploy action does NOT run the vite calculator build despite the env-injection comment — the bundle is built manually and committed to the site repo.
- 2026-04-01: Rename heartwood-site to site_files, update paths in index.nix
- 2026-03-30: Initial creation — systemd service for Heartwood CMS Dashboard
