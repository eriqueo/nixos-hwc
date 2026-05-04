#!/usr/bin/env python3
"""
Heartwood Craft — Catalog & Assembly Rules Validator

Validates the three-layer architecture:
  Layer 1: catalog items (price book) — pricing, JT linkage, naming
  Layer 2: assembly rules (in catalog.json) — formulas, conditions, state keys

Checks:
  1. Duplicate names across assembly rules
  2. Assembly rules with formulas but no default_qty fallback
  3. Formula state key references → do they resolve in enrichState()?
  4. Condition trigger state key references → same check
  5. Naming convention violations
  6. Trade references that don't map to a known trade rate
  7. Orphaned rules (rule references missing state keys)

Run after every catalog/assembly change, before export.
Exit code 1 if critical errors found, 0 otherwise.

Usage:
  python3 validate_catalog.py /path/to/catalog.json [/path/to/stateKeys.json]
  python3 validate_catalog.py  # uses defaults from estimator src/data/
"""

import json
import re
import sys
import os
from collections import defaultdict

# ─── Configuration ───────────────────────────────────────────────────────────

# Valid state keys produced by enrichState() — derived geometry values
DERIVED_KEYS_BATHROOM = {
    "bathroom_floor_sqft",
    "bathroom_perimeter_lf",
    "shower_wall_tile_sqft",
    "shower_pan_tile_sqft",
    "shower_curb_tile_sqft",
    "shower_accent_tile_sqft",
    "bathroom_wall_paint_sqft",
}

DERIVED_KEYS_DECK = {
    "deck_sqft",
    "deck_perimeter_lf",
    "deck_joist_count",
    "deck_footing_count",
    "deck_decking_lf",
    "railing_lf",
    "stair_tread_count",
    "deck_width_ft",
    "deck_height_ft",
    "stair_width_ft",
    "stair_stringer_count",
}

# Raw input state keys (bathroom) — from enrichState input expectations
RAW_KEYS_BATHROOM = {
    "bathroom_length_ft",
    "bathroom_width_ft",
    "shower_wall_1_width_ft",
    "shower_wall_2_width_ft",
    "shower_wall_3_width_ft",
    "shower_wall_4_width_ft",
    "shower_wall_height_ft",
    "shower_pan_width_ft",
    "shower_pan_length_ft",
    "shower_curb_height_in",
    "shower_curb_width_in",
    "shower_curb_length_ft",
    "wall_height_ft",
}

RAW_KEYS_DECK = {
    "deck_length_ft",
    "deck_width_ft",
    "joist_spacing_in",
    "deck_height_ft",
    "stair_width_ft",
    "stair_stringer_count",
}

# Known functions in formulaEngine.js — these are NOT state keys
FORMULA_FUNCTIONS = {"ceil", "floor", "round", "max", "min", "abs", "if"}

# Keywords in formulaEngine.js — these are NOT state keys
FORMULA_KEYWORDS = {"AND", "OR", "NOT", "TRUE", "FALSE", "true", "false",
                    "and", "or", "not"}

# Known trade rate keys (from schema.sql seed + assembler TRADE_RATE_KEY map)
KNOWN_TRADES = {
    "demo", "framing", "plumbing", "tile", "drywall", "painting",
    "finish_carpentry", "electrical", "admin", "waterproofing",
    "protection", "sitework", "concrete", "decking", "stairs", "railing",
    "planning", "cabinetry", "tiling", "finish carpentry",
}

# Valid project types
VALID_PROJECT_TYPES = {"bathroom", "deck", "kitchen", "general"}

# Canonical naming pattern: {Type} | {Trade} | {Subject} [| {Spec}]
CANONICAL_PATTERN = re.compile(
    r'^(Labor|Material|Allowance|Admin|Other)\s*\|\s*\w[\w\s&/\'-]*\s*\|\s*\w[\w\s&/\'-]*(\s*\|\s*\w[\w\s&/\'".-]*)?$'
)

# ─── Formula/Condition Identifier Extraction ─────────────────────────────────

# Matches bare identifiers in formula expressions
IDENT_RE = re.compile(r'[a-zA-Z_][a-zA-Z0-9_]*')


def extract_identifiers(expr: str) -> set:
    """Extract all identifier tokens from a formula or condition string.
    Strips quoted string literals first so they aren't mistaken for state keys."""
    if not expr or expr == "always":
        return set()
    # Remove quoted strings (both single and double quoted, including escaped quotes)
    cleaned = re.sub(r'"[^"]*"', '', expr)
    cleaned = re.sub(r"'[^']*'", '', cleaned)
    return set(IDENT_RE.findall(cleaned))


def filter_state_refs(identifiers: set) -> set:
    """Remove known functions and keywords, leaving only state key references."""
    return identifiers - FORMULA_FUNCTIONS - FORMULA_KEYWORDS


# ─── State Key Registry ─────────────────────────────────────────────────────

def build_valid_keys(state_keys_data: list) -> dict:
    """
    Build per-project-type sets of valid state keys from stateKeys.json.
    Returns {'bathroom': set(...), 'deck': set(...), None: set(...)}
    """
    keys_by_type = defaultdict(set)

    for sk in state_keys_data:
        raw_key = sk["key"]
        parts = raw_key.split(".", 1)
        if len(parts) == 2:
            _, attr = parts
            flat_key = attr
            keys_by_type[sk.get("projectType")].add(flat_key)
        else:
            keys_by_type[sk.get("projectType")].add(raw_key)

    return keys_by_type


def get_all_valid_keys_for_project(project_type: str, keys_by_type: dict) -> set:
    """Get the full set of valid state keys for a given project type."""
    valid = set()

    # Global keys (projectType=None in stateKeys.json)
    valid |= keys_by_type.get(None, set())

    if project_type == "bathroom":
        valid |= keys_by_type.get("bathroom", set())
        valid |= DERIVED_KEYS_BATHROOM
        valid |= RAW_KEYS_BATHROOM
    elif project_type == "deck":
        valid |= keys_by_type.get("deck", set())
        valid |= DERIVED_KEYS_DECK
        valid |= RAW_KEYS_DECK

    # Common state keys used in formulas/conditions but not in stateKeys.json
    valid |= {
        # Allowance cost values
        "tub_allowance", "shower_trim_allowance", "toilet_allowance",
        "vanity_allowance", "accessory_allowance",
        # Project context
        "job_type", "occupied_home", "lead_safe_required",
        "customer_name", "address", "source",
        # Bathroom conditions & scope toggles (from ScopeTab UI)
        "demo_scope", "has_shower_tile", "new_tub", "shower_niches",
        "has_shower", "has_tub", "has_niche", "permit_required",
        "drywall_repair_needed", "plumbing_moved", "electrical_needed",
        "niche_count", "fixture_count",
        "has_paint", "has_vanity", "has_new_lighting", "has_floor_tile",
        "has_mirror", "has_accent_tile", "new_electrical", "new_fan",
        "fixtures", "tile_level", "project_type",
        "is_double_vanity",
        # Bathroom measurement inputs (not yet in stateKeys.json)
        "bathroom_wall_repair_sqft",
        # Deck conditions
        "project_scope", "decking_material", "railing_type",
        "has_stairs",
    }

    return valid


# ─── Validators ──────────────────────────────────────────────────────────────

class Issue:
    CRITICAL = "CRITICAL"
    WARNING = "WARNING"
    INFO = "INFO"

    def __init__(self, level, item_id, item_name, message):
        self.level = level
        self.item_id = item_id
        self.item_name = item_name
        self.message = message

    def __str__(self):
        return f"  [{self.level}] id={self.item_id} \"{self.item_name}\": {self.message}"


def validate_catalog(catalog: list, keys_by_type: dict) -> list:
    """Run all validation checks on assembly rules (from catalog.json).
    Each entry is an assembly rule joined to its catalog item."""
    issues = []

    # ── Check 1: Duplicate names within same project type ────────────────
    name_counts = defaultdict(list)
    for item in catalog:
        name = item.get("name", "UNNAMED")
        ptype = item.get("projectType", "?")
        key = f"{name}|{ptype}"
        name_counts[key].append(item.get("ruleId", item.get("id", "?")))

    for key, ids in name_counts.items():
        if len(ids) > 1:
            name, ptype = key.rsplit("|", 1)
            issues.append(Issue(
                Issue.CRITICAL, ids[0], name,
                f"Duplicate name in project_type={ptype} — appears {len(ids)} times (rule ids: {ids})"
            ))

    # ── Per-rule checks ──────────────────────────────────────────────────
    for item in catalog:
        iid = item.get("ruleId", item.get("id", "?"))
        iname = item.get("name", "UNNAMED")
        ptype = item.get("projectType")
        ct = item.get("conditionTrigger")
        so = item.get("sortOrder")
        qf = item.get("qtyFormula")
        dq = item.get("defaultQty")
        itype = item.get("type")

        is_rule = bool(ct) and bool(so)

        # Check 2: Invalid project type
        if ptype and ptype not in VALID_PROJECT_TYPES:
            issues.append(Issue(
                Issue.CRITICAL, iid, iname,
                f"Invalid projectType: \"{ptype}\""
            ))

        # Check 3: Rules with formula but no default_qty
        if is_rule and qf:
            if dq is None or dq == 0:
                issues.append(Issue(
                    Issue.WARNING, iid, iname,
                    f"Has qtyFormula but defaultQty is {dq} — fallback will produce 0-qty line"
                ))

        # Check 4: Formula state key references
        if qf:
            refs = filter_state_refs(extract_identifiers(qf))
            if ptype:
                valid = get_all_valid_keys_for_project(ptype, keys_by_type)
                unknown = refs - valid
                if unknown:
                    issues.append(Issue(
                        Issue.WARNING, iid, iname,
                        f"qtyFormula references unknown state keys: {sorted(unknown)} "
                        f"(formula: \"{qf}\")"
                    ))

        # Check 5: Condition trigger state key references
        if ct and ct != "always":
            refs = filter_state_refs(extract_identifiers(ct))
            if ptype:
                valid = get_all_valid_keys_for_project(ptype, keys_by_type)
                unknown = refs - valid
                if unknown:
                    issues.append(Issue(
                        Issue.WARNING, iid, iname,
                        f"conditionTrigger references unknown state keys: {sorted(unknown)} "
                        f"(condition: \"{ct}\")"
                    ))

        # Check 6: Naming convention
        if is_rule and not CANONICAL_PATTERN.match(iname):
            issues.append(Issue(
                Issue.INFO, iid, iname,
                "Name doesn't match canonical pattern: {Type} | {Trade} | {Subject} [| {Spec}]"
            ))

        # Check 7: Labor items should have a trade
        if itype == "Labor" and is_rule:
            parts = iname.split(" | ")
            if len(parts) >= 2:
                name_trade = parts[1].strip().lower()
                trade_key = name_trade.replace(" ", "_").replace("&", "")
                if trade_key not in KNOWN_TRADES and name_trade not in KNOWN_TRADES:
                    issues.append(Issue(
                        Issue.WARNING, iid, iname,
                        f"Labor item trade \"{name_trade}\" not in known trade rates"
                    ))

        # Check 8: Waste factor sanity
        wf = item.get("wasteFactor")
        if wf is not None and (wf < 1.0 or wf > 2.0):
            issues.append(Issue(
                Issue.WARNING, iid, iname,
                f"Unusual wasteFactor: {wf} (expected 1.0-2.0)"
            ))

    return issues


# ─── Report ──────────────────────────────────────────────────────────────────

def discover_all_refs(catalog: list) -> dict:
    """Discover all unique state key references across formulas and conditions."""
    formula_refs = defaultdict(set)
    condition_refs = defaultdict(set)

    for item in catalog:
        iname = item.get("name", "?")
        ptype = item.get("projectType", "?")

        qf = item.get("qtyFormula")
        ct = item.get("conditionTrigger")

        if qf:
            for ref in filter_state_refs(extract_identifiers(qf)):
                formula_refs[ref].add(f"{iname} [{ptype}]")

        if ct and ct != "always":
            for ref in filter_state_refs(extract_identifiers(ct)):
                condition_refs[ref].add(f"{iname} [{ptype}]")

    return {"formula_refs": dict(formula_refs), "condition_refs": dict(condition_refs)}


def print_report(issues: list, catalog: list):
    """Print a structured validation report."""
    critical = [i for i in issues if i.level == Issue.CRITICAL]
    warnings = [i for i in issues if i.level == Issue.WARNING]
    info = [i for i in issues if i.level == Issue.INFO]

    # Assembly rule stats
    assembly_items = [i for i in catalog if i.get("conditionTrigger") and i.get("sortOrder")]
    formula_items = [i for i in assembly_items if i.get("qtyFormula")]
    condition_items = [i for i in assembly_items
                       if (i.get("conditionTrigger") or "") not in ("", "always")]

    by_type = defaultdict(int)
    for item in assembly_items:
        by_type[item.get("projectType", "none")] += 1

    print("=" * 72)
    print("HEARTWOOD CRAFT — CATALOG VALIDATION REPORT")
    print("=" * 72)
    print()
    print(f"Total assembly rules:    {len(catalog)}")
    print(f"  with qty formulas:     {len(formula_items)}")
    print(f"  with conditions:       {len(condition_items)}")
    print(f"  by project type:       {dict(by_type)}")
    print()

    if critical:
        print(f"{'─' * 72}")
        print(f"CRITICAL ERRORS ({len(critical)}) — must fix before export")
        print(f"{'─' * 72}")
        for i in critical:
            print(str(i))
        print()

    if warnings:
        print(f"{'─' * 72}")
        print(f"WARNINGS ({len(warnings)}) — review recommended")
        print(f"{'─' * 72}")
        for i in warnings:
            print(str(i))
        print()

    if info:
        print(f"{'─' * 72}")
        print(f"INFO ({len(info)}) — optional cleanup")
        print(f"{'─' * 72}")
        for i in info:
            print(str(i))
        print()

    # Summary
    print("=" * 72)
    if critical:
        print(f"RESULT: FAIL — {len(critical)} critical, {len(warnings)} warnings, {len(info)} info")
    elif warnings:
        print(f"RESULT: PASS with warnings — {len(warnings)} warnings, {len(info)} info")
    else:
        print(f"RESULT: CLEAN — {len(info)} info notes")
    print("=" * 72)

    # Discovery: all referenced state keys
    disc = discover_all_refs(catalog)
    all_refs = sorted(set(disc["formula_refs"].keys()) | set(disc["condition_refs"].keys()))

    print()
    print(f"{'─' * 72}")
    print(f"STATE KEY REFERENCES ({len(all_refs)} unique keys)")
    print(f"{'─' * 72}")
    for key in all_refs:
        f_count = len(disc["formula_refs"].get(key, set()))
        c_count = len(disc["condition_refs"].get(key, set()))
        parts = []
        if f_count: parts.append(f"{f_count} formulas")
        if c_count: parts.append(f"{c_count} conditions")
        print(f"  {key:40s} ({', '.join(parts)})")
    print()

    return len(critical) > 0


# ─── Main ────────────────────────────────────────────────────────────────────

def main():
    # Resolve paths
    if len(sys.argv) >= 2:
        catalog_path = sys.argv[1]
    else:
        catalog_path = None

    if len(sys.argv) >= 3:
        state_keys_path = sys.argv[2]
    else:
        state_keys_path = None

    # Try to find files in known locations
    search_dirs = [
        os.getcwd(),
        os.path.dirname(os.path.abspath(__file__)),
    ]

    if not catalog_path:
        for d in search_dirs:
            candidate = os.path.join(d, "catalog.json")
            if os.path.exists(candidate):
                catalog_path = candidate
                break
        if not catalog_path:
            print("ERROR: catalog.json not found. Pass path as first argument.")
            sys.exit(2)

    if not state_keys_path:
        for d in search_dirs:
            candidate = os.path.join(d, "stateKeys.json")
            if os.path.exists(candidate):
                state_keys_path = candidate
                break

    # Load catalog (now contains assembly rules joined to catalog items)
    print(f"Loading catalog: {catalog_path}")
    with open(catalog_path, "r") as f:
        catalog = json.load(f)

    # Load state keys (optional — validator works without them, just skips key checks)
    keys_by_type = defaultdict(set)
    if state_keys_path and os.path.exists(state_keys_path):
        print(f"Loading state keys: {state_keys_path}")
        with open(state_keys_path, "r") as f:
            state_keys_data = json.load(f)
        keys_by_type = build_valid_keys(state_keys_data)
    else:
        print("WARNING: stateKeys.json not found — skipping state key reference checks")

    print()

    # Run validation
    issues = validate_catalog(catalog, keys_by_type)

    # Print report
    has_critical = print_report(issues, catalog)

    sys.exit(1 if has_critical else 0)


if __name__ == "__main__":
    main()
