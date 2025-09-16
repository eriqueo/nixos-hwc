# Site Crawler (Scrapy + Podman)

Crawls a site (or list of sites), stays on the same registrable domain,
calls your custom extractor on each HTML page, writes JSON Lines.

## Build (Podman)

```bash
podman build -t site-crawler .
