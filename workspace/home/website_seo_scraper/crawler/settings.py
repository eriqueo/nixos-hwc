# Minimal, sane defaults. Overridable via spider.custom_settings or CLI.
BOT_NAME = "site_crawler"

SPIDER_MODULES = ["crawler.spiders"]
NEWSPIDER_MODULE = "crawler.spiders"

ROBOTSTXT_OBEY = True
CONCURRENT_REQUESTS = 8
DOWNLOAD_DELAY = 0.25

AUTOTHROTTLE_ENABLED = True
AUTOTHROTTLE_START_DELAY = 0.5
AUTOTHROTTLE_MAX_DELAY = 10.0

LOG_LEVEL = "INFO"

# Respect common compressed content
COMPRESSION_ENABLED = True

# Don’t fill logs with cookies unless debugging
COOKIES_ENABLED = False

# Avoid re-crawling the exact same URLs within one run
DUPEFILTER_CLASS = "scrapy.dupefilters.RFPDupeFilter"
