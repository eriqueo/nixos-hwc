#!/usr/bin/env python3
"""
sonarr-rightsize — find episode files that are oversized for their runtime, and
replace them through Sonarr with a smaller release at the same resolution.

WHY THIS EXISTS
    Measured 2026-09-09 on hwc-server: every Sonarr quality definition had
    maxSize = None, because the TRaSH `series` guide data sets only a per-tier
    minimum and gates quality with custom formats instead of size. Sonarr
    therefore took whatever the indexer offered. Parks and Recreation held 122
    WEBRip-1080p files at a median 2.2 GB for a 21-minute episode — 100 MB/min —
    while a 1.01 GB WEBDL-1080p of the same episode sat in the release list,
    rejected only by the upgrade-only rule.

    The caps are now set (domains/media/recyclarr/parts/config.nix), but a cap
    only gates FUTURE grabs. This tool is for the files already on disk.

    Absolute size is the wrong test — a 63-minute Band of Brothers episode is
    legitimately bigger than a 7-minute Bluey. The test is the SIZE RATE in MB
    per minute, the same unit the quality definitions use.

RUNTIME COMES FROM THE FILE, NOT THE SERIES
    Sonarr's series-level `runtime` is a rounded nominal value: Parks reads 25
    when its episodes are 21:30. Rating a 21-minute file against 25 minutes
    understates its rate by 16%, and for short-form shows the error is worse —
    Schoolhouse Rock reads 3. This tool uses mediaInfo.runTime per file and
    SKIPS any file without it rather than falling back, because an unknown
    runtime produces a low rate, and a low rate reads as "this file is fine".
    Unknown is reported as CANNOT VERIFY, never as a pass.

HOW IT REPLACES A FILE
    It never deletes anything. For each candidate it runs Sonarr's interactive
    search and grabs one specific release; Sonarr replaces the existing file
    when that download imports. If nothing suitable exists the episode is
    reported and left alone.

    Grabbing a specific release bypasses Sonarr's upgrade-only rule, which is
    what makes a downgrade possible at all — a plain EpisodeSearch will not
    replace an in-profile file with a smaller one.

    THE RESOLUTION FLOOR IS THE SAFETY RULE. A replacement is never below the
    resolution already held. The HD-1080p profile carries an SD-Fallback group,
    so without the floor a 2.2 GB 1080p file resolves happily to a 180 MB XviD
    rip — that is not right-sizing, it is throwing the episode away.

    Season packs are excluded. A pack's size covers a whole season, so
    comparing it against one episode's size is meaningless, and grabbing one to
    replace a single file pulls down episodes that were never candidates.

USAGE
    sonarr-rightsize.py                        # report only, changes nothing
    sonarr-rightsize.py --max-rate 60          # flag anything over 60 MB/min
    sonarr-rightsize.py --series "Parks"       # limit to matching series
    sonarr-rightsize.py --apply --limit 5      # dry run: show what it would grab
    sonarr-rightsize.py --apply --yes --limit 5    # actually grab 5

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

CONFIG_XML = "/opt/sonarr/config/config.xml"
BASE = "http://127.0.0.1:8989/api/v3"

MB = 1000 * 1000
GB = 1000 * 1000 * 1000

# Default flag threshold in MB per minute. 60 sits above the p90 of every 1080p
# tier this library holds (WEBDL 66, HDTV 58, WEBRip 95 skewed by the Parks
# bloat) without catching the normal case: the 1.7 GB AMZN WEB-DL grabbed on
# 2026-09-09 measures 77 and IS caught, which is intended — it is a 22-minute
# sitcom episode and a 1.1 GB WEB-DL of the same show measures 49.
DEFAULT_MAX_RATE = 60.0

# Skip files already smaller than this. Chasing 200 MB files costs indexer
# queries and returns nothing worth the bandwidth of re-downloading.
DEFAULT_MIN_SIZE_GB = 0.7

# A replacement must be at most this fraction of the current file, so a 3%
# difference does not trigger a re-download.
DEFAULT_SHRINK_RATIO = 0.85


# Rejections that exist ONLY to stop a downgrade, and which this tool is for
# overriding. Every OTHER rejection is a real quality or policy judgement and
# is honoured — that distinction is the safety boundary of the whole tool.
#
# Getting this wrong in either direction is bad in a different way. Discard all
# rejected releases and the tool finds nothing: measured 2026-09-09, the first
# run resolved 1 of 122 Parks episodes while a 1.01 GB WEBDL-1080p sat there
# rejected as "equal or higher Custom Format score". Ignore rejections entirely
# and it will happily grab the x265 and LQ releases the custom formats exist to
# keep out, and the blocklisted .exe from the same evening.
OVERRIDABLE_REJECTIONS = (
    "existing file on disk is of equal or higher preference",
    "existing file on disk has a equal or higher custom format score",
    "existing file on disk has an equal or higher custom format score",
    "release in queue is of equal or higher preference",
    "release in queue has an equal or higher custom format score",
)


def overridable(release):
    """True if this release was rejected ONLY by the upgrade-only rule.

    Requires EVERY rejection to be overridable. A release rejected for both
    "equal or higher preference" AND "x265 score below minimum" is not a
    downgrade we want — one disqualifying reason is enough.
    """
    reasons = release.get("rejections") or []
    if not reasons:
        return True
    for reason in reasons:
        text = (reason if isinstance(reason, str) else str(reason)).lower()
        if not any(ok in text for ok in OVERRIDABLE_REJECTIONS):
            return False
    return True


class SonarrError(RuntimeError):
    pass


def read_api_key(path):
    with open(path, "r", encoding="utf-8") as fh:
        m = re.search(r"<ApiKey>([a-f0-9]+)</ApiKey>", fh.read())
    if not m:
        raise SonarrError(f"no <ApiKey> in {path}")
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
        raise SonarrError(f"{method} {path} -> {e.code} {e.read()[:300]!r}") from e


def api_list(key, path, **kw):
    """api() for an endpoint that must answer with a list.

    A 200 with an empty body decodes to None, which reads as "no items" but is
    really "no answer". Failing here keeps that from becoming an empty report
    that looks like a clean library.
    """
    got = api(key, path, **kw)
    if not isinstance(got, list):
        raise SonarrError(f"GET {path} -> expected a list, got {type(got).__name__}")
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


def quality_rank(profile, quality_name):
    """Position of quality_name in the profile, best = highest number.

    Returns None when the quality is not in the profile at all.
    """
    rank = 0
    found = None
    for item in profile.get("items", []):
        q = item.get("quality")
        subs = item.get("items") or []
        if q:
            rank += 1
            if q.get("name") == quality_name:
                found = rank
        elif subs:
            rank += 1
            for sub in subs:
                sq = sub.get("quality")
                if sq and sq.get("name") == quality_name:
                    found = rank
    return found


def meets_cutoff(profile, quality_name):
    """True if this quality already satisfies the profile's upgrade cutoff.

    THIS IS THE ONE PRODUCER OF "good enough". The profile already declares it
    — Sonarr's cutoff means "stop upgrading once reached" — so reading it here
    keeps this tool from inventing a second, quieter definition that disagrees.

    Concretely: the Sonarr HD-1080p profile ranks WEB-DL top with the cutoff one
    rank below at Bluray-1080p, precisely so the ~250 GB of Bluray-sourced
    episodes here are satisfied and never chased down to a smaller WEB-DL. A
    hardcoded "skip Bluray" list here would drift from that the first time the
    profile changed. WEBRip and HDTV sit below the cutoff and stay in scope.
    """
    if not profile:
        return False
    cutoff_id = profile.get("cutoff")
    cutoff_name = None
    for item in profile.get("items", []):
        q = item.get("quality")
        if q and q.get("id") == cutoff_id:
            cutoff_name = q.get("name")
        elif item.get("id") == cutoff_id:
            cutoff_name = item.get("name")
    if cutoff_name is None:
        return False
    have = quality_rank(profile, quality_name)
    want = quality_rank(profile, cutoff_name)
    if have is None or want is None:
        return False
    return have >= want


def runtime_seconds(episode_file):
    """Seconds of video, from mediaInfo. None when it cannot be determined.

    None is a THIRD STATE, not a zero. Callers must exclude the file, never
    treat it as a low rate — see the module docstring.
    """
    mi = episode_file.get("mediaInfo") or {}
    rt = mi.get("runTime")
    if not rt:
        return None
    try:
        parts = [int(x) for x in rt.split(":")]
    except ValueError:
        return None
    while len(parts) < 3:
        parts.insert(0, 0)
    secs = parts[0] * 3600 + parts[1] * 60 + parts[2]
    # A two-minute "episode" is almost always a sample or a broken probe, and
    # dividing by it manufactures an enormous rate.
    return secs if secs >= 120 else None


def find_candidates(key, series_list, profiles, max_rate, min_size_gb, name_filter,
                    include_satisfied=False):
    """Episode files over the rate cap, plus counts of what was excluded."""
    out = []
    unrated = 0
    satisfied = 0
    for s in series_list:
        if name_filter and name_filter.lower() not in s["title"].lower():
            continue
        profile = profiles.get(s.get("qualityProfileId"))
        for f in api_list(key, f"episodefile?seriesId={s['id']}"):
            size = f.get("size") or 0
            if size < min_size_gb * GB:
                continue
            secs = runtime_seconds(f)
            if secs is None:
                unrated += 1
                continue
            rate = (size / MB) / (secs / 60)
            if rate <= max_rate:
                continue
            qname = ((f.get("quality") or {}).get("quality") or {}).get("name")
            if not include_satisfied and meets_cutoff(profile, qname):
                satisfied += 1
                continue
            out.append({
                "series": s,
                "profile": profile,
                "file": f,
                "size": size,
                "seconds": secs,
                "rate": rate,
            })
    out.sort(key=lambda c: -(c["size"] - c["seconds"] / 60 * max_rate * MB))
    return out, unrated, satisfied


def episode_ids_for_file(key, cand):
    """Episode ids this file covers. A file may hold a multi-episode airing."""
    ids = cand["file"].get("episodeIds")
    if ids:
        return ids
    eps = api_list(key, f"episode?seriesId={cand['series']['id']}")
    return [e["id"] for e in eps if e.get("episodeFileId") == cand["file"]["id"]]


def pick_release(key, cand, episode_id, max_rate, require_in_profile, shrink_ratio):
    """Choose a replacement, never below the resolution already held.

    Two tiers, in order:
      1. the LARGEST release that fits under the cap — best quality the cap buys
      2. if none fits, the SMALLEST release at or above the current resolution
         that is still a real shrink — the cap is unreachable, so take the best
         available reduction and say so
    """
    cap = max_rate * MB * (cand["seconds"] / 60)
    cur_res = ((cand["file"].get("quality") or {}).get("quality") or {}).get("resolution") or 0
    try:
        releases = api_list(key, f"release?episodeId={episode_id}", timeout=300)
    except SonarrError as e:
        return None, None, f"search failed: {e}"
    if not releases:
        return None, None, "no releases returned"

    eligible = []
    for r in releases:
        if r.get("rejected") and not overridable(r):
            continue
        # A season pack's size covers the whole season; comparing it to one
        # episode file is meaningless and grabbing it pulls down the rest.
        if r.get("fullSeason"):
            continue
        if r.get("episodeNumbers") and len(r["episodeNumbers"]) > 1:
            continue
        size = r.get("size") or 0
        if size <= 0 or size > cand["size"] * shrink_ratio:
            continue
        q = (r.get("quality") or {}).get("quality") or {}
        if (q.get("resolution") or 0) < cur_res:
            continue
        # Cross-check the parsed quality against the release TITLE. Sonarr
        # derives quality from the name, so a mis-named release defeats a floor
        # built on the parsed value. When the title states a resolution of its
        # own, believe the lower of the two.
        claimed = [int(m) for m in re.findall(r"\b(480|576|720|1080|2160)p?\b", r.get("title") or "")]
        if claimed and max(claimed) < cur_res:
            continue
        if require_in_profile and cand["profile"] and not profile_allows(cand["profile"], q.get("name")):
            continue
        eligible.append(r)

    if not eligible:
        return None, None, f"no single-episode release at {cur_res or '?'}p under {cand['size'] / GB:.1f} GB"

    under = [r for r in eligible if (r.get("size") or 0) <= cap]
    if under:
        under.sort(key=lambda r: -(r.get("size") or 0))
        return under[0], "under-cap", None
    eligible.sort(key=lambda r: (r.get("size") or 0))
    return eligible[0], "over-cap", None


def queued_episode_ids(key):
    """Episode ids with a download already in the queue."""
    q = api(key, "queue?pageSize=1000")
    ids = set()
    for r in (q or {}).get("records", []):
        if r.get("episodeId"):
            ids.add(r["episodeId"])
        for e in r.get("episodes") or []:
            ids.add(e["id"])
    return ids


def label(cand):
    f = cand["file"]
    rel = f.get("relativePath") or f.get("path") or "?"
    return f"{cand['series']['title'][:26]} {rel.split('/')[-1][:34]}"


def cmd_report(args, key, series_list, profiles):
    cands, unrated, satisfied = find_candidates(
        key, series_list, profiles, args.max_rate, args.min_size, args.series,
        args.include_satisfied,
    )
    if not cands:
        print(f"no file over {args.max_rate:.0f} MB/min; nothing to do")
        if unrated:
            print(f"({unrated} files CANNOT VERIFY — no usable mediaInfo runtime, excluded)")
        return 0

    by_series = {}
    for c in cands:
        t = c["series"]["title"]
        e = by_series.setdefault(t, {"n": 0, "size": 0, "excess": 0})
        e["n"] += 1
        e["size"] += c["size"]
        e["excess"] += c["size"] - (c["seconds"] / 60 * args.max_rate * MB)

    print(f"{len(cands)} files over {args.max_rate:.0f} MB/min, in {len(by_series)} series\n")
    print(f"{'series':<38} {'files':>5} {'held GB':>9} {'over GB':>9}")
    for t, e in sorted(by_series.items(), key=lambda x: -x[1]["excess"]):
        print(f"{t[:38]:<38} {e['n']:>5} {e['size'] / GB:>9.1f} {e['excess'] / GB:>9.1f}")
    total_excess = sum(e["excess"] for e in by_series.values())
    print(f"\nrecoverable at {args.max_rate:.0f} MB/min: {total_excess / GB:.0f} GB")
    print("This is the ARITHMETIC ceiling, not a promise — it assumes a suitable")
    print("smaller release exists for every file. Run --apply to see what resolves.")
    if satisfied:
        print(f"\n{satisfied} oversized files already MEET THE PROFILE CUTOFF and were left alone")
        print("(Bluray and better — shrinking those trades picture quality for space).")
        print("Pass --include-satisfied to rate them too.")
    if unrated:
        print(f"\n{unrated} files CANNOT VERIFY — no usable mediaInfo runtime, excluded from all counts.")
    return 0


def cmd_apply(args, key, series_list, profiles):
    cands, unrated, satisfied = find_candidates(
        key, series_list, profiles, args.max_rate, args.min_size, args.series,
        args.include_satisfied,
    )
    if not cands:
        print("no candidates; nothing to do")
        return 0
    in_queue = queued_episode_ids(key)
    acted = skipped = 0
    for c in cands:
        if acted >= args.limit:
            print(f"\nreached --limit {args.limit}; {len(cands) - acted - skipped} candidates left.")
            print("Re-run to continue. The limit exists so a batch cannot flood your indexers.")
            break
        name = label(c)
        if not c["series"].get("monitored"):
            print(f"SKIP  {name:<62} series unmonitored")
            skipped += 1
            continue
        ep_ids = episode_ids_for_file(key, c)
        if not ep_ids:
            print(f"SKIP  {name:<62} no episode maps to this file")
            skipped += 1
            continue
        if len(ep_ids) > 1:
            print(f"SKIP  {name:<62} multi-episode file")
            skipped += 1
            continue
        if ep_ids[0] in in_queue:
            print(f"SKIP  {name:<62} already downloading")
            skipped += 1
            continue

        rel, tier, why = pick_release(
            key, c, ep_ids[0], args.max_rate, not args.any_quality, args.shrink_ratio
        )
        if rel is None:
            print(f"SKIP  {name:<62} {why}")
            skipped += 1
            time.sleep(args.delay)
            continue

        line = (
            f"{'GRAB' if args.yes else 'WOULD'}  {name:<62} "
            f"{c['size'] / GB:.2f} -> {rel['size'] / GB:.2f} GB  {tier:<9} "
            f"[{(rel.get('quality') or {}).get('quality', {}).get('name')}]"
        )
        # Print AFTER the grab succeeds, never before. Printing first makes a
        # failed grab read as a successful one.
        if args.yes:
            try:
                api(key, "release", method="POST",
                    body={"guid": rel["guid"], "indexerId": rel["indexerId"]})
            except SonarrError as e:
                print(f"FAIL  {name:<62} grab rejected: {e}")
                skipped += 1
                time.sleep(args.delay)
                continue
        print(line)
        acted += 1
        time.sleep(args.delay)

    print(f"\n{'grabbed' if args.yes else 'would grab'}: {acted}, skipped: {skipped}")
    if satisfied:
        print(f"{satisfied} oversized files meet the profile cutoff and were left alone.")
    if unrated:
        print(f"{unrated} files CANNOT VERIFY — no usable mediaInfo runtime, excluded.")
    if not args.yes:
        print("dry run. Re-run with --yes to grab.")
    else:
        print("Sonarr replaces each existing file when its download imports.")
        print("Watch Activity > Queue, and re-run the report afterwards to confirm.")
    return acted


def main():
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--max-rate", type=float, default=DEFAULT_MAX_RATE,
                   help=f"flag files over this MB/min (default {DEFAULT_MAX_RATE:g})")
    p.add_argument("--min-size", type=float, default=DEFAULT_MIN_SIZE_GB,
                   help=f"ignore files smaller than this in GB (default {DEFAULT_MIN_SIZE_GB:g})")
    p.add_argument("--series", help="only series whose title contains this")
    p.add_argument("--apply", action="store_true", help="resolve and grab replacements")
    p.add_argument("--yes", action="store_true", help="actually grab; without it --apply is a dry run")
    p.add_argument("--limit", type=int, default=5, help="max grabs per run (default 5)")
    p.add_argument("--delay", type=float, default=2.0, help="seconds between indexer searches")
    p.add_argument("--shrink-ratio", type=float, default=DEFAULT_SHRINK_RATIO,
                   help="replacement must be at most this fraction of the current file")
    p.add_argument("--include-satisfied", action="store_true",
                   help="also rate files that already meet the profile cutoff (e.g. Bluray)")
    p.add_argument("--any-quality", action="store_true",
                   help="allow releases outside the series quality profile")
    p.add_argument("--config", default=CONFIG_XML)
    args = p.parse_args()

    try:
        key = read_api_key(args.config)
        series_list = api_list(key, "series")
        profiles = {pr["id"]: pr for pr in api_list(key, "qualityprofile")}
        if args.apply:
            return 0 if cmd_apply(args, key, series_list, profiles) >= 0 else 1
        return cmd_report(args, key, series_list, profiles)
    except SonarrError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
