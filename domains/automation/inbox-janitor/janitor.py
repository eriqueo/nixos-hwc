#!/usr/bin/env python3
"""inbox-janitor v2 — declarative file routing in a hexagonal frame.

Adopts the model of tfeldmann/organize (locations -> filters -> actions ->
templated destinations) but as dependency-free stdlib Python you own, so new
filters/actions are just registered functions — no pip package, no lock-in.

WHY THE REWRITE (what v1 got wrong):
  v1 classified by *domain/class* (datax/notes, business/admin) — a semantic
  guess from filename globs. Semantics-from-filenames is unreliable, so ~44% of
  files fell through to _review and the rest scattered across 148 folders.
  v2 routes on INTRINSIC, always-knowable attributes first (extension, mimetype,
  date, size). Those never miss, so _review shrinks to genuinely-unknown files.

ARCHITECTURE (hexagonal):
  CORE (pure, no I/O):
    - FILTERS registry: each filter is (FileMeta, param) -> dict|None.
        None = no match. dict = matched, plus any emitted template vars.
    - classify(): quarantine > rules (first match wins) > fallback. Pure.
    - render()/target_name(): build the new name from a template + vars. Pure.
  EDGES (all side effects, isolated):
    - gather(): stat + xattr + mimetype -> a FileMeta parsed once at the boundary.
    - apply_move(): mkdir + move + conflict handling.
    - republish(): tell Syncthing to re-index touched paths (the v1 sync bug).
        Late-bound: only fires if SYNCTHING_* env is injected by the unit.

SAFETY: dry-run by default; host-guarded (single-writer); fail-loud to _review.
"""
from __future__ import annotations

import argparse
import datetime as dt
import mimetypes
import os
import re
import shutil
import socket
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Optional

try:
    import yaml
except ImportError:
    sys.exit("inbox-janitor: PyYAML not available (nix: python3.withPackages(ps:[ps.pyyaml]))")


# ============================================================ CORE (pure) =====

@dataclass(frozen=True)
class FileMeta:
    """Untrusted file facts, parsed once at the edge. The core trusts this type."""
    path: Path
    name: str
    stem: str
    ext: str            # lowercase, no dot, compound-aware ("tar.gz")
    size: int
    mtime: dt.datetime
    ctime: dt.datetime
    mimetype: str       # "" if unknown
    source_host: Optional[str]


@dataclass(frozen=True)
class Decision:
    kind: str                       # 'quarantine' | 'route' | 'fallback'
    dest: Path                      # directory the file belongs in
    rename: bool = True
    reason: str = ""
    vars: dict = field(default_factory=dict)   # emitted template placeholders


COMPOUND_EXTS = (".tar.gz", ".tar.bz2", ".tar.xz", ".tgz")


def ext_of(name: str) -> str:
    n = name.lower()
    for e in COMPOUND_EXTS:
        if n.endswith(e):
            return e.lstrip(".")
    return n.rsplit(".", 1)[-1] if "." in n.strip(".") else ""


def stem_of(name: str, ext: str) -> str:
    return name[: -(len(ext) + 1)] if ext and name.lower().endswith("." + ext) else name


# ---- filter registry: the expansion seam. Add a filter = add a function. ----
FilterFn = Callable[[FileMeta, Any], Optional[dict]]
FILTERS: dict[str, FilterFn] = {}


def filt(name: str):
    def reg(fn: FilterFn) -> FilterFn:
        FILTERS[name] = fn
        return fn
    return reg


@filt("ext")
def _f_ext(m: FileMeta, param) -> Optional[dict]:
    wanted = [str(e).lower().lstrip(".") for e in param]
    return {} if m.ext in wanted else None


@filt("mimetype")
def _f_mimetype(m: FileMeta, param) -> Optional[dict]:
    # partial / prefix match, e.g. "image/" matches "image/png"
    prefixes = [param] if isinstance(param, str) else list(param)
    return {} if m.mimetype and any(m.mimetype.startswith(p) for p in prefixes) else None


@filt("name")
def _f_name(m: FileMeta, param: dict) -> Optional[dict]:
    n = m.name
    if "startswith" in param and not n.startswith(param["startswith"]):
        return None
    if "endswith" in param and not n.endswith(param["endswith"]):
        return None
    if "contains" in param and param["contains"] not in n:
        return None
    if "glob" in param and not Path(n).match(param["glob"]):
        return None
    if "iregex" in param:
        mo = re.search(param["iregex"], n, re.I)
        if not mo:
            return None
        return dict(mo.groupdict())
    if "regex" in param:
        mo = re.search(param["regex"], n)
        if not mo:
            return None
        return dict(mo.groupdict())
    return {}


@filt("size")
def _f_size(m: FileMeta, param: str) -> Optional[dict]:
    mo = re.match(r"\s*(>=|<=|>|<|==)\s*([\d.]+)\s*([kmgt]?b?)\s*$", str(param), re.I)
    if not mo:
        return None
    op, num, unit = mo.group(1), float(mo.group(2)), mo.group(3).lower()
    mult = {"": 1, "b": 1, "kb": 1e3, "k": 1e3, "mb": 1e6, "m": 1e6,
            "gb": 1e9, "g": 1e9, "tb": 1e12, "t": 1e12}.get(unit, 1)
    threshold = num * mult
    ok = {">=": m.size >= threshold, "<=": m.size <= threshold, ">": m.size > threshold,
          "<": m.size < threshold, "==": m.size == threshold}[op]
    return {} if ok else None


@filt("age")
def _f_age(m: FileMeta, param: dict) -> Optional[dict]:
    # {newer|older: "<N>d"} against mtime
    now = dt.datetime.now()
    age_days = (now - m.mtime).total_seconds() / 86400
    if "newer" in param and age_days > _days(param["newer"]):
        return None
    if "older" in param and age_days < _days(param["older"]):
        return None
    return {}


def _days(s) -> float:
    mo = re.match(r"\s*([\d.]+)\s*([dwmy]?)", str(s))
    if not mo:
        raise ValueError(f"bad age value: {s!r} (want e.g. '7d', '2w')")
    n = float(mo.group(1)); u = mo.group(2)
    return n * {"d": 1, "w": 7, "m": 30, "y": 365, "": 1}[u]


def match_block(m: FileMeta, block: dict) -> Optional[dict]:
    """AND across all filters in a match block; merge their emitted vars. Pure."""
    emitted: dict = {}
    for fname, param in block.items():
        fn = FILTERS.get(fname)
        if fn is None:
            raise KeyError(f"unknown filter '{fname}' (known: {sorted(FILTERS)})")
        out = fn(m, param)
        if out is None:
            return None
        emitted.update(out)
    return emitted


def classify(m: FileMeta, cfg: dict) -> Decision:
    """quarantine > rules (first match wins) > fallback. Pure."""
    dl = Path(cfg["meta"]["inbox_root"]) / "downloads"

    for q in cfg.get("quarantine", []):
        v = match_block(m, q["match"])
        if v is not None:
            return Decision("quarantine", dl / q["dest"], rename=q.get("rename", False),
                            reason=f"quarantine:{q['dest'].rstrip('/')}", vars=v)

    for r in cfg.get("rules", []):
        v = match_block(m, r["match"])
        if v is not None:
            return Decision("route", dl / r["dest"], rename=True,
                            reason=r.get("name", r["dest"].rstrip("/")), vars=v)

    fb = cfg["fallback"]["dest"]
    return Decision("fallback", dl / fb, rename=cfg["fallback"].get("rename", True),
                    reason="no rule matched")


# ---- naming (pure templating; no eval) --------------------------------------
def slugify(stem: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", stem.lower()).strip("_")


_TOKEN = re.compile(r"\{([\w.]+)\}")


def render(template: str, ctx: dict) -> str:
    def sub(mo):
        key = mo.group(1)
        if "." in key:
            head, attr = key.split(".", 1)
            val = ctx.get(head)
            return str(getattr(val, attr, "") if not isinstance(val, dict) else val.get(attr, ""))
        return str(ctx.get(key, ""))
    return _TOKEN.sub(sub, template)


def target_name(m: FileMeta, decision: Decision, cfg: dict) -> str:
    """New filename. Grandfathered prefixes & rename:false are left untouched."""
    if not decision.rename:
        return m.name
    if any(m.name.startswith(p) for p in cfg["meta"].get("grandfathered_prefixes", [])):
        return m.name
    date_field = cfg.get("date_field", "modified")
    date = (m.mtime if date_field == "modified" else m.ctime).date()
    ctx = {
        "date": date, "stem": m.stem, "slug": slugify(m.stem),
        "ext": ("." + m.ext) if m.ext else "", "extname": m.ext,
        "mimetype": m.mimetype, **decision.vars,
    }
    tmpl = cfg.get("naming", {}).get("template", "{date}_{slug}{ext}")
    out = render(tmpl, ctx)
    return out or m.name


# ============================================================ EDGES (I/O) =====

def gather(p: Path) -> FileMeta:
    st = p.stat()
    name = p.name
    ext = ext_of(name)
    mime = mimetypes.guess_type(name)[0] or ""
    return FileMeta(
        path=p, name=name, stem=stem_of(name, ext), ext=ext, size=st.st_size,
        mtime=dt.datetime.fromtimestamp(st.st_mtime),
        ctime=dt.datetime.fromtimestamp(getattr(st, "st_ctime", st.st_mtime)),
        mimetype=mime, source_host=source_host_of(p),
    )


def source_host_of(p: Path) -> Optional[str]:
    for attr in ("user.xdg.origin.url", "user.xdg.referrer.url"):
        try:
            url = os.getxattr(str(p), attr).decode(errors="replace")
            mo = re.search(r"https?://([^/]+)/", url)
            if mo:
                return mo.group(1)
        except OSError:
            pass
    return None


def unique(dest_dir: Path, name: str, on_conflict: str) -> Optional[Path]:
    t = dest_dir / name
    if not t.exists():
        return t
    if on_conflict == "skip":
        return None
    if on_conflict == "overwrite":
        return t
    stem, dot, ext = name.partition(".")          # rename_new (default): counter
    i = 2
    while (dest_dir / f"{stem}_{i}{dot}{ext}").exists():
        i += 1
    return dest_dir / f"{stem}_{i}{dot}{ext}"


def iter_files(cfg: dict, all_mode: bool, locations: Optional[list] = None):
    """Default: loose files at downloads/ root (idempotent drain).
    --all: walk the whole downloads tree (reclassify / preview).
    --from LOC: walk only the given location(s) — relative to downloads/ or
    absolute. Lets you re-sort a specific subtree (e.g. migrating old folders)
    without touching the rest. Destinations are still the downloads/ buckets."""
    dl = Path(cfg["meta"]["inbox_root"]) / "downloads"
    skip_dirs = {d.rstrip("/") for d in cfg.get("preview_skip_dirs", [])}
    if locations:
        roots = [Path(loc) if Path(loc).is_absolute() else dl / loc for loc in locations]
    elif all_mode:
        roots = [dl]
    else:
        for e in sorted(dl.iterdir()):
            if e.is_file() and not e.name.startswith("."):
                yield e
        return
    for base in roots:
        if not base.exists():
            continue
        for root, dirs, files in os.walk(base):
            dirs[:] = [d for d in dirs if not d.startswith(".") and d not in skip_dirs]
            for fn in files:
                if not fn.startswith("."):
                    yield Path(root) / fn


def _syncthing_apikey() -> Optional[str]:
    """Resolve the local Syncthing API key, in order:
    SYNCTHING_APIKEY env > SYNCTHING_APIKEY_FILE > <apikey> in SYNCTHING_CONFIG
    (default ~/.config/syncthing/config.xml). Lets the unit stay secret-free."""
    key = os.environ.get("SYNCTHING_APIKEY")
    if key:
        return key.strip()
    keyfile = os.environ.get("SYNCTHING_APIKEY_FILE")
    if keyfile:
        try:
            return Path(keyfile).read_text().strip()
        except OSError:
            return None
    cfgpath = Path(os.environ.get("SYNCTHING_CONFIG",
                                  str(Path.home() / ".config/syncthing/config.xml")))
    try:
        mo = re.search(r"<apikey>([^<]+)</apikey>", cfgpath.read_text())
        return mo.group(1).strip() if mo else None
    except OSError:
        return None


def republish(touched: set[Path], cfg: dict, log) -> None:
    """Rescan touched subpaths so Syncthing re-indexes janitor moves immediately
    (fixes v1's up-to-1h index lag). Best-effort; never fails the drain.
    Sensible local defaults; override via SYNCTHING_URL / _FOLDER / _APIKEY*."""
    url = os.environ.get("SYNCTHING_URL", "http://127.0.0.1:8384")
    folder = os.environ.get("SYNCTHING_FOLDER", "000_inbox")
    key = _syncthing_apikey()
    if not (url and folder and key and touched):
        return
    root = Path(cfg["meta"]["inbox_root"])
    for d in sorted(touched):
        sub = str(d.relative_to(root))
        req = urllib.request.Request(
            f"{url}/rest/db/scan?folder={folder}&sub={urllib.parse.quote(sub)}",
            method="POST", headers={"X-API-Key": key})
        try:
            urllib.request.urlopen(req, timeout=10).read()
        except Exception as e:           # best-effort: never fail the drain on this
            log(f"  republish WARN: rescan of {sub} failed: {e}")


# ============================================================ ORCHESTRATION ===

def run(cfg: dict, apply: bool, all_mode: bool, log, locations: Optional[list] = None) -> dict:
    stats: dict[str, int] = {}
    touched: set[Path] = set()
    n = 0
    for path in iter_files(cfg, all_mode, locations):
        m = gather(path)
        dec = classify(m, cfg)
        new_name = target_name(m, dec, cfg)
        bucket = dec.dest.name
        stats[bucket] = stats.get(bucket, 0) + 1
        n += 1
        target = unique(dec.dest, new_name, cfg.get("on_conflict", "rename_new"))
        if target is None:
            log(f"[{dec.reason:14}] SKIP (conflict)  {m.name}")
            continue
        log(f"[{dec.reason:14}] {m.name}  ->  {target.relative_to(Path(cfg['meta']['inbox_root']))}")
        if apply:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(target))
            touched.add(target.parent)
    log("")
    log(f"{'APPLIED' if apply else 'DRY-RUN'} {'(--all: whole tree)' if all_mode else '(loose root only)'}: {n} file(s)")
    for b in sorted(stats, key=lambda k: -stats[k]):
        log(f"  {stats[b]:5}  {b}/")
    if apply:
        republish(touched, cfg, log)
    return stats


def main() -> None:
    ap = argparse.ArgumentParser(description="Drain ~/000_inbox/downloads (declarative, hexagonal)")
    ap.add_argument("--config", default=str(Path.home() / "000_inbox/_inbox-routing.yaml"))
    ap.add_argument("--apply", action="store_true", help="actually move files (default: dry-run)")
    ap.add_argument("--all", action="store_true", help="walk whole tree, not just loose root (preview/migration)")
    ap.add_argument("--from", dest="locations", action="append", metavar="LOC",
                    help="walk only this location (rel to downloads/ or absolute); repeatable")
    ap.add_argument("--force", action="store_true", help="bypass owner-host guard")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.config).read_text())
    owner = cfg["meta"]["owner_host"]
    if args.apply and not args.force and socket.gethostname() != owner:
        sys.exit(f"inbox-janitor: refusing to --apply on '{socket.gethostname()}' "
                 f"(owner_host={owner}). Use --force only if no other mover runs.")
    run(cfg, args.apply, args.all, print, args.locations)


if __name__ == "__main__":
    main()
