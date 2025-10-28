import re
from urllib.parse import urljoin, urlparse
import tldextract
import scrapy
from extractor import extract

SKIP_EXT = re.compile(
    r"\.(?:pdf|zip|rar|7z|tar|gz|bz2|mp4|mp3|mov|avi|wmv|webm|mkv|jpg|jpeg|png|gif|svg|webp|ico|bmp|ttf|woff2?|eot|css|less|scss|js)$",
    re.IGNORECASE,
)

def same_registrable_domain(url_a: str, url_b: str) -> bool:
    a = tldextract.extract(url_a)
    b = tldextract.extract(url_b)
    return (a.domain, a.suffix) == (b.domain, b.suffix)

class SiteSpider(scrapy.Spider):
    """
    Crawl one or more start URLs, stay on the same registrable domain,
    run your extractor on every HTML page, and emit JSON lines.
    """
    name = "site"

    # Many things are overridable at runtime; these are defaults
    custom_settings = {
        "ROBOTSTXT_OBEY": True,
        "AUTOTHROTTLE_ENABLED": True,
        "CONCURRENT_REQUESTS": 8,
        "DOWNLOAD_DELAY": 0.25,
        # The FEEDS target file is injected by run.py so we don't fix it here.
    }

    def __init__(self, start_url=None, start_urls_file=None, max_depth=3, allow_subdomains="1", *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.max_depth = int(max_depth)
        self.allow_subdomains = allow_subdomains == "1"

        self._start_urls = []
        if start_url:
            self._start_urls = [start_url]
        elif start_urls_file:
            with open(start_urls_file, "r", encoding="utf-8") as f:
                self._start_urls = [ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")]
        else:
            raise ValueError("Provide -a start_url=... or -a start_urls_file=...")

        # Anchor domain to the first URL; others are filtered by same registrable domain
        self.anchor = self._start_urls[0]

    def start_requests(self):
        for u in self._start_urls:
            yield scrapy.Request(u, callback=self.parse, meta={"depth": 0})

    def parse(self, response):
        # Run your extractor and yield record
        if "text/html" in (response.headers.get("Content-Type", b"text/html").decode().split(";")[0]):
            try:
                data = extract(response.text, response.url)  # returns your full harvested dict
                if data:
                    # If someone later swaps extract() to return just a fragment, we still add URL/status.
                    if not isinstance(data, dict) or "meta" not in data or "extracted" not in data:
                        data = {"meta": {"url": response.url}, "extracted": data}
                    # Attach HTTP status for convenience
                    data.setdefault("extracted", {}).setdefault("technical", {})
                    data["extracted"]["technical"].setdefault("httpStatus", response.status)
                    yield data
            except Exception as e:
                self.logger.warning(f"Extractor error on {response.url}: {e}")


            # Depth-limited link following
            depth = response.meta.get("depth", 0)
            if depth >= self.max_depth:
                return

            # Discover links
            for href in response.css("a::attr(href)").getall():
                abs_url = urljoin(response.url, href.strip())
                if SKIP_EXT.search(urlparse(abs_url).path):
                    continue
                # Keep to same registrable domain
                if same_registrable_domain(abs_url, self.anchor):
                    # If subdomains not allowed, enforce exact netloc match with anchor
                    if not self.allow_subdomains:
                        if urlparse(abs_url).netloc != urlparse(self.anchor).netloc:
                            continue
                    yield scrapy.Request(abs_url, callback=self.parse, meta={"depth": depth + 1})
