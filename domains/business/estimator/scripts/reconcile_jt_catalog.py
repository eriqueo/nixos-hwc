#!/usr/bin/env python3
"""Reconcile Postgres catalog_items with JT org catalog.

Phases:
  A) Build mapping: match Postgres items → JT items via ID, name, fuzzy match
  B) Execute sync: update matched items, create unmatched, store JT IDs back

Usage:
  python3 reconcile_jt_catalog.py                  # Phase A only (DRY_RUN)
  python3 reconcile_jt_catalog.py --sync            # Phase B (DRY_RUN, prints plan)
  python3 reconcile_jt_catalog.py --sync --execute  # Phase B (LIVE — makes changes)
  python3 reconcile_jt_catalog.py --cache-jt        # Fetch JT catalog to cache file

Environment:
  JT_GRANT_KEY  — from /run/hwc-sys-mcp/env or env var
  Database: hwc (local psql)
"""

import argparse
import json
import os
import re
import subprocess
import time
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path
from typing import Optional
from urllib.request import Request, urlopen

# ── Constants ────────────────────────────────────────────────────────────────

SCRIPT_DIR = Path(__file__).parent
CACHE_FILE = SCRIPT_DIR / "jt_catalog_cache.json"
MAP_FILE = SCRIPT_DIR / "jt_catalog_map.json"
MANUAL_MAP_FILE = SCRIPT_DIR / "jt_manual_overrides.json"
KEEPERS_FILE = SCRIPT_DIR / "jt_dedup_keepers.json"
DELETIONS_FILE = SCRIPT_DIR / "jt_dedup_deletions.json"
PRE_SYNC_JT = SCRIPT_DIR / "jt_catalog_pre_sync.json"
PRE_SYNC_PG = SCRIPT_DIR / "pg_jt_links_pre_sync.json"
SYNC_LOG = SCRIPT_DIR / "sync_log.json"
SYNC_STATE = SCRIPT_DIR / "sync_state.json"
DB = "hwc"

PAVE_URL = "https://api.jobtread.com/pave"
ORG_ID = "22Nm3uFevXMb"
USER_ID = "22Nm3uFeRB7s"
ENV_FILE = "/run/hwc-sys-mcp/env"

# Postgres trade → JT cost code ID
TRADE_TO_COST_CODE = {
    "Admin":            "22Nm3uGRAMmH",  # Planning
    "Planning":         "22Nm3uGRAMmH",  # Planning
    "Sitework":         "22NxeGLaJCQT",  # Site Preparation
    "Cleanup":          "22NxeGLaJCQT",  # Site Preparation
    "Demo":             "22Nm3uGRAMmJ",  # Demolition
    "Framing":          "22Nm3uGRAMmN",  # Framing
    "Siding":           "22Nm3uGRAMmQ",  # Siding
    "Electrical":       "22Nm3uGRAMmS",  # Electrical
    "HVAC":             "22Nm3uGRAMmS",  # Electrical (no dedicated code)
    "Plumbing":         "22Nm3uGRAMmT",  # Plumbing
    "Insulation":       "22Nm3uGRAMmV",  # Insulation
    "Drywall":          "22Nm3uGRAMmW",  # Drywall
    "Doors & Windows":  "22Nm3uGRAMmX",  # Doors & Windows
    "Flooring":         "22Nm3uGRAMmZ",  # Flooring
    "Tile":             "22Nm3uGRAMma",  # Tiling
    "Waterproofing":    "22Nm3uGRAMma",  # Tiling (Schluter products)
    "Cabinetry":        "22Nm3uGRAMmb",  # Cabinetry
    "Countertop":       "22Nm3uGRAMmc",  # Countertops
    "Trimwork":         "22Nm3uGRAMmd",  # Trimwork
    "Finish Carpentry": "22Nm3uGRAMmd",  # Trimwork
    "Specialty":        "22Nm3uGRAMme",  # Specialty Finishes
    "Painting":         "22Nm3uGRAMmf",  # Painting
    "Appliances":       "22Nm3uGRAMmg",  # Appliances
    "Decking":          "22Nm3uGRAMmh",  # Decking
    "Stairs":           "22Nm3uGRAMmh",  # Decking
    "Railing":          "22Nm3uGRAMmh",  # Decking
    "Concrete":         "22Nm3uGRAMmk",  # Concrete
    "Furnishings":      "22Nm3uGRAMmn",  # Furnishings
    "Miscellaneous":    "22Nm3uGRAMmp",  # Miscellaneous
    "Protection":       "22Nm3uGRAMmp",  # Miscellaneous
    "Allowances":       "22Nm3uGRAMmp",  # Miscellaneous
    "Fixtures":         "22Nm3uGRAMmT",  # Plumbing (fixtures are plumbing-adjacent)
}

# Postgres item_type → JT cost type ID
TYPE_TO_COST_TYPE = {
    "Labor":      "22Nm3uGRAMmq",  # Labor
    "Material":   "22Nm3uGRAMmr",  # Materials
    "Allowance":  "22Nm3uGRAMmt",  # Other
    "Other":      "22Nm3uGRAMmt",  # Other
    "Subcontract": "22Nm3uGRAMms", # Subcontractor
}

# JT unit name → ID
UNIT_NAME_TO_ID = {
    "Cubic Yards": "22Nm3uGRAMm5",
    "Days":        "22Nm3uGRAMm6",
    "Each":        "22Nm3uGRAMm7",
    "Gallons":     "22Nm3uGRAMm8",
    "Hours":       "22Nm3uGRAMm9",
    "Linear Feet": "22Nm3uGRAMmA",
    "Lump Sum":    "22Nm3uGRAMmB",
    "Pounds":      "22Nm3uGRAMmC",
    "Square Feet": "22Nm3uGRAMmD",
    "Squares":     "22Nm3uGRAMmE",
    "Tons":        "22Nm3uGRAMmF",
}


# ── Data classes ─────────────────────────────────────────────────────────────

@dataclass
class PgItem:
    id: int
    canonical_name: str
    display_name: str
    item_type: str
    trade: str
    subject: str
    spec: str
    jt_cost_code_id: Optional[str]
    jt_cost_type_id: Optional[str]
    jt_unit_id: Optional[str]
    jt_catalog_id: Optional[str]
    unit_cost: Optional[float]
    unit_price: Optional[float]

@dataclass
class JtItem:
    id: str
    name: str
    unit_cost: Optional[float]
    unit_price: Optional[float]
    cost_code_id: Optional[str]
    cost_code_name: Optional[str]
    cost_type_id: Optional[str]
    cost_type_name: Optional[str]
    unit_id: Optional[str]
    unit_name: Optional[str]

@dataclass
class Match:
    pg_id: int
    pg_name: str
    jt_id: str
    jt_name: str
    method: str  # exact_id, exact_name, fuzzy_name, manual
    score: float = 1.0
    conflicts: list = field(default_factory=list)


# ── PAVE API client ─────────────────────────────────────────────────────────

class PaveAPI:
    def __init__(self, grant_key: str):
        self.grant_key = grant_key

    def _request(self, operations: dict, retries: int = 3) -> dict:
        envelope = {
            "query": {
                "$": {
                    "grantKey": self.grant_key,
                    "notify": False,
                    "viaUserId": USER_ID,
                },
                **operations,
            }
        }
        from urllib.error import HTTPError as _HTTPError
        for attempt in range(retries + 1):
            req = Request(
                PAVE_URL,
                data=json.dumps(envelope).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                with urlopen(req, timeout=30) as resp:
                    data = json.loads(resp.read())
            except _HTTPError as e:
                if e.code == 429 and attempt < retries:
                    delay = 2 ** (attempt + 1)
                    print(f"    Rate limited (429), waiting {delay}s...")
                    time.sleep(delay)
                    continue
                body = e.read().decode()[:500]
                raise RuntimeError(f"PAVE HTTP {e.code}: {body}") from e
            if data.get("errors"):
                msgs = "; ".join(e.get("message", "?") for e in data["errors"])
                raise RuntimeError(f"PAVE error: {msgs}")
            return data
        raise RuntimeError("Max retries exceeded")

    def get_all_cost_items(self) -> list[dict]:
        """Fetch all org cost items. PAVE costItems supports size but not after.
        Paginate by filtering with where id > lastId, sorted by id."""
        all_items = []
        last_id = None
        page = 0
        while True:
            page += 1
            params: dict = {"size": 100}
            if last_id:
                # Use where clause to paginate: id > last_id
                params["where"] = {
                    ">": [
                        {"field": ["id"]},
                        {"value": last_id},
                    ]
                }
                params["sortBy"] = [{"field": ["id"], "order": "asc"}]
            else:
                params["sortBy"] = [{"field": ["id"], "order": "asc"}]

            resp = self._request({
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
                            "costCode": {"id": {}, "name": {}},
                            "costType": {"id": {}, "name": {}},
                            "unit": {"id": {}, "name": {}},
                        },
                    },
                }
            })
            org = resp.get("organization", {})
            items_data = org.get("costItems", {})
            nodes = items_data.get("nodes", [])
            if not nodes:
                break
            all_items.extend(nodes)
            print(f"  Page {page}: {len(nodes)} items (total: {len(all_items)})")
            if len(nodes) < 100:
                break
            last_id = nodes[-1]["id"]
            time.sleep(0.3)
        return all_items

    def create_cost_item(self, name: str, cost_code_id: str, cost_type_id: str,
                         unit_id: Optional[str] = None,
                         unit_cost: Optional[float] = None,
                         unit_price: Optional[float] = None) -> str:
        """Create a cost item and return its ID."""
        params: dict = {
            "organizationId": ORG_ID,
            "name": name,
            "costCodeId": cost_code_id,
            "costTypeId": cost_type_id,
        }
        if unit_id:
            params["unitId"] = unit_id
        if unit_cost is not None:
            params["unitCost"] = unit_cost
        if unit_price is not None:
            params["unitPrice"] = unit_price

        resp = self._request({
            "createCostItem": {
                "$": params,
                "createdCostItem": {"id": {}, "name": {}},
            }
        })
        created = resp.get("createCostItem", {}).get("createdCostItem", {})
        return created.get("id", "")

    def update_cost_item(self, item_id: str, **kwargs) -> None:
        """Update a cost item. Valid kwargs: name, costCodeId, costTypeId, unitId, unitCost, unitPrice."""
        params = {"id": item_id, **kwargs}
        self._request({"updateCostItem": {"$": params}})


# ── Postgres helpers ─────────────────────────────────────────────────────────

def psql_json(sql: str) -> list[dict]:
    result = subprocess.run(
        ["psql", "-d", DB, "-t", "-A", "-c",
         f"SELECT json_agg(t) FROM ({sql}) t"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"psql error: {result.stderr}")
    raw = result.stdout.strip()
    if not raw or raw == "" or raw == "null":
        return []
    return json.loads(raw)


def psql_exec(sql: str) -> None:
    result = subprocess.run(
        ["psql", "-d", DB, "-c", sql],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"psql error: {result.stderr}")


def load_pg_items() -> list[PgItem]:
    rows = psql_json("""
        SELECT id, canonical_name, display_name, item_type, trade,
               subject, COALESCE(spec, '') as spec,
               jt_cost_code_id, jt_cost_type_id, jt_unit_id, jt_catalog_id,
               unit_cost::float, unit_price::float
        FROM catalog_items
        WHERE is_active = true
        ORDER BY id
    """)
    return [PgItem(
        id=r["id"],
        canonical_name=r["canonical_name"] or "",
        display_name=r["display_name"] or "",
        item_type=r["item_type"] or "",
        trade=r["trade"] or "",
        subject=r["subject"] or "",
        spec=r["spec"] or "",
        jt_cost_code_id=r["jt_cost_code_id"],
        jt_cost_type_id=r["jt_cost_type_id"],
        jt_unit_id=r["jt_unit_id"],
        jt_catalog_id=r["jt_catalog_id"],
        unit_cost=r["unit_cost"],
        unit_price=r["unit_price"],
    ) for r in rows]


# ── JT data loading ─────────────────────────────────────────────────────────

def parse_jt_items(raw: list[dict]) -> list[JtItem]:
    items = []
    for r in raw:
        cc = r.get("costCode") or {}
        ct = r.get("costType") or {}
        u = r.get("unit") or {}
        items.append(JtItem(
            id=r["id"],
            name=r.get("name", ""),
            unit_cost=r.get("unitCost"),
            unit_price=r.get("unitPrice"),
            cost_code_id=cc.get("id"),
            cost_code_name=cc.get("name"),
            cost_type_id=ct.get("id"),
            cost_type_name=ct.get("name"),
            unit_id=u.get("id"),
            unit_name=u.get("name"),
        ))
    return items


def fetch_jt_catalog(grant_key: str) -> list[JtItem]:
    """Fetch from API, save cache, return parsed items."""
    api = PaveAPI(grant_key)
    print("Fetching JT org catalog...")
    raw = api.get_all_cost_items()
    CACHE_FILE.write_text(json.dumps(raw, indent=2))
    print(f"Cached {len(raw)} JT items to {CACHE_FILE}")
    return parse_jt_items(raw)


def load_jt_catalog(grant_key: Optional[str] = None) -> list[JtItem]:
    """Load from cache if available, otherwise fetch."""
    if CACHE_FILE.exists():
        age_hours = (time.time() - CACHE_FILE.stat().st_mtime) / 3600
        print(f"Loading JT catalog from cache ({age_hours:.1f}h old)")
        raw = json.loads(CACHE_FILE.read_text())
        return parse_jt_items(raw)
    if not grant_key:
        raise RuntimeError("No cache file and no grant key. Run with --cache-jt first.")
    return fetch_jt_catalog(grant_key)


# ── Matching logic ───────────────────────────────────────────────────────────

def normalize(name: str) -> str:
    """Normalize a name for comparison."""
    s = name.lower().strip()
    # Remove common noise
    s = re.sub(r'["""\u201c\u201d]', '"', s)
    s = re.sub(r"['''\u2018\u2019]", "'", s)
    s = re.sub(r'\s+', ' ', s)
    return s


def fuzzy_score(a: str, b: str) -> float:
    return SequenceMatcher(None, normalize(a), normalize(b)).ratio()


def build_mapping(pg_items: list[PgItem], jt_items: list[JtItem]) -> dict:
    """Match Postgres items to JT items. Prefers dedup keepers when available."""
    # Index JT items
    jt_by_id = {j.id: j for j in jt_items}
    jt_by_name_norm: dict[str, list[JtItem]] = {}
    for j in jt_items:
        key = normalize(j.name)
        jt_by_name_norm.setdefault(key, []).append(j)

    # Load dedup keepers (name → keeper_id)
    keeper_ids: set[str] = set()
    keeper_by_name: dict[str, str] = {}  # normalized name → keeper JT ID
    if KEEPERS_FILE.exists():
        keepers_data = json.loads(KEEPERS_FILE.read_text())
        for name, info in keepers_data.items():
            kid = info["keeper_id"]
            keeper_ids.add(kid)
            keeper_by_name[normalize(name)] = kid
        print(f"Loaded {len(keeper_ids)} dedup keepers")
    else:
        print("WARNING: No dedup keepers file — run dedup_jt_catalog.py first for best results")

    # Load manual overrides
    manual_map = {}
    if MANUAL_MAP_FILE.exists():
        raw = json.loads(MANUAL_MAP_FILE.read_text())
        manual_map = {k: v for k, v in raw.items() if not k.startswith("_")}
        print(f"Loaded {len(manual_map)} manual overrides")

    matches: list[Match] = []
    unmatched_pg: list[PgItem] = []
    matched_jt_ids: set[str] = set()
    errors: list[str] = []

    for pg in pg_items:
        match = None

        # Strategy 1: Manual override (pg_id → jt_id, or null to force create-new)
        pg_id_str = str(pg.id)
        if pg_id_str in manual_map:
            jt_id = manual_map[pg_id_str]
            if jt_id is None:
                # Explicitly rejected — skip all matching, force create-new
                unmatched_pg.append(pg)
                continue
            if jt_id in jt_by_id:
                jt = jt_by_id[jt_id]
                match = Match(pg.id, pg.canonical_name, jt.id, jt.name, "manual")

        # Strategy 2: Exact jt_catalog_id match (redirect to keeper if it's a dupe)
        if not match and pg.jt_catalog_id and pg.jt_catalog_id in jt_by_id:
            jt = jt_by_id[pg.jt_catalog_id]
            # If this ID is not the keeper and a keeper exists for this name, use keeper
            name_key = normalize(jt.name)
            keeper_id = keeper_by_name.get(name_key)
            if keeper_id and keeper_id != pg.jt_catalog_id and keeper_id in jt_by_id:
                keeper_jt = jt_by_id[keeper_id]
                match = Match(pg.id, pg.canonical_name, keeper_jt.id, keeper_jt.name, "exact_id_to_keeper")
                match.conflicts.append(f"redirected from dupe {pg.jt_catalog_id} to keeper {keeper_id}")
            else:
                match = Match(pg.id, pg.canonical_name, jt.id, jt.name, "exact_id")

        # Strategy 3: Exact name match (canonical_name or display_name)
        if not match:
            for name_to_try in [pg.canonical_name, pg.display_name]:
                key = normalize(name_to_try)
                if key in jt_by_name_norm:
                    candidates = jt_by_name_norm[key]
                    if len(candidates) == 1:
                        jt = candidates[0]
                        match = Match(pg.id, pg.canonical_name, jt.id, jt.name, "exact_name")
                        break
                    elif len(candidates) > 1:
                        # Multiple JT items with same name — prefer keeper
                        keeper_id = keeper_by_name.get(key)
                        if keeper_id:
                            keeper_jt = jt_by_id.get(keeper_id)
                            if keeper_jt:
                                match = Match(pg.id, pg.canonical_name, keeper_jt.id, keeper_jt.name, "exact_name_keeper")
                                break
                        # Fallback: disambiguate by cost code
                        pg_cc = pg.jt_cost_code_id or TRADE_TO_COST_CODE.get(pg.trade)
                        for c in candidates:
                            if c.cost_code_id == pg_cc:
                                match = Match(pg.id, pg.canonical_name, c.id, c.name, "exact_name")
                                break
                        if not match:
                            jt = candidates[0]
                            match = Match(pg.id, pg.canonical_name, jt.id, jt.name, "exact_name")
                            match.conflicts.append(f"Multiple JT matches, no keeper: {[c.id for c in candidates[:5]]}")
                        break

        # Strategy 4: Fuzzy name match — only match against keepers to avoid dupes
        if not match:
            pg_cc = pg.jt_cost_code_id or TRADE_TO_COST_CODE.get(pg.trade)
            # Build candidate pool: keepers only (or all if no keepers file)
            fuzzy_pool = [j for j in jt_items if j.id in keeper_ids] if keeper_ids else jt_items
            best_score = 0.0
            best_jt = None
            for jt in fuzzy_pool:
                if jt.id in matched_jt_ids:
                    continue
                # Prefer same cost code
                if pg_cc and jt.cost_code_id != pg_cc:
                    continue
                for name_to_try in [pg.display_name, pg.subject]:
                    score = fuzzy_score(name_to_try, jt.name)
                    if score > best_score:
                        best_score = score
                        best_jt = jt

            # Also try without cost code filter if nothing good found
            if best_score < 0.7:
                for jt in fuzzy_pool:
                    if jt.id in matched_jt_ids:
                        continue
                    for name_to_try in [pg.display_name, pg.subject]:
                        score = fuzzy_score(name_to_try, jt.name)
                        if score > best_score:
                            best_score = score
                            best_jt = jt

            if best_jt and best_score >= 0.82:
                match = Match(pg.id, pg.canonical_name, best_jt.id, best_jt.name,
                              "fuzzy_name", best_score)

        if match:
            # Check for pricing conflicts
            jt = jt_by_id[match.jt_id]
            if pg.unit_cost and jt.unit_cost:
                diff = abs(pg.unit_cost - jt.unit_cost)
                if diff > 0.01:
                    match.conflicts.append(
                        f"unit_cost: PG={pg.unit_cost} vs JT={jt.unit_cost}")
            if pg.unit_price and jt.unit_price:
                diff = abs(pg.unit_price - jt.unit_price)
                if diff > 0.01:
                    match.conflicts.append(
                        f"unit_price: PG={pg.unit_price} vs JT={jt.unit_price}")
            matches.append(match)
            matched_jt_ids.add(match.jt_id)
        else:
            unmatched_pg.append(pg)

    # Flag many-to-one matches (multiple PG → same JT)
    jt_match_count: dict[str, list[int]] = {}
    for m in matches:
        jt_match_count.setdefault(m.jt_id, []).append(m.pg_id)
    for m in matches:
        pg_ids = jt_match_count.get(m.jt_id, [])
        if len(pg_ids) > 1:
            m.conflicts.append(f"many-to-one: {len(pg_ids)} PG items → same JT item (PG IDs: {pg_ids})")

    # Unmatched JT items (only count keepers as meaningful unmatched)
    unmatched_jt_all = [j for j in jt_items if j.id not in matched_jt_ids]
    unmatched_jt_keepers = [j for j in unmatched_jt_all if j.id in keeper_ids] if keeper_ids else unmatched_jt_all

    # Count matches to keepers vs non-keepers
    matches_to_keeper = sum(1 for m in matches if m.jt_id in keeper_ids) if keeper_ids else 0
    matches_to_nonkeeper = len(matches) - matches_to_keeper if keeper_ids else 0

    return {
        "matches": matches,
        "unmatched_pg": unmatched_pg,
        "unmatched_jt": unmatched_jt_all,
        "unmatched_jt_keepers": unmatched_jt_keepers,
        "errors": errors,
        "matches_to_keeper": matches_to_keeper,
        "matches_to_nonkeeper": matches_to_nonkeeper,
        "keeper_ids": keeper_ids,
    }


# ── Reporting ────────────────────────────────────────────────────────────────

def print_report(mapping: dict, pg_items: list[PgItem], jt_items: list[JtItem]):
    matches = mapping["matches"]
    unmatched_pg = mapping["unmatched_pg"]
    unmatched_jt = mapping["unmatched_jt"]

    print("\n" + "=" * 80)
    print("JT CATALOG RECONCILIATION REPORT")
    print("=" * 80)

    keeper_ids = mapping.get("keeper_ids", set())
    unmatched_jt_keepers = mapping.get("unmatched_jt_keepers", [])

    print(f"\nPostgres catalog: {len(pg_items)} active items")
    print(f"JT org catalog:   {len(jt_items)} items ({len(keeper_ids)} keepers after dedup)")

    # Match summary
    by_method: dict[str, list] = {}
    for m in matches:
        by_method.setdefault(m.method, []).append(m)
    print(f"\n── Matches: {len(matches)} ──")
    for method, items in sorted(by_method.items()):
        print(f"  {method}: {len(items)}")
    if keeper_ids:
        print(f"  → to keeper: {mapping.get('matches_to_keeper', 0)}")
        print(f"  → to non-keeper (will redirect): {mapping.get('matches_to_nonkeeper', 0)}")

    # Conflicts
    conflicts = [m for m in matches if m.conflicts]
    if conflicts:
        print(f"\n── Conflicts ({len(conflicts)}) ──")
        for m in conflicts[:20]:
            print(f"  PG#{m.pg_id} ↔ JT:{m.jt_id}")
            print(f"    PG: {m.pg_name}")
            print(f"    JT: {m.jt_name}")
            for c in m.conflicts:
                print(f"    ⚠ {c}")
        if len(conflicts) > 20:
            print(f"  ... and {len(conflicts) - 20} more")

    # Fuzzy matches (for review)
    fuzzy = [m for m in matches if m.method == "fuzzy_name"]
    if fuzzy:
        print(f"\n── Fuzzy matches ({len(fuzzy)}) — REVIEW THESE ──")
        for m in sorted(fuzzy, key=lambda x: x.score):
            print(f"  [{m.score:.2f}] PG#{m.pg_id}: {m.pg_name}")
            print(f"          JT: {m.jt_name}")
        print()

    # Unmatched Postgres (need JT creation)
    print(f"\n── Unmatched Postgres items ({len(unmatched_pg)}) — will be CREATED in JT ──")
    for pg in unmatched_pg[:30]:
        print(f"  PG#{pg.id}: {pg.canonical_name} [{pg.item_type}/{pg.trade}]")
    if len(unmatched_pg) > 30:
        print(f"  ... and {len(unmatched_pg) - 30} more")

    # Unmatched JT (split keepers vs dupes)
    unmatched_dupes = len(unmatched_jt) - len(unmatched_jt_keepers)
    print(f"\n── Unmatched JT items ({len(unmatched_jt)}) ──")
    if keeper_ids:
        print(f"  Keepers (unique, no PG match): {len(unmatched_jt_keepers)}")
        print(f"  Duplicates (dedup candidates):  {unmatched_dupes}")
    print(f"  Showing keepers only:")
    for jt in unmatched_jt_keepers[:30]:
        cc = jt.cost_code_name or "?"
        ct = jt.cost_type_name or "?"
        print(f"    JT:{jt.id}: {jt.name} [{cc}/{ct}]")
    if len(unmatched_jt_keepers) > 30:
        print(f"    ... and {len(unmatched_jt_keepers) - 30} more")

    print("\n" + "=" * 80)


def save_mapping(mapping: dict):
    """Save mapping to JSON for reference."""
    output = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "matches": [
            {
                "pg_id": m.pg_id,
                "pg_name": m.pg_name,
                "jt_id": m.jt_id,
                "jt_name": m.jt_name,
                "method": m.method,
                "score": round(m.score, 3),
                "conflicts": m.conflicts,
            }
            for m in mapping["matches"]
        ],
        "unmatched_pg": [
            {"id": pg.id, "canonical_name": pg.canonical_name,
             "item_type": pg.item_type, "trade": pg.trade}
            for pg in mapping["unmatched_pg"]
        ],
        "unmatched_jt": [
            {"id": jt.id, "name": jt.name,
             "cost_code": jt.cost_code_name, "cost_type": jt.cost_type_name}
            for jt in mapping["unmatched_jt"]
        ],
    }
    MAP_FILE.write_text(json.dumps(output, indent=2))
    print(f"\nMapping saved to {MAP_FILE}")


# ── Sync logic ───────────────────────────────────────────────────────────────

def resolve_cost_code(pg: PgItem) -> str:
    """Get JT cost code ID for a Postgres item."""
    if pg.jt_cost_code_id:
        return pg.jt_cost_code_id
    cc = TRADE_TO_COST_CODE.get(pg.trade)
    if cc:
        return cc
    return "22Nm3uGRAMmG"  # Uncategorized


def resolve_cost_type(pg: PgItem) -> str:
    """Get JT cost type ID for a Postgres item."""
    if pg.jt_cost_type_id:
        return pg.jt_cost_type_id
    ct = TYPE_TO_COST_TYPE.get(pg.item_type)
    if ct:
        return ct
    return "22Nm3uGRAMmt"  # Other


def resolve_unit(pg: PgItem) -> Optional[str]:
    """Get JT unit ID for a Postgres item."""
    if pg.jt_unit_id:
        return pg.jt_unit_id
    # Default by item_type
    if pg.item_type == "Labor":
        return UNIT_NAME_TO_ID["Hours"]
    if pg.item_type == "Material":
        return UNIT_NAME_TO_ID["Each"]
    return UNIT_NAME_TO_ID["Lump Sum"]


def take_snapshots(api: "PaveAPI", execute: bool):
    """Save pre-sync state for rollback."""
    if not execute:
        return
    # Snapshot JT catalog
    if not PRE_SYNC_JT.exists():
        print("Taking JT catalog snapshot...")
        raw = api.get_all_cost_items()
        PRE_SYNC_JT.write_text(json.dumps(raw, indent=2))
        print(f"  Saved {len(raw)} JT items to {PRE_SYNC_JT.name}")
    else:
        print(f"  JT snapshot exists ({PRE_SYNC_JT.name}), skipping")

    # Snapshot PG links
    if not PRE_SYNC_PG.exists():
        print("Taking Postgres jt_catalog_id snapshot...")
        rows = psql_json("SELECT id, jt_catalog_id FROM catalog_items WHERE is_active = true ORDER BY id")
        PRE_SYNC_PG.write_text(json.dumps(rows, indent=2))
        print(f"  Saved {len(rows)} PG links to {PRE_SYNC_PG.name}")
    else:
        print(f"  PG snapshot exists ({PRE_SYNC_PG.name}), skipping")


def load_sync_state() -> dict:
    """Load resume state — tracks completed operations."""
    if SYNC_STATE.exists():
        return json.loads(SYNC_STATE.read_text())
    return {"completed_updates": [], "completed_creates": [], "completed_pg_writes": []}


def save_sync_state(state: dict):
    SYNC_STATE.write_text(json.dumps(state, indent=2))


def append_sync_log(entry: dict):
    """Append a mutation to the sync log."""
    log: list = []
    if SYNC_LOG.exists():
        log = json.loads(SYNC_LOG.read_text())
    log.append({**entry, "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S")})
    SYNC_LOG.write_text(json.dumps(log, indent=2))


def sync_catalog(mapping: dict, pg_items: list[PgItem], grant_key: str,
                 execute: bool = False):
    """Phase B: sync matched items and create unmatched ones."""
    pg_by_id = {p.id: p for p in pg_items}
    api = PaveAPI(grant_key)
    matches = mapping["matches"]
    unmatched_pg = mapping["unmatched_pg"]

    stats = {"updated": 0, "created": 0, "repurposed": 0, "skipped": 0, "errors": 0}
    pg_updates: list[tuple[int, str]] = []
    op_count = 0

    print(f"\n{'EXECUTING' if execute else 'DRY RUN'}: Sync Phase")
    print("=" * 60)

    # Take snapshots before any changes
    if execute:
        take_snapshots(api, execute)
    state = load_sync_state() if execute else {"completed_updates": [], "completed_creates": [], "completed_pg_writes": []}

    # Step 1: Update matched items
    print(f"\n── Updating {len(matches)} matched items ──")
    for m in matches:
        pg = pg_by_id.get(m.pg_id)
        if not pg:
            continue

        # Already synced?
        if pg.jt_catalog_id == m.jt_id:
            if normalize(pg.canonical_name) == normalize(m.jt_name):
                stats["skipped"] += 1
                continue

        # Resume: skip already completed
        op_key = f"update:{m.pg_id}:{m.jt_id}"
        if op_key in state["completed_updates"]:
            stats["skipped"] += 1
            if pg.jt_catalog_id != m.jt_id:
                pg_updates.append((pg.id, m.jt_id))
            continue

        update_fields: dict = {}
        if normalize(pg.canonical_name) != normalize(m.jt_name):
            update_fields["name"] = pg.canonical_name

        target_cc = resolve_cost_code(pg)
        update_fields["costCodeId"] = target_cc
        update_fields["costTypeId"] = resolve_cost_type(pg)

        unit_id = resolve_unit(pg)
        if unit_id:
            update_fields["unitId"] = unit_id
        if pg.unit_cost is not None:
            update_fields["unitCost"] = float(pg.unit_cost)
        if pg.unit_price is not None:
            update_fields["unitPrice"] = float(pg.unit_price)

        if execute:
            try:
                api.update_cost_item(m.jt_id, **update_fields)
                append_sync_log({"op": "update", "jt_id": m.jt_id, "pg_id": m.pg_id,
                                 "old_name": m.jt_name, "new_name": pg.canonical_name,
                                 "fields": update_fields})
                state["completed_updates"].append(op_key)
                save_sync_state(state)
                stats["updated"] += 1
                time.sleep(0.2)
            except Exception as e:
                print(f"  ERROR updating JT:{m.jt_id} for PG#{m.pg_id}: {e}")
                stats["errors"] += 1
        else:
            rename_tag = ""
            if update_fields.get("name"):
                rename_tag = f" rename:'{m.jt_name}'→'{pg.canonical_name}'"
            print(f"  UPDATE JT:{m.jt_id} PG#{m.pg_id}{rename_tag}")
            stats["updated"] += 1

        if pg.jt_catalog_id != m.jt_id:
            pg_updates.append((pg.id, m.jt_id))

        op_count += 1
        if execute and op_count % 50 == 0:
            print(f"  ... {op_count} API calls done ({stats['updated']} updated, {stats['errors']} errors)")

    # Step 2: Create unmatched Postgres items in JT (or repurpose duplicates)
    repurpose_pool: dict[str, list[dict]] = {}
    if DELETIONS_FILE.exists():
        deletions = json.loads(DELETIONS_FILE.read_text())
        for d in deletions:
            key = normalize(d["name"])
            repurpose_pool.setdefault(key, []).append(d)

    print(f"\n── Creating/repurposing {len(unmatched_pg)} new JT items ──")
    for pg in unmatched_pg:
        cc = resolve_cost_code(pg)
        ct = resolve_cost_type(pg)
        unit = resolve_unit(pg)

        # Resume: skip already completed
        create_key = f"create:{pg.id}"
        if create_key in state["completed_creates"]:
            stats["skipped"] += 1
            continue

        # Check repurpose pool
        repurpose_id = None
        for name_to_check in [pg.canonical_name, pg.display_name]:
            key = normalize(name_to_check)
            if key in repurpose_pool and repurpose_pool[key]:
                dupe = repurpose_pool[key].pop(0)
                repurpose_id = dupe["id"]
                break

        if repurpose_id:
            if execute:
                try:
                    update = {"name": pg.canonical_name, "costCodeId": cc, "costTypeId": ct}
                    if unit:
                        update["unitId"] = unit
                    if pg.unit_cost is not None:
                        update["unitCost"] = float(pg.unit_cost)
                    if pg.unit_price is not None:
                        update["unitPrice"] = float(pg.unit_price)
                    api.update_cost_item(repurpose_id, **update)
                    pg_updates.append((pg.id, repurpose_id))
                    append_sync_log({"op": "repurpose", "jt_id": repurpose_id,
                                     "pg_id": pg.id, "new_name": pg.canonical_name})
                    state["completed_creates"].append(create_key)
                    save_sync_state(state)
                    stats["repurposed"] += 1
                    time.sleep(0.2)
                except Exception as e:
                    print(f"  ERROR repurposing JT:{repurpose_id}: {e}")
                    stats["errors"] += 1
            else:
                print(f"  REPURPOSE JT:{repurpose_id} → {pg.canonical_name}")
                stats["repurposed"] += 1
        else:
            if execute:
                try:
                    new_id = api.create_cost_item(
                        name=pg.canonical_name,
                        cost_code_id=cc,
                        cost_type_id=ct,
                        unit_id=unit,
                        unit_cost=float(pg.unit_cost) if pg.unit_cost else None,
                        unit_price=float(pg.unit_price) if pg.unit_price else None,
                    )
                    if new_id:
                        pg_updates.append((pg.id, new_id))
                        append_sync_log({"op": "create", "jt_id": new_id,
                                         "pg_id": pg.id, "name": pg.canonical_name})
                        state["completed_creates"].append(create_key)
                        save_sync_state(state)
                        stats["created"] += 1
                    else:
                        print(f"  ERROR: No ID returned for PG#{pg.id}")
                        stats["errors"] += 1
                    time.sleep(0.2)
                except Exception as e:
                    print(f"  ERROR creating PG#{pg.id} '{pg.canonical_name}': {e}")
                    stats["errors"] += 1
            else:
                print(f"  CREATE: {pg.canonical_name} [{pg.item_type}/{pg.trade}]")
                stats["created"] += 1

        op_count += 1
        if execute and op_count % 50 == 0:
            print(f"  ... {op_count} API calls done")

    # Step 3: Write JT IDs back to Postgres
    if pg_updates:
        print(f"\n── Writing {len(pg_updates)} JT IDs back to Postgres ──")
        if execute:
            for pg_id, jt_id in pg_updates:
                pg_key = f"pg:{pg_id}"
                if pg_key in state["completed_pg_writes"]:
                    continue
                try:
                    safe_jt = jt_id.replace("'", "''")
                    psql_exec(
                        f"UPDATE catalog_items SET jt_catalog_id = '{safe_jt}', "
                        f"updated_at = now() WHERE id = {int(pg_id)}"
                    )
                    state["completed_pg_writes"].append(pg_key)
                except Exception as e:
                    print(f"  ERROR updating PG#{pg_id}: {e}")
                    stats["errors"] += 1
            save_sync_state(state)
            print(f"  Done — {len(pg_updates)} PG rows updated")
        else:
            for pg_id, jt_id in pg_updates[:5]:
                print(f"  PG#{pg_id} → jt_catalog_id = '{jt_id}'")
            if len(pg_updates) > 5:
                print(f"  ... and {len(pg_updates) - 5} more")

    # Summary
    print(f"\n── Sync Summary ──")
    print(f"  Updated:    {stats['updated']}")
    print(f"  Created:    {stats['created']}")
    print(f"  Repurposed: {stats['repurposed']}")
    print(f"  Skipped:    {stats['skipped']}")
    print(f"  Errors:     {stats['errors']}")
    print(f"  Total API:  {op_count}")
    if not execute:
        print("\n  DRY RUN — no changes made. Use --execute to apply.")


# ── CLI ──────────────────────────────────────────────────────────────────────

def load_grant_key() -> str:
    """Load JT grant key from env or env file."""
    key = os.environ.get("JT_GRANT_KEY")
    if key:
        return key
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                if line.startswith("JT_GRANT_KEY="):
                    return line.split("=", 1)[1].strip()
    raise RuntimeError(
        f"JT_GRANT_KEY not found in environment or {ENV_FILE}")


def main():
    parser = argparse.ArgumentParser(description="Reconcile Postgres catalog with JT org catalog")
    parser.add_argument("--cache-jt", action="store_true", help="Fetch JT catalog to cache file and exit")
    parser.add_argument("--sync", action="store_true", help="Run sync phase (DRY_RUN unless --execute)")
    parser.add_argument("--execute", action="store_true", help="Actually make changes (requires --sync)")
    parser.add_argument("--refresh", action="store_true", help="Force refresh JT cache before mapping")
    parser.add_argument("--dedup-first", action="store_true", help="Run dedup analysis before reconciliation")
    args = parser.parse_args()

    grant_key = load_grant_key()

    # Cache-only mode
    if args.cache_jt:
        fetch_jt_catalog(grant_key)
        return

    # Refresh cache if requested
    if args.refresh or not CACHE_FILE.exists():
        fetch_jt_catalog(grant_key)

    # Run dedup first if requested
    if args.dedup_first:
        print("\n── Running dedup analysis first ──")
        import subprocess as _sp
        result = _sp.run(
            ["python3", str(SCRIPT_DIR / "dedup_jt_catalog.py")],
            capture_output=False,
        )
        if result.returncode != 0:
            print("WARNING: dedup script failed, continuing without keepers")
        print()

    # Load data
    print("Loading Postgres catalog...")
    pg_items = load_pg_items()
    print(f"  {len(pg_items)} active items")

    jt_items = load_jt_catalog(grant_key)
    print(f"  {len(jt_items)} JT items")

    # Phase A: Build mapping
    print("\nBuilding mapping...")
    mapping = build_mapping(pg_items, jt_items)
    print_report(mapping, pg_items, jt_items)
    save_mapping(mapping)

    # Phase B: Sync
    if args.sync:
        sync_catalog(mapping, pg_items, grant_key, execute=args.execute)


if __name__ == "__main__":
    main()
