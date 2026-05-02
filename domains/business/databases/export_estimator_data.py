#!/usr/bin/env python3
"""Export estimator data from hwc database to JSON files.

Generates:
  - tradeRates.json (trade rates for the assembler pricing engine)
  - catalog_export.json (all catalog items with JT mappings)
  - templates.json (saved estimate templates)

Output: domains/business/estimator/app/src/data/
"""
import subprocess
import json
from pathlib import Path

DB = "hwc"
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "estimator" / "app" / "src" / "data"


def psql_json(sql: str) -> list[dict]:
    """Run SQL and return parsed JSON rows."""
    cmd = ["sudo", "-u", "postgres", "psql", "-d", DB, "-t", "-A",
           "-c", f"SELECT json_agg(t) FROM ({sql}) t;"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"psql error: {result.stderr}")
    raw = result.stdout.strip()
    if not raw or raw == "" or raw == "null":
        return []
    return json.loads(raw)


def export_trade_rates():
    """Export trade_rates table -> tradeRates.json format."""
    rows = psql_json("""
        SELECT trade, base_wage as wage, burden_factor as burden,
               markup_factor as markup
        FROM trade_rates ORDER BY trade
    """)
    # Map DB trade names to assembler trade names
    name_map = {"tile": "tiling", "finish_carpentry": "cabinetry", "admin": "planning"}
    mapped = {}
    for r in rows:
        key = name_map.get(r["trade"], r["trade"])
        mapped[key] = {
            "wage": float(r["wage"]),
            "burden": float(r["burden"]),
            "markup": float(r["markup"]),
        }
    # Waterproofing uses tile rates
    if "waterproofing" not in mapped and "tiling" in mapped:
        mapped["waterproofing"] = dict(mapped["tiling"])

    path = OUTPUT_DIR / "tradeRates.json"
    with open(path, "w") as f:
        json.dump(mapped, f, indent=2)
    print(f"  tradeRates.json — {len(mapped)} trades")
    return mapped


def export_catalog_items():
    """Export catalog_items -> catalog_export.json."""
    rows = psql_json("""
        SELECT canonical_name, display_name, item_type, trade,
               jt_cost_code_id, jt_cost_type_id, jt_unit_id,
               jt_org_cost_item_id, unit_cost, unit_price,
               budget_group_path, condition_trigger,
               qty_driver, qty_formula, default_qty,
               waste_factor, production_rate,
               source, description, project_type
        FROM catalog_items
        WHERE is_active = true
        ORDER BY project_type, budget_group_path, canonical_name
    """)

    path = OUTPUT_DIR / "catalog_export.json"
    with open(path, "w") as f:
        json.dump(rows, f, indent=2)

    by_type: dict[str, int] = {}
    for r in rows:
        pt = r.get("project_type", "unknown")
        by_type[pt] = by_type.get(pt, 0) + 1
    parts = ", ".join(f"{pt}: {n}" for pt, n in sorted(by_type.items()))
    print(f"  catalog_export.json — {len(rows)} items ({parts})")
    return rows


def export_templates():
    """Export estimate_templates -> templates.json."""
    rows = psql_json("""
        SELECT id, name, project_type, description, state,
               created_at::text, updated_at::text
        FROM estimate_templates
        WHERE is_active = true
        ORDER BY project_type, name
    """)
    path = OUTPUT_DIR / "templates.json"
    with open(path, "w") as f:
        json.dump(rows or [], f, indent=2)
    print(f"  templates.json — {len(rows or [])} templates")
    return rows


if __name__ == "__main__":
    print(f"Exporting estimator data from {DB} -> {OUTPUT_DIR}")
    export_trade_rates()
    export_catalog_items()
    try:
        export_templates()
    except Exception as e:
        print(f"  templates: skipped ({e})")
        with open(OUTPUT_DIR / "templates.json", "w") as f:
            json.dump([], f)
        print("  templates.json — 0 (table missing)")
    print("Done.")
