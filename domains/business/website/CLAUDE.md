# Heartwood website

Read README.md and index.nix here for the current hosting contract. All website operations run on hwc-work. Customer-facing hostname is iheartwoodcraft.com; heartwoodcraft.me is legacy, not the production website.

CMS source and developer instructions: /opt/business/heartwood-cms/CLAUDE.md.
Website source: hwc.paths.business.websiteSite, currently /opt/business/website-site.
Published output: hwc.paths.business.websitePublished, currently /opt/business/website-published/current.
The private CMS manages content and publishes atomically to local releases. Public Caddy serves generated files through Cloudflare Tunnel. No Hostinger/SFTP publication remains.

Calculator builds require HWC_WEBSITE_SITE_DIR and use @site-data imports. CMS supplies that path and the configured CRM endpoints. Secrets stay in /run/agenix; never print keys in commands or logs.
