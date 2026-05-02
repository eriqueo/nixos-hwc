#!/usr/bin/env python3
"""Export bathroom calculator JSON from the hwc database.

Usage: python3 export_calculator_json.py [--output PATH]

Reads catalog_items and trade_rates from the hwc Postgres database,
merges with the existing calculator-bathroom.json (to preserve steps,
reportContext, imageBase, webhook), and writes the new JSON.

Default output: site_files/src/_data/calculator-bathroom.json
"""

import argparse
import json
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SITE_DIR = SCRIPT_DIR.parent / "website" / "site_files"
DEFAULT_INPUT = SITE_DIR / "src" / "_data" / "calculator-bathroom.json"
DEFAULT_OUTPUT = DEFAULT_INPUT


def query_db(sql: str) -> list[dict]:
    """Run a SQL query via psql and return rows as dicts."""
    result = subprocess.run(
        ["sudo", "-u", "postgres", "psql", "-d", "hwc", "-t", "-A", "-F", "\x01", "-c", sql],
        capture_output=True, text=True, check=True,
    )
    if not result.stdout.strip():
        return []

    # Use psql with headers to get column names
    header_result = subprocess.run(
        ["sudo", "-u", "postgres", "psql", "-d", "hwc", "-A", "-F", "\x01", "-c", sql],
        capture_output=True, text=True, check=True,
    )
    lines = header_result.stdout.strip().split("\n")
    if len(lines) < 2:
        return []

    headers = lines[0].split("\x01")
    rows = []
    for line in lines[1:]:
        if line.startswith("(") and line.endswith(")"):
            break  # skip row count footer
        vals = line.split("\x01")
        row = {}
        for h, v in zip(headers, vals):
            # Convert numeric strings
            if v == "":
                row[h] = None
            elif v == "t":
                row[h] = True
            elif v == "f":
                row[h] = False
            else:
                try:
                    if "." in v:
                        row[h] = float(v)
                    else:
                        row[h] = int(v)
                except ValueError:
                    row[h] = v
            rows.append(row) if h == headers[-1] else None
        if row:
            rows.append(row) if row not in rows else None
    # Redo more cleanly
    rows = []
    for line in lines[1:]:
        if line.startswith("(") and line.endswith(")"):
            break
        vals = line.split("\x01")
        if len(vals) != len(headers):
            continue
        row = {}
        for h, v in zip(headers, vals):
            if v == "":
                row[h] = None
            elif v == "t":
                row[h] = True
            elif v == "f":
                row[h] = False
            else:
                try:
                    if "." in v:
                        row[h] = float(v)
                    else:
                        row[h] = int(v)
                except ValueError:
                    row[h] = v
        rows.append(row)
    return rows


def get_catalog_items() -> list[dict]:
    """Fetch all active bathroom catalog items."""
    return query_db("""
        SELECT canonical_name, display_name, item_type, trade,
               budget_group_path, condition_trigger,
               qty_driver, qty_formula, default_qty,
               waste_factor, production_rate,
               unit_cost, unit_price, source, description
        FROM catalog_items
        WHERE project_type = 'bathroom' AND is_active = true
        ORDER BY id
    """)


def get_trade_rates() -> dict:
    """Fetch trade rates as a dict keyed by trade name."""
    rows = query_db("""
        SELECT trade, unit_cost, unit_price
        FROM trade_rates
        ORDER BY trade
    """)
    return {r["trade"]: {"cost": r["unit_cost"], "price": r["unit_price"]} for r in rows}


def build_calculator_json(existing: dict, items: list[dict], rates: dict) -> dict:
    """Build the new calculator JSON format."""
    return {
        "calculator": "bathroom",
        "engine": "assembly",
        "title": existing.get("title", "Bathroom Remodel Cost Calculator"),
        "subtitle": existing.get("subtitle", ""),
        "webhook": existing.get("webhook", ""),
        "imageBase": existing.get("imageBase", "/img/calculator/bathroom"),

        # Keep existing steps unchanged
        "steps": existing.get("steps", []),

        # Size-derived variables
        "sizeMap": {
            "small":  {"bathroom_sqft": 35, "perimeter_lf": 24, "wall_sqft": 192, "shower_wall_sqft": 54, "shower_pan_sqft": 9, "paint_sqft": 227, "floor_tile_sqft": 26, "drywall_sqft": 138},
            "medium": {"bathroom_sqft": 55, "perimeter_lf": 30, "wall_sqft": 240, "shower_wall_sqft": 78, "shower_pan_sqft": 12, "paint_sqft": 295, "floor_tile_sqft": 43, "drywall_sqft": 162},
            "large":  {"bathroom_sqft": 85, "perimeter_lf": 37, "wall_sqft": 296, "shower_wall_sqft": 96, "shower_pan_sqft": 15, "paint_sqft": 381, "floor_tile_sqft": 70, "drywall_sqft": 200},
            "xl":     {"bathroom_sqft": 120, "perimeter_lf": 44, "wall_sqft": 352, "shower_wall_sqft": 120, "shower_pan_sqft": 18, "paint_sqft": 472, "floor_tile_sqft": 102, "drywall_sqft": 232},
        },

        "showerTubMap": {
            "shower_only":   {"has_shower": True,  "has_tub": False},
            "tub_shower":    {"has_shower": True,  "has_tub": True},
            "both_separate": {"has_shower": True,  "has_tub": True},
            "tub_only":      {"has_shower": False, "has_tub": True},
        },

        "featureMap": {
            "heated_floor":  {"has_heated_floor": True},
            "niches":        {"has_niches": True, "niche_count": 2},
            "bench":         {"has_bench": True},
            "double_vanity": {"is_double_vanity": True},
            "lighting":      {"has_new_lighting": True},
            "ventilation":   {"has_new_ventilation": True},
        },

        "featureAdds": {
            "heated_floor": 1800,
            "bench": 1400,
        },

        "refreshFactors": {
            "demo": 0.5,
            "framing": 0.3,
        },

        "tileProductionRates": {
            "basic": {"floor": 0.20, "wall": 0.24},
            "mid":   {"floor": 0.28, "wall": 0.33},
            "high":  {"floor": 0.38, "wall": 0.45},
        },

        "tradeRates": rates,

        "materialMarkup": 1.429,

        "scopeItems": items,

        # Keep existing report context
        "reportContext": existing.get("reportContext", {}),
    }


def estimate_scenario(data: dict, state: dict) -> tuple[float, float]:
    """Quick estimate for a scenario to validate output."""
    size = data["sizeMap"].get(state.get("bathroom_size", "medium"), data["sizeMap"]["medium"])
    st = data["showerTubMap"].get(state.get("shower_tub", "shower_only"), {"has_shower": True, "has_tub": False})

    full = {**state, **size, **st}
    features = state.get("features", [])
    for feat, vals in data["featureMap"].items():
        if feat in features:
            full.update(vals)
        else:
            for k in vals:
                full.setdefault(k, False if isinstance(vals[k], bool) else 0)

    total_price = 0
    rates = data["tradeRates"]

    for item in data["scopeItems"]:
        ct = item.get("condition_trigger", "true")
        if not eval_condition(ct, full):
            continue

        qty = item.get("default_qty", 1) or 1
        formula = item.get("qty_formula")
        if formula and item.get("qty_driver"):
            qty = eval_formula(formula, full, item)

        waste = item.get("waste_factor", 1.0) or 1.0

        if item["item_type"] == "labor":
            trade = item.get("trade", "demo")
            rate = rates.get(trade, {}).get("price", 94.50)

            # Tile production rate override
            pr = item.get("production_rate")
            tile_level = full.get("tile_level", "mid")
            tile_rates = data.get("tileProductionRates", {}).get(tile_level, {})
            cn = item.get("canonical_name", "")
            if "Floor Installation" in cn and tile_rates.get("floor"):
                pr = tile_rates["floor"]
            elif "Shower Wall Installation" in cn and tile_rates.get("wall"):
                pr = tile_rates["wall"]

            if pr and item.get("qty_driver") and not formula:
                driver_val = full.get(item["qty_driver"], 0)
                if isinstance(driver_val, (int, float)):
                    qty = driver_val * pr

            total_price += qty * waste * rate
        elif item["item_type"] in ("material", "other"):
            price = item.get("unit_price", 0) or 0
            total_price += qty * waste * price
        elif item["item_type"] == "allowance":
            price = item.get("unit_price", 0) or 0
            driver = item.get("qty_driver")
            if driver and driver in full:
                driver_val = full.get(driver, 0)
                if isinstance(driver_val, (int, float)) and driver_val > 0:
                    total_price += driver_val * waste * price
                else:
                    total_price += qty * waste * price
            else:
                total_price += qty * waste * price

    # Add feature flat adds
    for feat in features:
        add = data.get("featureAdds", {}).get(feat, 0)
        total_price += add

    lo = round(total_price * 0.85 / 500) * 500
    hi = round(total_price * 1.15 / 500) * 500
    return lo, hi


def eval_condition(expr: str, state: dict) -> bool:
    """Evaluate a simple condition trigger expression."""
    if not expr or expr.strip().lower() == "true":
        return True
    if expr.strip().lower() == "false":
        return False

    # Handle AND/OR
    if " AND " in expr:
        return all(eval_condition(part.strip(), state) for part in expr.split(" AND "))
    if " OR " in expr:
        return any(eval_condition(part.strip(), state) for part in expr.split(" OR "))

    # Handle != and =
    if "!=" in expr:
        key, val = [s.strip().strip('"') for s in expr.split("!=", 1)]
        return str(state.get(key, "")).lower() != val.lower()
    if "=" in expr:
        key, val = [s.strip().strip('"') for s in expr.split("=", 1)]
        return str(state.get(key, "")).lower() == val.lower()

    # Boolean variable check
    return bool(state.get(expr.strip(), False))


def eval_formula(formula: str, state: dict, item: dict) -> float:
    """Evaluate a quantity formula."""
    if formula.startswith("CASE"):
        # Handle CASE WHEN is_double_vanity THEN 6 ELSE 4 END
        if "is_double_vanity" in formula:
            return 6 if state.get("is_double_vanity") else 4
        return item.get("default_qty", 1) or 1

    # Simple formulas like "bathroom_sqft * 0.08" or "var * production_rate"
    parts = formula.split("*")
    if len(parts) == 2:
        left_name = parts[0].strip()
        right_str = parts[1].strip()

        # Resolve left operand from state
        left_val = state.get(left_name, 0)
        if not isinstance(left_val, (int, float)):
            left_val = 0

        # Resolve right operand — could be literal or variable (e.g. production_rate)
        try:
            right_val = float(right_str)
        except ValueError:
            # Try item field, then state
            right_val = item.get(right_str) or state.get(right_str, 0)
            if not isinstance(right_val, (int, float)):
                right_val = 0

        return left_val * right_val

    return item.get("default_qty", 1) or 1


def main():
    parser = argparse.ArgumentParser(description="Export bathroom calculator JSON from hwc database")
    parser.add_argument("--output", "-o", type=Path, default=DEFAULT_OUTPUT,
                        help=f"Output path (default: {DEFAULT_OUTPUT})")
    parser.add_argument("--input", "-i", type=Path, default=DEFAULT_INPUT,
                        help=f"Existing JSON to preserve steps from (default: {DEFAULT_INPUT})")
    args = parser.parse_args()

    # Load existing JSON
    print(f"Reading existing JSON from {args.input}")
    with open(args.input) as f:
        existing = json.load(f)

    # Query database
    print("Querying catalog_items...")
    items = get_catalog_items()
    print(f"  Found {len(items)} active bathroom items")

    print("Querying trade_rates...")
    rates = get_trade_rates()
    print(f"  Found {len(rates)} trades: {', '.join(sorted(rates.keys()))}")

    # Build new JSON
    data = build_calculator_json(existing, items, rates)

    # Write output
    print(f"Writing {args.output}")
    with open(args.output, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  Done. {len(items)} scope items, {len(rates)} trade rates.")

    # Validation: estimate a medium full gut scenario
    print("\n--- Validation: Medium full gut, shower only, mid tile, standard fixtures ---")
    test_state = {
        "project_type": "full_gut",
        "bathroom_size": "medium",
        "shower_tub": "shower_only",
        "tile_level": "mid",
        "fixtures": "standard",
        "features": [],
    }
    lo, hi = estimate_scenario(data, test_state)
    print(f"  Estimated range: ${lo:,.0f} - ${hi:,.0f}")

    print("\n--- Validation: Small refresh, tub+shower, basic tile, standard fixtures ---")
    test_state2 = {
        "project_type": "refresh",
        "bathroom_size": "small",
        "shower_tub": "tub_shower",
        "tile_level": "basic",
        "fixtures": "standard",
        "features": [],
    }
    lo2, hi2 = estimate_scenario(data, test_state2)
    print(f"  Estimated range: ${lo2:,.0f} - ${hi2:,.0f}")

    print("\n--- Validation: Large full gut, both separate, high tile, premium, niches+heated+double ---")
    test_state3 = {
        "project_type": "full_gut",
        "bathroom_size": "large",
        "shower_tub": "both_separate",
        "tile_level": "high",
        "fixtures": "premium",
        "features": ["niches", "heated_floor", "double_vanity"],
    }
    lo3, hi3 = estimate_scenario(data, test_state3)
    print(f"  Estimated range: ${lo3:,.0f} - ${hi3:,.0f}")

    print("\n--- Validation: Medium tub-to-shower, mid tile, upgraded fixtures, niches ---")
    test_state4 = {
        "project_type": "tub_to_shower",
        "bathroom_size": "medium",
        "shower_tub": "shower_only",
        "tile_level": "mid",
        "fixtures": "upgraded",
        "features": ["niches"],
    }
    lo4, hi4 = estimate_scenario(data, test_state4)
    print(f"  Estimated range: ${lo4:,.0f} - ${hi4:,.0f}")


if __name__ == "__main__":
    main()
