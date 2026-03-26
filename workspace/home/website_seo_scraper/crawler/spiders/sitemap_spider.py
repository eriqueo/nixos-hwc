import logging
from urllib.parse import urlparse

from lxml.etree import XMLSyntaxError
import scrapy
from scrapy import Request
from scrapy.spiders import SitemapSpider

# IMPORTANT: your extractor is a PACKAGE named `extractor` with a file extractor.py
# (i.e., /app/extractor/__init__.py and /app/extractor/extractor.py)
# and the function is defined as: def extract(html: str, url: str, scoped: bool = True, diagnostics: bool = False) -> dict
from extractor.extractor import extract  # <-- do not change

logger = logging.getLogger(__name__)


class HardenedSitemapSpider(SitemapSpider):
    """
    A robust sitemap spider that:
      - Tries common sitemap endpoints
      - Falls back to robots.txt to discover 'Sitemap:' lines
      - Won't crash on empty/non-XML sitemap responses
      - Calls your extractor.extract() for each page and yields the harvested dict
    """

    name = "sitemap"

    # You can override these via settings or CLI (run.py sets FEEDS, ROBOTSTXT_OBEY, USER_AGENT, etc.)
    custom_settings = {
        # Respect robots unless run.py overrides it
        "ROBOTSTXT_OBEY": True,
        # Be nice by default
        "AUTOTHROTTLE_ENABLED": True,
        "AUTOTHROTTLE_START_DELAY": 0.5,
        "AUTOTHROTTLE_MAX_DELAY": 10.0,
        "CONCURRENT_REQUESTS": 8,
        "DOWNLOAD_DELAY": 0.25,
        "COOKIES_ENABLED": False,
        "LOG_LEVEL": "INFO",
    }

    # Parse every URL found in the sitemap(s) with parse_page
    sitemap_rules = [(r".*", "parse_page")]

    def __init__(self, start_url=None, allow_subdomains="0", *args, **kwargs):
        """
        Args passed from run.py:
          --start-url <URL> (required)
          --allow-subdomains  "1" to allow subdomains, "0" (default) to restrict to exact hostname
        """
        super().__init__(*args, **kwargs)

        if not start_url:
            raise ValueError("--start-url is required for sitemap mode")

        self.start_url = start_url.rstrip("/")
        self.allow_subdomains = str(allow_subdomains or "0") == "1"

        host = self._hostname(self.start_url)
        if not host:
            raise ValueError(f"Could not derive hostname from start URL: {self.start_url}")

        # Restrict scope
        if self.allow_subdomains:
            # Keep registrable domain only (best-effort without extra deps)
            parts = host.split(".")
            base = ".".join(parts[-2:]) if len(parts) >= 2 else host
            self.allowed_domains = [base]
        else:
            self.allowed_domains = [host]

        # Seed common sitemap endpoints; we’ll also try robots.txt for Sitemap: lines
        self.sitemap_urls = [
            f"{self.start_url}/sitemap.xml",
            f"{self.start_url}/sitemap_index.xml",
        ]
        self._robots_url = f"{self.start_url}/robots.txt"

        logger.info("Sitemap spider init | start=%s allow_subdomains=%s allowed_domains=%s",
                    self.start_url, self.allow_subdomains, self.allowed_domains)

    # ---- helpers ----

    def _hostname(self, url: str) -> str:
        return urlparse(url).hostname or ""

    # ---- overrides / hardening ----

    def _parse_sitemap(self, response):
        """
        Hardened version of the parent parser:
         - Accepts empty/non-XML responses and falls back to robots.txt
         - Catches XMLSyntaxError and falls back
        """
        ctype = (response.headers.get(b"Content-Type") or b"").decode(errors="ignore").lower()
        body = (response.text or "").strip()

        if not body or "xml" not in ctype:
            logger.warning("Sitemap not XML or empty: %s (Content-Type=%s). Falling back to robots.txt",
                           response.url, ctype)
            yield Request(self._robots_url, callback=self.parse_robots, dont_filter=True)
            return

        try:
            # Use the base class logic when it *is* valid XML
            yield from super()._parse_sitemap(response)
        except XMLSyntaxError:
            logger.warning("Invalid XML in sitemap: %s. Falling back to robots.txt", response.url)
            yield Request(self._robots_url, callback=self.parse_robots, dont_filter=True)

    def parse_robots(self, response):
        """
        Discover additional sitemaps via robots.txt 'Sitemap:' directives.
        """
        if response.status != 200 or not response.text:
            logger.warning("robots.txt missing or empty at %s (status=%s)", response.url, response.status)
            return

        found = 0
        for line in response.text.splitlines():
            line = line.strip()
            if not line or not line.lower().startswith("sitemap:"):
                continue
            url = line.split(":", 1)[1].strip()
            if url:
                found += 1
                logger.info("Found sitemap in robots.txt: %s", url)
                yield Request(url, callback=self._parse_sitemap, dont_filter=True)

        if found == 0:
            logger.info("No 'Sitemap:' lines in robots.txt at %s", response.url)

    # ---- page handler ----

    def parse_page(self, response):
        """
        Called for every URL matched by sitemap_rules.
        Runs your extractor and yields the harvested dict directly as an item.
        """
        try:
            harvested = extract(
                html=response.text,
                url=response.url,
                scoped=True,            # use the scoped main-content heuristic by default
                diagnostics=False,      # flip to True if you want resource counts
            )
            # Ensure we always include the fetched URL (defensive)
            harvested["meta"] = harvested.get("meta", {})
            harvested["meta"]["fetchedUrl"] = response.url

            yield harvested

        except Exception as e:
            logger.error("Extractor failed for %s: %s", response.url, e, exc_info=True)
            # You could also yield a minimal error record instead of dropping it:
            # yield {"meta": {"url": response.url, "error": str(e)}}
