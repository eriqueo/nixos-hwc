# Heartwood website on hwc-work

## Purpose
Edit, build and publish iheartwoodcraft.com on hwc-work. Cloudflare provides public DNS, TLS and the tunnel; Caddy serves only local published output. The CMS stays private.

## Boundaries
- Website source: `/opt/business/website-site`, repository `eriqueo/hwc-website`.
- CMS app: `/opt/business/heartwood-cms`, repository `eriqueo/heartwood-cms`.
- Calculator source: `calculator/app` in this Nix repository, on hwc-work.
- CRM receives existing contact/calculator/appointment requests; this migration does not change those endpoints.

## Structure
`index.nix` declares CMS configuration, its local static origin and the public tunnel entries. `hwc.paths.business.websiteSite` and `websitePublished` own locations. CMS and MCP receive the same explicit source path. `site_files` remains a compatibility symlink for old operator instructions, permanent by design; active CMS/MCP/calculator builds no longer require it.

Calculator photo variants are declared in the website’s canonical question data. The shared image-card renderer reads that data; Eleventy generates the selected variants in staged output and retains the originals.

Publishing builds the calculator then the 11ty site. Preview builds do not change the public release. Successful publication switches `website-published/current` atomically. Generated releases are REPLACEABLE and bounded by the publisher; source is CRITICAL and covered by hwc-work's `/opt/business` backup. The previous release supports rollback. Existing Apache redirects and report URL rewrites are now served by Caddy. Hostinger is not a publishing destination.

The CMS deploy action performs local publication. The API remains at loopback port 8095 behind its existing private route. Caddy's public origin binds only 127.0.0.1:8096; no public inbound firewall port is added. The tunnel serves `iheartwoodcraft.com` and `www.iheartwoodcraft.com` from this origin.

## Changelog
- 2026-10-01: Render responsive calculator photo cards from canonical presentation data; preserve estimates and lead fields.
- 2026-09-28: Move public origin and publishing to hwc-work; retain page redirects/report links; derive tool and calculator paths from the canonical source.
- 2026-09-18: Calculator lead intake moved to hwc-crm.
