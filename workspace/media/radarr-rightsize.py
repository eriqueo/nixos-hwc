#!/usr/bin/env python3
"""
radarr-rightsize — find movies whose file is oversized for its runtime, and
replace them through Radarr with a smaller release.

WHY THIS EXISTS
    Measured 2026-08-24 on hwc-server: every Radarr quality definition had
    maxSize = None (unlimited), so Radarr grabbed whatever the indexer offered.
    47 of 323 movies held a file over 10 GB, 757 GB in total, including
    38 Mb/s BluRay REMUX files and two raw BR-DISK rips.

    Absolute size is the wrong test — a 202-minute film is legitimately bigger
    than a 94-minute one. The test used here is the SIZE RATE in MB per minute
    of runtime, which is the same unit Radarr's own quality definitions use.

HOW IT REPLACES A FILE
    It never deletes anything. For each candidate it runs Radarr's interactive
    search and grabs one specific release; Radarr replaces the existing file
    when that download imports. If nothing suitable exists the movie is
    reported and left alone.

    Grabbing a specific release bypasses Radarr's upgrade-only rule, which is
    what makes a downgrade possible at all — a plain MoviesSearch will not
    replace an in-profile file with a smaller one.

    THE RESOLUTION FLOOR IS THE SAFETY RULE. A replacement is never below the
    resolution already held. Measured live on 2026-08-24, without that floor
    "My Man Godfrey" resolved to a 1.1 GB DVDRip: the HD-1080p profile carries
    an SD-Fallback group, so DVD counted as allowed, and no 1080p release fit
    the 45 MB/min cap for a 94-minute film. With the floor it resolves to a
    7.8 GB Bluray-1080p instead.

    Choice is two-tier. Tier 1 takes the LARGEST release under the cap, so the
    cap buys the best quality it can. Tier 2 applies when nothing fits: it
    takes the SMALLEST release at or above the current resolution, and labels
    the row "over-cap" so an unreachable target is visible rather than silent.

USAGE
    radarr-rightsize.py                       # report only, changes nothing
    radarr-rightsize.py --max-rate 40         # flag anything over 40 MB/min
    radarr-rightsize.py --apply --limit 5     # dry run: show what it would grab
    radarr-rightsize.py --apply --yes --limit 5   # actually grab 5
    radarr-rightsize.py --set-max-size --yes  # cap FUTURE grabs (prevention)

    Every mode is a dry run until --yes. --limit defaults to 5 so one run
    cannot flood the indexers; re-run to continue through the list.
"""

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request

CONFIG_XML = "/opt/radarr/config/config.xml"
BASE = "http://127.0.0.1:7878/api/v3"

# Cap for FUTURE grabs, in MB per minute of runtime, written by --set-max-size.
# A 120-minute film at 40 MB/min lands near 4.8 GB, about 5.3 Mb/s of video.
# Qualities absent from this map keep whatever maxSize they already have.
FUTURE_MAX_SIZE = {
    "HDTV-720p": 20.0,
    "WEBDL-720p": 20.0,
    "WEBRip-720p": 20.0,
    "Bluray-720p": 25.0,
    "HDTV-1080p": 35.0,
    "WEBDL-1080p": 40.0,
    "WEBRip-1080p": 40.0,
    "Bluray-1080p": 45.0,
    "HDTV-2160p": 70.0,
    "WEBDL-2160p": 80.0,
    "WEBRip-2160p": 80.0,
    "Bluray-2160p": 100.0,
}

MB = 1024 * 1024
GB = 1024 * 1024 * 1024


class RadarrError(RuntimeError):
    pass


def read_api_key(path):
    with open(path, "r", encoding="utf-8") as fh:
        m = re.search(r"<ApiKey>([a-f0-9]+)</ApiKey>", fh.read())
    if not m:
        raise RadarrError(f"no <ApiKey> in {path}")
    return m.group(1)


def api(key, path, method="GET", body=None, timeout=180):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{BASE}/{path}",
        data=data,
        method=method,
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raise RadarrError(f"{method} {path} -> {e.code} {e.read()[:300]!r}") from e


def api_list(key, path, **kw):
    """api() for an endpoint that must answer with a list.

    A 200 with an empty body decodes to None, which reads as "no items" but is
    really "no answer". Failing here keeps that from becoming an empty report
    that looks like a clean library.
    """
    got = api(key, path, **kw)
    if not isinstance(got, list):
        raise RadarrError(f"GET {path} -> expected a list, got {type(got).__name__}")
    return got


def profile_allows(profile, quality_name):
    """True if quality_name is an allowed quality in this profile.

    Profile items are either a quality or a named group holding qualities;
    a group is allowed as a whole, so its members are checked too.
    """
    for item in profile.get("items", []):
        if not item.get("allowed"):
            continue
        q = item.get("quality")
        if q and q.get("name") == quality_name:
            return True
        for sub in item.get("items") or []:
            sq = sub.get("quality")
            if sq and sq.get("name") == quality_name:
                return True
    return False


def size_rate(size_bytes, runtime_min):
    """MB per minute of runtime. Returns None when runtime is unknown."""
    if not runtime_min:
        return None
    return size_bytes / MB / runtime_min


def find_candidates(movies, profiles, max_rate, min_size_gb):
    out = []
    for m in movies:
        if not m.get("hasFile") or not m.get("movieFile"):
            continue
        f = m["movieFile"]
        size = f.get("size") or 0
        if size < min_size_gb * GB:
            continue
        rate = size_rate(size, m.get("runtime"))
        if rate is None or rate <= max_rate:
            continue
        target = max_rate * MB * m["runtime"]
        out.append(
            {
                "movie": m,
                "file": f,
                "size": size,
                "rate": rate,
                "quality": f["quality"]["quality"]["name"],
                "profile": profiles.get(m["qualityProfileId"], {}),
                "target_bytes": target,
                "saving": max(0, size - target),
            }
        )
    out.sort(key=lambda c: -c["saving"])
    return out


def pick_release(key, cand, max_rate, require_in_profile, allow_lower_res, shrink_ratio):
    """Choose a replacement, never below the resolution already held.

    The resolution floor is the important rule. Measured live on 2026-08-24:
    without it, "My Man Godfrey" resolved to a 1.1 GB DVDRip, because the
    HD-1080p profile carries an SD-Fallback group and no 1080p release fit the
    45 MB/min cap for a 94-minute film. Shrinking a REMUX to a DVDRip is not
    right-sizing, it is throwing the movie away.

    Two tiers, in order:
      1. the LARGEST release that fits under the cap — best quality the cap buys
      2. if none fits, the SMALLEST release at or above the current resolution
         that is still a real shrink — the cap is unreachable, so take the best
         available reduction and say so
    """
    movie = cand["movie"]
    cap = max_rate * MB * movie["runtime"]
    cur_res = ((cand["file"].get("quality") or {}).get("quality") or {}).get("resolution") or 0
    try:
        releases = api_list(key, f"release?movieId={movie['id']}", timeout=300)
    except RadarrError as e:
        return None, None, f"search failed: {e}"
    if not releases:
        return None, None, "no releases returned"

    eligible = []
    for r in releases:
        if r.get("rejected"):
            continue
        size = r.get("size") or 0
        # Must be a real shrink, not a rounding difference.
        if size <= 0 or size > cand["size"] * shrink_ratio:
            continue
        q = (r.get("quality") or {}).get("quality") or {}
        if not allow_lower_res and (q.get("resolution") or 0) < cur_res:
            continue
        if require_in_profile and not profile_allows(cand["profile"], q.get("name")):
            continue
        eligible.append(r)

    if not eligible:
        return None, None, f"no release at {cur_res or '?'}p smaller than {cand['size'] / GB:.1f} GB"

    under = [r for r in eligible if (r.get("size") or 0) <= cap]
    if under:
        under.sort(key=lambda r: -(r.get("size") or 0))
        return under[0], "under-cap", None
    eligible.sort(key=lambda r: (r.get("size") or 0))
    return eligible[0], "over-cap", None


def queued_movie_ids(key):
    """Movie ids with a download already in the queue.

    Grabbing is not idempotent — a second grab starts a second download — so a
    movie already in the queue is skipped rather than grabbed again.
    """
    ids = set()
    page = 1
    while True:
        q = api(key, f"queue?page={page}&pageSize=100&includeMovie=false")
        recs = (q or {}).get("records") or []
        for rec in recs:
            if rec.get("movieId"):
                ids.add(rec["movieId"])
        if len(recs) < 100:
            break
        page += 1
    return ids


def cmd_report(args, movies, profiles):
    cands = find_candidates(movies, profiles, args.max_rate, args.min_size)
    total_now = sum(c["size"] for c in cands)
    total_saving = sum(c["saving"] for c in cands)
    print(
        f"{len(movies)} movies in Radarr; {len(cands)} over "
        f"{args.max_rate:g} MB/min and at least {args.min_size:g} GB\n"
    )
    print(f"{'GB':>6} {'MB/min':>7} {'->GB':>6} {'QUALITY':<15} {'PROFILE':<17} {'INPROF':<7} TITLE")
    for c in cands:
        inprof = "yes" if profile_allows(c["profile"], c["quality"]) else "NO"
        print(
            f"{c['size'] / GB:6.1f} {c['rate']:7.1f} {c['target_bytes'] / GB:6.1f} "
            f"{c['quality']:<15} {c['profile'].get('name', '?'):<17} {inprof:<7} {c['movie']['title'][:40]}"
        )
    print(
        f"\nheld now: {total_now / GB:.0f} GB   "
        f"ceiling at {args.max_rate:g} MB/min: {(total_now - total_saving) / GB:.0f} GB   "
        f"recoverable: {total_saving / GB:.0f} GB"
    )
    print("\nINPROF=NO means the current file is not allowed by its own profile;")
    print("those replace most reliably. Nothing was changed. Add --apply --yes to act.")
    return cands


def cmd_set_max_size(args, key):
    defs = api_list(key, "qualitydefinition")
    changed = []
    for d in defs:
        name = d["quality"]["name"]
        want = FUTURE_MAX_SIZE.get(name)
        if want is None or d.get("maxSize") == want:
            continue
        changed.append((name, d.get("maxSize"), want))
        d["maxSize"] = want
    if not changed:
        print("quality definitions already capped; nothing to do")
        return
    print("maxSize (MB/min) changes:")
    for name, old, new in changed:
        print(f"  {name:<16} {str(old):>8} -> {new}")
    if not args.yes:
        print("\ndry run. Re-run with --yes to write these.")
        return
    api(key, "qualitydefinition/update", method="PUT", body=defs)
    print(f"\nwrote {len(changed)} quality definitions. Future grabs are capped.")


def cmd_apply(args, key, movies, profiles):
    cands = find_candidates(movies, profiles, args.max_rate, args.min_size)
    if not cands:
        print("no candidates; nothing to do")
        return 0
    in_queue = queued_movie_ids(key)
    acted = skipped = 0
    for c in cands:
        if acted >= args.limit:
            print(f"\nreached --limit {args.limit}; {len(cands) - acted - skipped} candidates left.")
            print("Re-run to continue. The limit exists so a batch cannot flood your indexers.")
            break
        m = c["movie"]
        title = m["title"][:44]
        if not m.get("monitored"):
            print(f"SKIP  {title:<44} unmonitored")
            skipped += 1
            continue
        if m["id"] in in_queue:
            print(f"SKIP  {title:<44} already downloading")
            skipped += 1
            continue

        rel, tier, why = pick_release(
            key, c, args.max_rate, not args.any_quality,
            args.allow_lower_resolution, args.shrink_ratio,
        )
        if rel is None:
            print(f"SKIP  {title:<44} {why}")
            skipped += 1
            time.sleep(args.delay)
            continue

        newsize = rel["size"] / GB
        line = (
            f"{'GRAB' if args.yes else 'WOULD'}  {title:<44} "
            f"{c['size'] / GB:.1f} -> {newsize:.1f} GB  {tier:<9} "
            f"[{(rel.get('quality') or {}).get('quality', {}).get('name')}] {rel.get('title', '')[:52]}"
        )
        print(line)
        if args.yes:
            try:
                api(key, "release", method="POST", body={"guid": rel["guid"], "indexerId": rel["indexerId"]})
            except RadarrError as e:
                print(f"      FAILED: {e}")
                skipped += 1
                time.sleep(args.delay)
                continue
        acted += 1
        time.sleep(args.delay)

    print(f"\n{'grabbed' if args.yes else 'would grab'}: {acted}, skipped: {skipped}")
    if not args.yes:
        print("dry run. Re-run with --yes to grab.")
    else:
        print("Radarr replaces each existing file when its download imports.")
        print("Watch Activity > Queue, and re-run the report afterwards to confirm.")
    return acted


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--api-key", help="Radarr API key (default: read from config.xml)")
    p.add_argument("--config", default=CONFIG_XML, help=f"Radarr config.xml (default {CONFIG_XML})")
    p.add_argument("--max-rate", type=float, default=45.0,
                   help="size ceiling in MB per minute of runtime (default 45)")
    p.add_argument("--min-size", type=float, default=8.0,
                   help="ignore files smaller than this many GB (default 8)")
    p.add_argument("--limit", type=int, default=5,
                   help="most movies to act on in one run (default 5); protects indexers")
    p.add_argument("--delay", type=float, default=5.0,
                   help="seconds between indexer searches (default 5)")
    p.add_argument("--any-quality", action="store_true",
                   help="allow a replacement whose quality is outside the movie's profile")
    p.add_argument("--allow-lower-resolution", action="store_true",
                   help="DANGEROUS: permit a replacement below the resolution already held. "
                        "Without this, a 1080p file is only ever replaced by 1080p or better.")
    p.add_argument("--shrink-ratio", type=float, default=0.85,
                   help="a replacement must be at most this fraction of the current file "
                        "(default 0.85); stops near-identical re-downloads")
    p.add_argument("--apply", action="store_true", help="grab replacements")
    p.add_argument("--set-max-size", action="store_true",
                   help="cap FUTURE grabs by writing maxSize into the quality definitions")
    p.add_argument("--yes", action="store_true", help="actually write; without it every mode is a dry run")
    args = p.parse_args()

    try:
        key = args.api_key or read_api_key(args.config)
    except (OSError, RadarrError) as e:
        print(f"cannot read API key: {e}", file=sys.stderr)
        return 2

    try:
        if args.set_max_size:
            cmd_set_max_size(args, key)
            if not args.apply:
                return 0
        movies = api_list(key, "movie")
        profiles = {p["id"]: p for p in api_list(key, "qualityprofile")}
        if args.apply:
            cmd_apply(args, key, movies, profiles)
        else:
            cmd_report(args, movies, profiles)
    except RadarrError as e:
        print(f"radarr: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
