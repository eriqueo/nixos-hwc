#!/usr/bin/env python3

import argparse, csv, json, math, re, sys, time, hashlib
from urllib.parse import urljoin, urlparse
from datetime import datetime, timezone
import requests
from bs4 import BeautifulSoup, NavigableString, Tag

TOOL_VERSION = "3.2.0"
SCHEMA_VERSION = "raw-harvest-v1"

CONTENT_PREFER = [
    "main[role='main']","main","article",".entry-content",".site-content",
    "#primary","#content",".content",".page-content",".post-content",".hentry",
    ".container main","[data-seo-content='true']"
]

NOISE_CONTAINERS = [
    "#query-monitor","[id^='query-monitor']","[class*='query-monitor']","#qm-wrapper","[id^='qm-']",".qm",".qm-box",".qm-panel",
    "#wpadminbar","#wp-toolbar",".wp-admin",
    "nav","header","footer","aside",
    "script","style","template","noscript","iframe",
    "[hidden]","[aria-hidden='true']","[role='presentation']"
]

SOCIAL_DOMAINS = [
    "facebook.com","instagram.com","linkedin.com","youtube.com","tiktok.com",
    "pinterest.com","x.com","twitter.com","houzz.com","bbb.org","nari.org"
]

IMAGE_EXT_RE = re.compile(r"\.(jpe?g|png|webp|gif|svg|avif)(\?|#|$)", re.I)

def now_iso():
    return datetime.now(timezone.utc).isoformat()

def filename_base(hostname, suffix=""):
    domain = re.sub(r"[^a-z0-9]", "_", (hostname or "site").lower())
    date = datetime.now().date().isoformat()
    return f"raw_{domain}_{date}{'_' + suffix if suffix else ''}"

def safe(fn, fallback=None):
    try:
        return fn()
    except Exception:
        return fallback

def tokenize(s):
    return [w for w in re.sub(r"[^\w\s]", " ", (s or "").lower()).split() if len(w) > 2]

def jaccard(a_str, b_str):
    a, b = set(tokenize(a_str)), set(tokenize(b_str))
    if not a and not b: return 1.0
    inter = len(a & b)
    uni = len(a | b) or 1
    return inter / uni

def wc(text):
    return len([w for w in re.split(r"\s+", (text or "").strip()) if w])

def is_internal_href(href, origin):
    try:
        if not href: return False
        if href.startswith("#"): return False
        if re.match(r"^(tel:|mailto:|javascript:|data:)", href, re.I): return False
        if href.startswith("/"): return True
        u = urlparse(urljoin(origin, href))
        return u.scheme in ("http","https") and u.netloc == urlparse(origin).netloc
    except Exception:
        return False

def get_selector(el):
    if not isinstance(el, Tag): return ""
    if el.has_attr("id") and el["id"]:
        return f"#{el['id']}"
    cls = (el.get("class") or [])[:2]
    if cls:
        return f"{el.name}." + ".".join(cls)
    idx = 1
    if el.parent:
        for sib in el.parent.children:
            if isinstance(sib, Tag):
                if sib is el: break
                if sib.name == el.name: idx += 1
    return f"{el.name}:nth-of-type({idx})"

def pick_largest_text_block(soup):
    candidates = soup.select("main, article, section, .container, .content, .site-content, #content, #primary")
    candidates = [el for el in candidates if el and el.get_text(strip=True)]
    if not candidates: return soup.body or soup
    best = max(candidates, key=lambda el: wc(el.get_text(" ", strip=True)))
    return best

def build_clean_root(soup):
    scope = None
    for sel in CONTENT_PREFER:
        found = soup.select_one(sel)
        if found:
            scope = found
            break
    if not scope:
        scope = pick_largest_text_block(soup)
    # clone by creating new soup from str(scope)
    clone = BeautifulSoup(str(scope), "lxml")

    # remove obvious noise
    for sel in NOISE_CONTAINERS:
        for n in clone.select(sel):
            n.decompose()

    # strip elements with inline fixed/overlay hints
    for n in clone.select("[style*='position:fixed'], [style*='z-index']"):
        n.decompose()

    # remove iframes again (defensive)
    for n in clone.select("iframe"):
        n.decompose()

    return clone

def text_from(root):
    for n in root.select("script,style,template,noscript"):
        n.decompose()
    return root.get_text("\n", strip=True)

def extract_meta(soup, url):
    title = soup.title.get_text(strip=True) if soup.title else ""
    meta_all = []
    for m in soup.find_all("meta"):
        meta_all.append({
            "name": m.get("name"),
            "property": m.get("property"),
            "httpEquiv": m.get("http-equiv"),
            "content": m.get("content")
        })
    def first_meta(selector):
        el = soup.select_one(selector)
        return el.get("content","") if el else ""
    description = first_meta('meta[name="description"],meta[property="description"]')
    robots = first_meta('meta[name="robots"]')
    canonical = safe(lambda: soup.select_one('link[rel="canonical"]').get("href",""), "")
    lang = soup.html.get("lang","") if soup.html else ""
    viewport = first_meta('meta[name="viewport"]')
    charset = safe(lambda: soup.select_one("meta[charset]")["charset"], "")

    # OG/Twitter
    og, tw = {}, {}
    for m in meta_all:
        if m["property"] and str(m["property"]).lower().startswith("og:"):
            og[m["property"][3:]] = m["content"] or ""
        if m["name"] and str(m["name"]).lower().startswith("twitter:"):
            tw[m["name"][8:]] = m["content"] or ""

    link_rels = []
    for l in soup.find_all("link"):
        link_rels.append({
            "rel": l.get("rel")[0] if l.get("rel") else None,
            "href": l.get("href"),
            "as": l.get("as"),
            "type": l.get("type"),
            "hreflang": l.get("hreflang"),
            "sizes": l.get("sizes")
        })

    return {
        "meta": {
            "title": title,
            "titleLength": len(title),
            "description": description,
            "descriptionLength": len(description),
            "robots": robots,
            "hasRobots": bool(robots),
            "canonical": canonical,
            "hasCanonical": bool(canonical),
            "language": lang,
            "viewport": viewport,
            "charset": charset
        },
        "metaAll": meta_all,
        "openGraph": {
            "title": og.get("title",""),
            "description": og.get("description",""),
            "image": og.get("image",""),
            "url": og.get("url",""),
            "type": og.get("type",""),
            "site_name": og.get("site_name", og.get("site","")),
            "locale": og.get("locale","")
        },
        "twitter": {
            "card": tw.get("card",""),
            "title": tw.get("title",""),
            "description": tw.get("description",""),
            "image": tw.get("image", tw.get("image:src","")),
            "site": tw.get("site",""),
            "creator": tw.get("creator","")
        },
        "linkRels": link_rels
    }

def has_level_skips(headings):
    last = 0
    for h in headings:
        lv = int(h["tag"][1:])
        if last and lv > last + 1:
            return True
        last = lv
    return False

def extract_headings(root, page_title):
    items = []
    for n in root.select("h1,h2,h3,h4,h5,h6"):
        items.append({"tag": n.name.lower(), "text": (n.get_text(" ", strip=True) or "").strip(), "id": n.get("id")})
    h1s = [i for i in items if i["tag"] == "h1"]
    summary = {
        "h1Count": len(h1s),
        "duplicateH1": len(h1s) != 1,
        "invalidStructure": has_level_skips(items),
        "titleH1Similarity": round(jaccard(page_title, h1s[0]["text"] if h1s else ""), 2)
    }
    return {"items": items, "summary": summary}

def extract_links(root, origin):
    anchors = []
    for a in root.select("a[href]"):
        href = a.get("href") or ""
        abs_url = safe(lambda: urljoin(origin, href), "")
        rel = a.get("rel")
        rel_str = " ".join(rel) if isinstance(rel, list) else (rel or "")
        nofollow = bool(re.search(r"\bnofollow\b", rel_str, re.I)) if rel_str else None
        noopener = bool(re.search(r"\bnoopener\b", rel_str, re.I)) if rel_str else None
        target = a.get("target")
        ctx_tag = "content"
        p = a.find_parent(["nav","header","footer","aside"])
        if p: ctx_tag = p.name.lower()
        is_media = bool(IMAGE_EXT_RE.search(href))
        anchors.append({
            "abs": abs_url,
            "href": href,
            "text": (a.get_text(" ", strip=True) or "").strip(),
            "internal": is_internal_href(href, origin),
            "context": ctx_tag if ctx_tag in ("nav","header","footer","aside") else "content",
            "rel": rel_str or None,
            "nofollow": nofollow,
            "noopener": noopener,
            "target": target,
            "isMedia": is_media
        })
    internal = [x for x in anchors if x["internal"]]
    external = [x for x in anchors if not x["internal"] and (x["href"].startswith("http://") or x["href"].startswith("https://"))]
    return {
        "counts": {"total": len(anchors), "internal": len(internal), "external": len(external)},
        "internal": internal[:200],
        "external": external[:200]
    }

def get_attr(el, names):
    for n in names:
        v = el.get(n)
        if v: return v
    return None

def parse_srcset_for_largest(srcset):
    if not srcset: return ""
    parts = [p.strip() for p in srcset.split(",") if p.strip()]
    def width(p):
        m = re.search(r"\s(\d+)w", p)
        return int(m.group(1)) if m else 0
    parts.sort(key=width, reverse=True)
    first = parts[0] if parts else ""
    return re.sub(r"\s+\d+w$", "", first).strip()

def extract_images(root):
    items = []

    for img in root.find_all("img"):
        src = get_attr(img, ["src","data-src","data-lazy","data-original"]) or ""
        srcset = get_attr(img, ["srcset","data-srcset"]) or ""
        lazy_attr = None
        for cand in ["data-src","data-lazy","data-original","data-srcset"]:
            if img.has_attr(cand):
                lazy_attr = cand
                break
        items.append({
            "tag": "img",
            "src": src,
            "srcset": srcset,
            "alt": img.get("alt",""),
            "title": img.get("title",""),
            "loading": img.get("loading",""),
            "width": img.get("width",""),
            "height": img.get("height",""),
            "fromSource": bool(src),
            "lazyAttr": lazy_attr or ""
        })

    for source in root.select("picture source"):
        srcset = get_attr(source, ["srcset","data-srcset"]) or ""
        largest = parse_srcset_for_largest(srcset) if srcset else ""
        items.append({
            "tag": "source",
            "src": largest or "",
            "srcset": srcset,
            "alt": "",
            "title": "",
            "fromSource": bool(largest)
        })

    background_images = []
    for el in root.select("[style*='background-image']"):
        style = el.get("style") or ""
        m = re.search(r"background-image:\s*url\((['\"]?)(.*?)\1\)", style, re.I)
        if m and m.group(2):
            background_images.append({"selector": get_selector(el), "url": m.group(2)})

    img_els = root.find_all("img")
    with_alt = sum(1 for i in img_els if (i.get("alt") or "").strip())
    missing_alt = max(len(img_els) - with_alt, 0)

    return {
        "total": len(img_els),
        "withAlt": with_alt,
        "missingAlt": missing_alt,
        "items": items[:500],
        "backgroundImages": background_images
    }

def extract_content(root):
    scoped_text = re.sub(r"\s+\n", "\n", text_from(root))
    scoped_text = re.sub(r"\n{3,}", "\n\n", scoped_text)
    blocks = []
    candidates = root.select("p, li, h1, h2, h3, h4, h5, h6, div")
    for el in candidates:
        txt = (el.get_text(" ", strip=True) or "").strip()
        if len(txt) >= 80:
            blocks.append({"tag": el.name.lower(), "text": txt[:400]})
        if len(blocks) >= 50: break
    return {"scopedText": scoped_text, "blocks": blocks}

def nearest_label_text(field, form_root):
    aria = field.get("aria-label")
    if aria: return aria
    fid = field.get("id")
    if fid:
        lab = form_root.select_one(f'label[for="{fid}"]')
        if lab: return lab.get_text(" ", strip=True)
    parent_label = field.find_parent("label")
    if parent_label: return parent_label.get_text(" ", strip=True)
    prev = field.find_previous_sibling()
    hops = 0
    while prev and hops < 2:
        t = (prev.get_text(" ", strip=True) or "").strip()
        if t: return t
        prev = prev.find_previous_sibling()
        hops += 1
    ph = field.get("placeholder")
    return ph or ""

def extract_forms(root):
    forms_out = []
    for f in root.find_all("form"):
        fields = []
        for field in f.select("input, select, textarea"):
            label_text = (nearest_label_text(field, root) or "").strip()
            t_raw = (field.get("type") or field.name or "text").lower()
            fields.append({
                "name": field.get("name",""),
                "id": field.get("id",""),
                "label": re.sub(r"[*:]\s*$","", label_text),
                "required": field.has_attr("required") or bool(re.search(r"\*\s*$", label_text)),
                "type": t_raw or "text"
            })
        forms_out.append({
            "action": f.get("action",""),
            "method": (f.get("method","get") or "get").lower(),
            "fields": fields
        })
    return forms_out

def dedupe_by_url(arr):
    seen = {}
    for o in arr:
        url = o.get("url")
        if url and url not in seen:
            seen[url] = o
    return list(seen.values())

def extract_contacts_social(root):
    phone_hrefs = [a.get("href","")[4:].strip() for a in root.select('a[href^="tel:"]')]
    email_hrefs = [a.get("href","")[7:].strip() for a in root.select('a[href^="mailto:"]')]
    phones = sorted(set(phone_hrefs))
    emails = sorted(set(email_hrefs))

    social = []
    for a in root.select("a[href]"):
        href = a.get("href")
        if not href: continue
        try:
            host = urlparse(href).hostname or ""
        except Exception:
            host = ""
        host = host.lower()
        if any(d in host for d in SOCIAL_DOMAINS):
            site = re.sub(r"^www\.", "", host).split(".")[0]
            social.append({"site": site, "url": href})
    return {"phones": phones, "emails": emails, "socialProfiles": dedupe_by_url(social)}

def extract_schema(soup):
    jsonld = []
    errors = []
    for i, s in enumerate(soup.select('script[type="application/ld+json"]')):
        raw = (s.string or s.get_text() or "").strip()
        if not raw: continue
        type_name = ""
        try:
            parsed = json.loads(raw)
            items = parsed if isinstance(parsed, list) else (parsed.get("@graph") if isinstance(parsed, dict) and "@graph" in parsed else [parsed])
            types = []
            for it in items:
                if isinstance(it, dict):
                    t = it.get("@type")
                    if isinstance(t, list) and t:
                        types.append(str(t[0]))
                    elif isinstance(t, str):
                        types.append(t)
            type_name = ", ".join([t for t in types if t])
        except Exception as e:
            errors.append({"index": i, "error": str(e)})
        jsonld.append({"type": type_name, "raw": raw[:50000]})

    microdata = [{"type": el.get("itemtype"), "selector": get_selector(el)} for el in soup.select("[itemscope][itemtype]")]
    rdfa = [{"typeof": el.get("typeof",""), "vocab": el.get("vocab",""), "selector": get_selector(el)} for el in soup.select("[typeof],[vocab]")]
    return {"count": len(jsonld)+len(microdata)+len(rdfa), "jsonLd": jsonld, "microdata": microdata, "rdfa": rdfa, "errors": errors}

def extract_platform_hints(soup):
    hints = []
    gens = [ (m.get("content") or "").lower() for m in soup.select('meta[name="generator"]') ]
    if any("wordpress" in g for g in gens):
        hints.append({"name":"WordPress","signal":"meta generator","confidence":0.9})
    hrefs = []
    for n in soup.find_all(["link","script"]):
        hrefs.append(n.get("href") or n.get("src") or "")
    if any(re.search(r"elementor", h or "", re.I) for h in hrefs):
        hints.append({"name":"Elementor","signal":"assets","confidence":0.9})
    if any(re.search(r"(et-|divi)", h or "", re.I) for h in hrefs):
        hints.append({"name":"Divi","signal":"assets","confidence":0.85})
    if any(re.search(r"(leadconnector|stcdn\.leadconnectorhq\.com)", h or "", re.I) for h in hrefs):
        hints.append({"name":"GoHighLevel","signal":"CDN","confidence":0.95})
    body = soup.body
    body_cls = " ".join(body.get("class", [])) .lower() if body else ""
    if not any(h["name"]=="WordPress" for h in hints) and re.search(r"\bwp-\w+", body_cls):
        hints.append({"name":"WordPress","signal":"body class","confidence":0.7})
    return {"hints": hints}

def extract_technical(soup, url, diagnostics=False):
    u = urlparse(url)
    https = (u.scheme == "https")
    hreflang = [l.get("hreflang") for l in soup.select('link[rel="alternate"][hreflang]') if l.get("hreflang")]
    mixed = any(
        (tag.get("src","").startswith("http://") or tag.get("href","").startswith("http://"))
        for tag in soup.find_all(["img","script","link"])
    )
    perf_timings = {"navigationStart": int(time.time()*1000), "domContentLoaded": None, "loadEvent": None}
    resource_counts = None
    if diagnostics:
        resource_counts = {
            "script": len(soup.select("script[src]")),
            "stylesheet": len(soup.select('link[rel="stylesheet"]')),
            "image": len(soup.select("img")) + len(soup.select("picture source"))
        }
    return {"https": https, "hreflang": hreflang, "mixedContentDetected": mixed, "perfTimings": perf_timings, "resourceCounts": resource_counts}

def head_hash(html_text):
    try:
        soup = BeautifulSoup(html_text, "lxml")
        head_html = str(soup.head) if soup.head else ""
        return hashlib.md5(head_html.encode("utf-8")).hexdigest()[:8]
    except Exception:
        return ""

def to_csv_rows(h):
    m = h["extracted"]["meta"]
    hd = h["extracted"]["headings"]["summary"]
    l = h["extracted"]["links"]["counts"]
    im = h["extracted"]["images"]
    tech = h["extracted"]["technical"]
    rows = [
        ["URL", h["meta"]["url"]],
        ["Title", m["title"]], ["Title Length", m["titleLength"]],
        ["Description Length", m["descriptionLength"]],
        ["Has Robots", m["hasRobots"]], ["Has Canonical", m["hasCanonical"]],
        ["H1 Count", hd["h1Count"]], ["Duplicate H1", hd["duplicateH1"]], ["Title~H1 Similarity", hd["titleH1Similarity"]],
        ["Links Total", l["total"]], ["Internal", l["internal"]], ["External", l["external"]],
        ["Images Total (img)", im["total"]], ["With Alt", im["withAlt"]], ["Missing Alt", im["missingAlt"]],
        ["HTTPS", tech["https"]], ["Mixed Content", tech["mixedContentDetected"]],
        ["DCL (ms)", tech["perfTimings"]["domContentLoaded"] or ""], ["Load (ms)", tech["perfTimings"]["loadEvent"] or ""]
    ]
    return rows

def harvest(url, scoped=True, diagnostics=False, timeout=30, user_agent=None):
    start = time.time()
    headers = {"User-Agent": user_agent or f"RawSEOHarvester/{TOOL_VERSION} (+https://example.local)"}
    resp = requests.get(url, headers=headers, timeout=timeout)
    resp.raise_for_status()
    html = resp.text
    soup = BeautifulSoup(html, "lxml")

    root = build_clean_root(soup) if scoped else BeautifulSoup(str(soup.body or soup), "lxml")

    meta_blocks = extract_meta(soup, url)
    headings = extract_headings(root, meta_blocks["meta"]["title"])
    links = extract_links(root, f"{urlparse(url).scheme}://{urlparse(url).netloc}")
    images = extract_images(root)
    content = extract_content(root)
    forms = extract_forms(root)
    contacts_social = extract_contacts_social(root)
    schema = extract_schema(soup)
    platform = extract_platform_hints(soup)
    technical = extract_technical(soup, url, diagnostics)

    harvested = {
        "meta": {
            "toolVersion": TOOL_VERSION,
            "schemaVersion": SCHEMA_VERSION,
            "harvestedAt": now_iso(),
            "url": url,
            "domain": urlparse(url).hostname or "",
            "userAgent": headers["User-Agent"],
            "scoped": bool(scoped),
            "diagnosticsMode": bool(diagnostics),
            "analysisTimeMs": 0
        },
        "extracted": {
            **meta_blocks,
            "headings": headings,
            "links": links,
            "images": images,
            "content": content,
            "forms": forms,
            "contacts": {"phones": contacts_social["phones"], "emails": contacts_social["emails"]},
            "socialProfiles": contacts_social["socialProfiles"],
            "schema": schema,
            "platform": platform,
            "technical": technical,
            "hashes": {"headHash": head_hash(html)}
        }
    }
    harvested["meta"]["analysisTimeMs"] = int((time.time() - start) * 1000)
    return harvested
    
def extract(html: str, url: str, scoped: bool = True, diagnostics: bool = False) -> dict:
    start = time.time()
    soup = BeautifulSoup(html, "lxml")
    root = build_clean_root(soup) if scoped else BeautifulSoup(str(soup.body or soup), "lxml")

    meta_blocks = extract_meta(soup, url)
    headings = extract_headings(root, meta_blocks["meta"]["title"])
    links = extract_links(root, f"{urlparse(url).scheme}://{urlparse(url).netloc}")
    images = extract_images(root)
    content = extract_content(root)
    forms = extract_forms(root)
    contacts_social = extract_contacts_social(root)
    schema = extract_schema(soup)
    platform = extract_platform_hints(soup)
    technical = extract_technical(soup, url, diagnostics=diagnostics)

    harvested = {
        "meta": {
            "toolVersion": TOOL_VERSION,
            "schemaVersion": SCHEMA_VERSION,
            "harvestedAt": now_iso(),
            "url": url,
            "domain": urlparse(url).hostname or "",
            "userAgent": "Scrapy/embedded",
            "scoped": bool(scoped),
            "diagnosticsMode": bool(diagnostics),
            "analysisTimeMs": int((time.time() - start) * 1000),
        },
        "extracted": {
            **meta_blocks,
            "headings": headings,
            "links": links,
            "images": images,
            "content": content,
            "forms": forms,
            "contacts": {"phones": contacts_social["phones"], "emails": contacts_social["emails"]},
            "socialProfiles": contacts_social["socialProfiles"],
            "schema": schema,
            "platform": platform,
            "technical": technical,
            "hashes": {"headHash": head_hash(soup.decode())},
        },
    }
    return harvested
def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f, quoting=csv.QUOTE_MINIMAL)
        for r in rows:
            w.writerow([str(c) for c in r])

def main():
    ap = argparse.ArgumentParser(description="Raw SEO Harvester (Python port)")
    ap.add_argument("url", help="Target URL to harvest")
    ap.add_argument("--scoped", action="store_true", help="Prefer main content container (default)")
    ap.add_argument("--whole", action="store_true", help="Use whole page body instead of scoped")
    ap.add_argument("--diagnostics", action="store_true", help="Include simple resource counts")
    ap.add_argument("--json", help="Write full JSON to this path")
    ap.add_argument("--csv", help="Write summary CSV to this path")
    ap.add_argument("--timeout", type=int, default=30)
    ap.add_argument("--user-agent", dest="ua")
    args = ap.parse_args()

    scoped = True
    if args.whole: scoped = False
    elif args.scoped: scoped = True

    try:
        result = harvest(args.url, scoped=scoped, diagnostics=args.diagnostics, timeout=args.timeout, user_agent=args.ua)
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    base = filename_base(result["meta"]["domain"], "scoped" if result["meta"]["scoped"] else "whole")

    if args.json:
        write_json(args.json, result)
        print(f"Wrote JSON: {args.json}")
    if args.csv:
        write_csv(args.csv, to_csv_rows(result))
        print(f"Wrote CSV: {args.csv}")

    if not args.json and not args.csv:
        # default: print JSON to stdout
        print(json.dumps(result, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()
