import os
import sys
import argparse
from scrapy.crawler import CrawlerProcess
from scrapy.utils.project import get_project_settings

def parse_args(argv):
    p = argparse.ArgumentParser(description="Site-wide HTML crawler that calls your extractor and writes JSONL.")
    p.add_argument("--start-url", help="Single start URL")
    p.add_argument("--start-urls-file", help="File with multiple start URLs (one per line)")
    p.add_argument("--max-depth", type=int, default=int(os.getenv("MAX_DEPTH", "3")), help="Max crawl depth")
    p.add_argument("--allow-subdomains", action="store_true", help="Follow subdomains on the same registrable domain")
    p.add_argument("--output", default=os.getenv("OUTPUT", "/data/out.jsonl"), help="Output JSONL path (mount /data)")
    p.add_argument(
        "--mode",
        choices=["crawl", "sitemap"],
        default="crawl",
        help="Select crawl mode: 'crawl' for link-following spider, 'sitemap' for sitemap-based spider",
    )
    p.add_argument("--respect-robots", action="store_true", default=True,
                   help="Obey robots.txt (default true). Use --no-respect-robots to disable.")
    p.add_argument("--no-respect-robots", dest="respect_robots", action="store_false")
    p.add_argument("--user-agent", dest="user_agent", help="Override User-Agent")
    return p.parse_args(argv)

def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    settings = get_project_settings()
    if args.user_agent:
        settings.set("USER_AGENT", args.user_agent, priority="cmdline")
    settings.set("ROBOTSTXT_OBEY", bool(args.respect_robots), priority="cmdline")
    
    # Configure FEEDS dynamically (Scrapy 2.1+)
    settings.set("FEEDS", {args.output: {"format": "jsonlines"}}, priority="cmdline")

    process = CrawlerProcess(settings)

    spider_kwargs = {
        "max_depth": args.max_depth,
        "allow_subdomains": "1" if args.allow_subdomains else "0",
    }
    if args.start_url:
        spider_kwargs["start_url"] = args.start_url
    if args.start_urls_file:
        spider_kwargs["start_urls_file"] = args.start_urls_file

    if args.mode == "crawl":
        process.crawl("site", **spider_kwargs)
    elif args.mode == "sitemap":
        process.crawl("sitemap_harvester", start_url=args.start_url)

    process.start()

if __name__ == "__main__":
    main()
