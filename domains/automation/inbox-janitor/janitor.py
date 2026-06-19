#!/usr/bin/env python3
"""inbox-janitor — drain ~/000_inbox/downloads per _inbox-routing.yaml.

Design (hexagonal):
  CORE   classify() is pure: (filename, source_host) + config -> Decision. No I/O.
  EDGES  load config, stat the tree, move/rename files. All side effects live here.

Safety contract:
  - DRY-RUN BY DEFAULT. Nothing moves unless --apply is passed.
  - HOST-GUARDED. Refuses to --apply on any host but meta.owner_host (the single-writer
    rule that keeps two machines from racing the same Syncthing path). Override: --force.
  - FAIL-LOUD. Unmatched files go to fallback (_review), never deleted, never guessed.
  - Renaming is conservative: grandfathered prefixes are left exactly as-is.
  - Only LOOSE files at the root of downloads/ are swept; the organized domain folders
    (datax/, business/, …) are never touched, so the pass is idempotent.
"""
from __future__ import annotations
import argparse, os, re, shutil, socket, sys
from dataclasses import dataclass
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("inbox-janitor: PyYAML not available (nix: python3.withPackages(ps:[ps.pyyaml]))")


# ---------------------------------------------------------------- CORE (pure) --
@dataclass(frozen=True)
class Decision:
    kind: str            # 'secrets' | 'junk' | 'route' | 'fallback'
    domain: str | None = None
    dest: Path | None = None     # final directory the file belongs in
    reason: str = ""


def _ext(name: str) -> str:
    n = name.lower()
    for e in (".tar.gz", ".tar.bz2", ".tgz"):
        if n.endswith(e):
            return e.lstrip(".")
    return n.rsplit(".", 1)[-1] if "." in n else ""


def _match(m: dict, name: str, source_host: str | None) -> bool:
    if "name_glob" in m and not Path(name).match(m["name_glob"]):
        return False
    if "name_regex" in m and not re.search(m["name_regex"], name, re.I):
        return False
    if "ext" in m and _ext(name) not in [e.lower() for e in m["ext"]]:
        return False
    if "source_host" in m:
        if not source_host or source_host not in m["source_host"]:
            return False
    return True


def classify(name: str, source_host: str | None, cfg: dict) -> Decision:
    """Pure: decide where a single file belongs. quarantine > rules > fallback."""
    for q in cfg.get("quarantine", []):
        if _match(q["match"], name, source_host):
            d = cfg["secrets_dir"] if q["action"] == "secrets" else cfg["junk_dir"]
            return Decision(q["action"], dest=Path(d), reason=f"quarantine:{q['action']}")
    for r in cfg.get("rules", []):
        if _match(r["match"], name, source_host):
            dom = cfg["domains"][r["domain"]]
            base = Path(dom["destination"])
            cls = cfg["class_map"][r["domain"]].get(r["class"], r["class"])
            return Decision("route", domain=r["domain"], dest=base / cls,
                            reason=f"{r['domain']}/{r['class']}")
    return Decision("fallback", dest=Path(cfg["fallback"]["dir"]), reason="no rule matched")


def target_name(name: str, cfg: dict) -> str:
    """snake_case new names; leave grandfathered kebab families untouched."""
    if any(name.startswith(p) for p in cfg["meta"].get("grandfathered_prefixes", [])):
        return name
    stem, dot, ext = name.partition(".")
    norm = re.sub(r"[^a-z0-9]+", "_", stem.lower()).strip("_")
    return f"{norm}{dot}{ext}" if norm else name


# ---------------------------------------------------------------- EDGES (I/O) --
def source_host_of(p: Path) -> str | None:
    """Best-effort origin: GNOME/KDE stamp the download URL in an xattr."""
    for attr in ("user.xdg.origin.url", "user.xdg.referrer.url"):
        try:
            url = os.getxattr(str(p), attr).decode(errors="replace")
            m = re.search(r"https?://([^/]+)/", url)
            if m:
                return m.group(1)
        except OSError:
            pass
    return None


def unique(dest_dir: Path, name: str) -> Path:
    t = dest_dir / name
    if not t.exists():
        return t
    stem, dot, ext = name.partition(".")
    i = 2
    while (dest_dir / f"{stem}_{i}{dot}{ext}").exists():
        i += 1
    return dest_dir / f"{stem}_{i}{dot}{ext}"


def run(cfg: dict, apply: bool, log) -> int:
    downloads = Path(cfg["meta"]["inbox_root"]) / "downloads"
    moved = 0
    for entry in sorted(downloads.iterdir()):
        if entry.is_dir() or entry.name.startswith("."):
            continue
        dec = classify(entry.name, source_host_of(entry), cfg)
        assert dec.dest is not None  # classify() always sets a destination
        new_name = entry.name if dec.kind in ("secrets", "junk") else target_name(entry.name, cfg)
        dest = unique(dec.dest, new_name)
        log(f"[{dec.reason:28}] {entry.name}  ->  {dest}")
        if apply:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(entry), str(dest))
        moved += 1
    log(f"{'APPLIED' if apply else 'DRY-RUN'}: {moved} loose file(s) at downloads/ root.")
    return moved


def main() -> None:
    ap = argparse.ArgumentParser(description="Drain ~/000_inbox/downloads per _inbox-routing.yaml")
    ap.add_argument("--config", default=str(Path.home() / "000_inbox/_inbox-routing.yaml"))
    ap.add_argument("--apply", action="store_true", help="actually move files (default: dry-run)")
    ap.add_argument("--force", action="store_true", help="bypass the owner-host guard")
    args = ap.parse_args()

    cfg = yaml.safe_load(Path(args.config).read_text())
    owner = cfg["meta"]["owner_host"]
    if args.apply and not args.force and socket.gethostname() != owner:
        sys.exit(f"inbox-janitor: refusing to --apply on '{socket.gethostname()}' "
                 f"(owner_host={owner}). Use --force only if you know no other mover runs.")
    run(cfg, args.apply, print)


if __name__ == "__main__":
    main()
