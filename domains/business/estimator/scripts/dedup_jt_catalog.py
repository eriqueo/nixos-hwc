#!/usr/bin/env python3
"""JT org catalog dedup analysis.

Groups the 5,130+ JT org catalog items by exact name, picks one keeper per name,
and marks the rest as deletion candidates.

Keeper selection priority:
  1. Item ID appears in CSV export (JT UI-visible primary)
  2. Has pricing populated (unitCost or unitPrice)
  3. Oldest createdAt

Output:
  jt_dedup_keepers.json   — {name: {keeper_id, ...}}
  jt_dedup_deletions.json — [{id, name, reason_not_keeper}]
  Console report

Usage:
  python3 dedup_jt_catalog.py              # Use cached data
  python3 dedup_jt_catalog.py --refresh    # Re-fetch from PAVE API
"""

import argparse
import csv
import json
import os
import time
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

# ── Paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
CACHE_FILE = SCRIPT_DIR / "jt_catalog_cache.json"
CSV_FILE = SCRIPT_DIR / "catalog-2026-05-03.csv"
KEEPERS_FILE = SCRIPT_DIR / "jt_dedup_keepers.json"
DELETIONS_FILE = SCRIPT_DIR / "jt_dedup_deletions.json"
ENV_FILE = "/run/hwc-sys-mcp/env"

PAVE_URL = "https://api.jobtread.com/pave"
ORG_ID = "22Nm3uFevXMb"
USER_ID = "22Nm3uFeRB7s"


# ── PAVE client ──────────────────────────────────────────────────────────────

def pave_request(grant_key: str, operations: dict) -> dict:
    envelope = {
        "query": {
            "$": {"grantKey": grant_key, "notify": False, "viaUserId": USER_ID},
            **operations,
        }
    }
    req = Request(
        PAVE_URL,
        data=json.dumps(envelope).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
    except HTTPError as e:
        body = e.read().decode()[:500]
        raise RuntimeError(f"PAVE HTTP {e.code}: {body}") from e
    if data.get("errors"):
        msgs = "; ".join(e.get("message", "?") for e in data["errors"])
        raise RuntimeError(f"PAVE error: {msgs}")
    return data


def fetch_jt_catalog(grant_key: str) -> list[dict]:
    """Fetch all org cost items with createdAt, paginating via where id > last."""
    all_items: list[dict] = []
    last_id = None
    page = 0
    while True:
        page += 1
        params: dict = {"size": 100, "sortBy": [{"field": ["id"], "order": "asc"}]}
        if last_id:
            params["where"] = {">": [{"field": ["id"]}, {"value": last_id}]}

        resp = pave_request(grant_key, {
            "organization": {
                "$": {"id": ORG_ID},
                "costItems": {
                    "$": params,
                    "nodes": {
                        "id": {},
                        "name": {},
                        "unitCost": {},
                        "unitPrice": {},
                        "description": {},
                        "createdAt": {},
                        "costCode": {"id": {}, "name": {}},
                        "costType": {"id": {}, "name": {}},
                        "unit": {"id": {}, "name": {}},
                    },
                },
            }
        })
        nodes = resp.get("organization", {}).get("costItems", {}).get("nodes", [])
        if not nodes:
            break
        all_items.extend(nodes)
        print(f"  Page {page}: {len(nodes)} items (total: {len(all_items)})")
        if len(nodes) < 100:
            break
        last_id = nodes[-1]["id"]
        time.sleep(0.3)
    return all_items


# ── CSV loader ───────────────────────────────────────────────────────────────

def load_csv_ids() -> set[str]:
    """Load the 797 primary item IDs from the CSV export."""
    if not CSV_FILE.exists():
        print(f"  WARNING: CSV not found at {CSV_FILE} — skipping CSV preference")
        return set()
    ids = set()
    with open(CSV_FILE, encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            item_id = row.get("Cost Item ID", "").strip()
            if item_id:
                ids.add(item_id)
    print(f"  Loaded {len(ids)} IDs from CSV export")
    return ids


# ── Dedup logic ──────────────────────────────────────────────────────────────

@dataclass
class ItemInfo:
    id: str
    name: str
    unit_cost: float | None
    unit_price: float | None
    created_at: str | None
    cost_code: str | None
    cost_type: str | None
    in_csv: bool
    has_pricing: bool

    @property
    def sort_key(self) -> tuple:
        """Lower = better keeper. CSV first, then pricing, then oldest."""
        return (
            0 if self.in_csv else 1,
            0 if self.has_pricing else 1,
            self.created_at or "9999",
        )


def analyze_duplicates(items: list[dict], csv_ids: set[str]) -> dict:
    """Group by name, pick keepers, mark deletions."""
    # Build ItemInfo objects
    by_name: dict[str, list[ItemInfo]] = defaultdict(list)
    for raw in items:
        cc = raw.get("costCode") or {}
        ct = raw.get("costType") or {}
        has_pricing = (raw.get("unitCost") is not None or raw.get("unitPrice") is not None)
        info = ItemInfo(
            id=raw["id"],
            name=raw.get("name", ""),
            unit_cost=raw.get("unitCost"),
            unit_price=raw.get("unitPrice"),
            created_at=raw.get("createdAt"),
            cost_code=cc.get("name"),
            cost_type=ct.get("name"),
            in_csv=raw["id"] in csv_ids,
            has_pricing=has_pricing,
        )
        by_name[info.name].append(info)

    keepers: dict[str, dict] = {}
    deletions: list[dict] = []
    stats = {
        "total": len(items),
        "unique_names": len(by_name),
        "singleton_names": 0,
        "duplicate_groups": 0,
        "items_to_keep": 0,
        "items_to_delete": 0,
        "deletions_in_csv": 0,
        "deletions_with_pricing": 0,
    }

    for name, group in sorted(by_name.items()):
        # Sort by keeper preference
        group.sort(key=lambda x: x.sort_key)
        keeper = group[0]

        keepers[name] = {
            "keeper_id": keeper.id,
            "in_csv": keeper.in_csv,
            "has_pricing": keeper.has_pricing,
            "created_at": keeper.created_at,
            "cost_code": keeper.cost_code,
            "cost_type": keeper.cost_type,
            "unit_cost": keeper.unit_cost,
            "unit_price": keeper.unit_price,
            "duplicate_count": len(group) - 1,
        }
        stats["items_to_keep"] += 1

        if len(group) == 1:
            stats["singleton_names"] += 1
        else:
            stats["duplicate_groups"] += 1

        for dupe in group[1:]:
            reasons = []
            if keeper.in_csv and not dupe.in_csv:
                reasons.append("keeper is in CSV export")
            elif not keeper.in_csv and not dupe.in_csv:
                if keeper.has_pricing and not dupe.has_pricing:
                    reasons.append("keeper has pricing")
                elif keeper.created_at and dupe.created_at and keeper.created_at < dupe.created_at:
                    reasons.append("keeper is older")
                else:
                    reasons.append("first in sort order")
            elif dupe.in_csv:
                reasons.append("multiple CSV entries — keeper scored higher")

            deletions.append({
                "id": dupe.id,
                "name": dupe.name,
                "in_csv": dupe.in_csv,
                "has_pricing": dupe.has_pricing,
                "created_at": dupe.created_at,
                "reason_not_keeper": "; ".join(reasons) if reasons else "duplicate",
            })
            stats["items_to_delete"] += 1
            if dupe.in_csv:
                stats["deletions_in_csv"] += 1
            if dupe.has_pricing:
                stats["deletions_with_pricing"] += 1

    return {"keepers": keepers, "deletions": deletions, "stats": stats}


# ── Reporting ────────────────────────────────────────────────────────────────

def print_report(result: dict, csv_ids: set[str]):
    stats = result["stats"]
    keepers = result["keepers"]
    deletions = result["deletions"]

    print("\n" + "=" * 70)
    print("JT CATALOG DEDUP REPORT")
    print("=" * 70)

    print(f"""
Total items:              {stats['total']:,}
Unique names:             {stats['unique_names']:,}
  Singletons (no dupes):  {stats['singleton_names']:,}
  Duplicate groups:       {stats['duplicate_groups']:,}
Items to keep:            {stats['items_to_keep']:,} (one per unique name)
Candidates for delete:    {stats['items_to_delete']:,}
  With pricing:           {stats['deletions_with_pricing']:,}
  In CSV export:          {stats['deletions_in_csv']:,}
CSV IDs loaded:           {len(csv_ids):,}""")

    # Keeper source breakdown
    csv_keepers = sum(1 for k in keepers.values() if k["in_csv"])
    pricing_keepers = sum(1 for k in keepers.values() if not k["in_csv"] and k["has_pricing"])
    other_keepers = stats["items_to_keep"] - csv_keepers - pricing_keepers
    print(f"""
Keeper selection method:
  From CSV export:        {csv_keepers:,}
  By pricing (no CSV):    {pricing_keepers:,}
  By age/fallback:        {other_keepers:,}""")

    # Worst duplicate groups
    worst = sorted(keepers.items(), key=lambda x: -x[1]["duplicate_count"])[:15]
    print("\nWorst duplicate groups:")
    for name, info in worst:
        if info["duplicate_count"] == 0:
            break
        csv_tag = " [CSV]" if info["in_csv"] else ""
        print(f"  {info['duplicate_count'] + 1:3d}x  {name}{csv_tag}")

    # Deletions that are in CSV (unusual — should be rare)
    csv_deletions = [d for d in deletions if d["in_csv"]]
    if csv_deletions:
        print(f"\nWARNING: {len(csv_deletions)} deletion candidates are in CSV export:")
        for d in csv_deletions[:10]:
            print(f"  {d['id']}: {d['name']} — {d['reason_not_keeper']}")

    print("\n" + "=" * 70)


# ── Main ─────────────────────────────────────────────────────────────────────

def load_grant_key() -> str:
    key = os.environ.get("JT_GRANT_KEY")
    if key:
        return key
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith("JT_GRANT_KEY="):
                    return line.split("=", 1)[1].strip()
    raise RuntimeError(f"JT_GRANT_KEY not found")


def main():
    parser = argparse.ArgumentParser(description="JT catalog dedup analysis")
    parser.add_argument("--refresh", action="store_true", help="Re-fetch JT catalog from PAVE API")
    args = parser.parse_args()

    grant_key = load_grant_key()

    # Load or fetch JT catalog
    if args.refresh or not CACHE_FILE.exists():
        print("Fetching JT org catalog (with createdAt)...")
        raw = fetch_jt_catalog(grant_key)
        CACHE_FILE.write_text(json.dumps(raw, indent=2))
        print(f"Cached {len(raw)} items")
    else:
        raw = json.loads(CACHE_FILE.read_text())
        # Check if cache has createdAt
        if raw and not raw[0].get("createdAt"):
            print("Cache missing createdAt — re-fetching...")
            raw = fetch_jt_catalog(grant_key)
            CACHE_FILE.write_text(json.dumps(raw, indent=2))
            print(f"Cached {len(raw)} items")
        else:
            print(f"Loaded {len(raw)} items from cache")

    # Load CSV IDs
    csv_ids = load_csv_ids()

    # Analyze
    print("Analyzing duplicates...")
    result = analyze_duplicates(raw, csv_ids)

    # Report
    print_report(result, csv_ids)

    # Save outputs
    KEEPERS_FILE.write_text(json.dumps(result["keepers"], indent=2))
    print(f"Keepers: {KEEPERS_FILE}")

    DELETIONS_FILE.write_text(json.dumps(result["deletions"], indent=2))
    print(f"Deletions: {DELETIONS_FILE}")


if __name__ == "__main__":
    main()
