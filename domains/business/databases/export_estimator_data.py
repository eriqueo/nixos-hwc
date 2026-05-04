#!/usr/bin/env python3
"""Export estimator data from hwc Postgres database to JSON files.

Three-layer architecture:
  - catalog.json         (assembly rules joined to catalog items — assembler-ready)
  - pricebook.json       (catalog items only — for UI catalog browser / manual picks)
  - catalog_export.json  (raw DB export for debugging)
  - tradeRates.json      (trade rates for the assembler pricing engine)
  - jtMappings.json      (JT cost code/type/unit ID maps)
  - templates.json       (saved estimate templates)

Output: domains/business/estimator/src/data/
"""
import subprocess
import json
from pathlib import Path

DB = "hwc"
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR.parent / "estimator" / "src" / "data"

# Unit abbreviation map
UNIT_ABBR = {
    "Hours": "hrs",
    "Square Feet": "sqft",
    "Linear Feet": "lf",
    "Each": "ea",
    "Lump Sum": "ls",
    "Gallons": "gal",
    "Pounds": "lbs",
    "Cubic Yards": "cy",
    "Days": "days",
    "Squares": "sq",
    "Tons": "tons",
}


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
    mapped = {}
    for r in rows:
        mapped[r["trade"]] = {
            "wage": float(r["wage"]),
            "burden": float(r["burden"]),
            "markup": float(r["markup"]),
        }

    path = OUTPUT_DIR / "tradeRates.json"
    with open(path, "w") as f:
        json.dump(mapped, f, indent=2)
    print(f"  tradeRates.json — {len(mapped)} trades")
    return mapped


def export_jt_mappings():
    """Export JT reference tables -> jtMappings.json."""
    codes = psql_json("SELECT id, code FROM jt_cost_codes")
    types = psql_json("SELECT id, name FROM jt_cost_types")
    units = psql_json("SELECT id, name FROM jt_units")

    mappings = {
        "codes": {r["code"]: r["id"] for r in codes},
        "types": {r["name"]: r["id"] for r in types},
        "units": {r["name"]: r["id"] for r in units},
    }

    path = OUTPUT_DIR / "jtMappings.json"
    with open(path, "w") as f:
        json.dump(mappings, f, indent=2)
    print(f"  jtMappings.json — {len(codes)} codes, {len(types)} types, {len(units)} units")
    return mappings


def export_catalog_items():
    """Export assembly_rules joined to catalog_items -> catalog.json (assembler format).

    Also exports pricebook.json (catalog items only) and catalog_export.json (raw).
    """
    # ── Assembler catalog: rules joined to items ──────────────────────────
    rows = psql_json("""
        SELECT
            ar.id AS rule_id,
            ci.id AS catalog_item_id,
            ci.canonical_name,
            ci.display_name,
            ci.item_type,
            ci.trade,
            ci.subject,
            ci.spec,
            ci.jt_catalog_id,
            ci.jt_cost_code_id,
            ci.jt_cost_type_id,
            ci.jt_unit_id,
            ci.jt_org_cost_item_id,
            COALESCE(ar.unit_cost_override, ci.unit_cost) AS unit_cost,
            COALESCE(ar.unit_price_override, ci.unit_price) AS unit_price,
            ci.labor_wage,
            ci.labor_burden,
            ar.budget_group_path,
            ar.condition_trigger,
            ar.qty_driver,
            ar.qty_formula,
            ar.default_qty,
            ar.waste_factor,
            ar.production_rate,
            ar.project_type,
            ar.sort_order,
            COALESCE(ar.description, ci.description) AS description,
            cc.code AS cost_code,
            ct.name AS cost_type_name,
            u.name AS unit_name
        FROM assembly_rules ar
        JOIN catalog_items ci ON ar.catalog_item_id = ci.id
        LEFT JOIN jt_cost_codes cc ON ci.jt_cost_code_id = cc.id
        LEFT JOIN jt_cost_types ct ON ci.jt_cost_type_id = ct.id
        LEFT JOIN jt_units u ON ci.jt_unit_id = u.id
        WHERE ar.is_active = true AND ci.is_active = true
        ORDER BY ar.sort_order, ci.item_type, ci.trade, ci.subject, ci.spec
    """)

    catalog = []
    for r in rows:
        unit_name = r.get("unit_name") or ""
        catalog.append({
            "id": r["catalog_item_id"],
            "ruleId": r["rule_id"],
            "name": r.get("display_name") or r["canonical_name"],
            "group": r.get("budget_group_path") or "",
            "code": r.get("cost_code") or "",
            "type": r.get("cost_type_name") or "",
            "unit": unit_name,
            "unitAbbr": UNIT_ABBR.get(unit_name, ""),
            "defaultQty": r.get("default_qty"),
            "unitCost": float(r["unit_cost"]) if r.get("unit_cost") is not None else None,
            "unitPrice": float(r["unit_price"]) if r.get("unit_price") is not None else None,
            "laborWage": float(r["labor_wage"]) if r.get("labor_wage") is not None else None,
            "laborBurden": float(r["labor_burden"]) if r.get("labor_burden") is not None else None,
            "wasteFactor": float(r["waste_factor"]) if r.get("waste_factor") is not None else None,
            "productionRate": float(r["production_rate"]) if r.get("production_rate") is not None else None,
            "qtyDriverKey": r.get("qty_driver"),
            "qtyFormula": r.get("qty_formula"),
            "conditionTrigger": r.get("condition_trigger"),
            "sortOrder": r.get("sort_order"),
            "projectType": r.get("project_type"),
            "notes": r.get("description") or "",
        })

    cat_path = OUTPUT_DIR / "catalog.json"
    with open(cat_path, "w") as f:
        json.dump(catalog, f, indent=2)

    by_type: dict[str, int] = {}
    for r in rows:
        t = r.get("project_type", "unknown")
        by_type[t] = by_type.get(t, 0) + 1
    parts = ", ".join(f"{t}: {n}" for t, n in sorted(by_type.items()))
    print(f"  catalog.json — {len(catalog)} assembly rules ({parts})")

    # ── Price book: all catalog items (for UI catalog browser) ────────────
    pricebook_rows = psql_json("""
        SELECT
            ci.id,
            ci.canonical_name,
            ci.display_name,
            ci.item_type,
            ci.trade,
            ci.subject,
            ci.spec,
            ci.unit_cost,
            ci.unit_price,
            ci.budget_group_path,
            ci.vendor,
            ci.available_finishes,
            ci.description,
            cc.code AS cost_code,
            ct.name AS cost_type_name,
            u.name AS unit_name
        FROM catalog_items ci
        LEFT JOIN jt_cost_codes cc ON ci.jt_cost_code_id = cc.id
        LEFT JOIN jt_cost_types ct ON ci.jt_cost_type_id = ct.id
        LEFT JOIN jt_units u ON ci.jt_unit_id = u.id
        WHERE ci.is_active = true
        ORDER BY ci.item_type, ci.trade, ci.subject, ci.spec
    """)

    pricebook = []
    for r in pricebook_rows:
        unit_name = r.get("unit_name") or ""
        pricebook.append({
            "id": r["id"],
            "name": r.get("display_name") or r["canonical_name"],
            "itemType": r.get("item_type"),
            "trade": r.get("trade"),
            "code": r.get("cost_code") or "",
            "type": r.get("cost_type_name") or "",
            "unit": unit_name,
            "unitAbbr": UNIT_ABBR.get(unit_name, ""),
            "unitCost": float(r["unit_cost"]) if r.get("unit_cost") is not None else None,
            "unitPrice": float(r["unit_price"]) if r.get("unit_price") is not None else None,
            "group": r.get("budget_group_path") or "",
            "vendor": r.get("vendor") or "",
            "finishes": r.get("available_finishes") or "",
            "notes": r.get("description") or "",
        })

    pb_path = OUTPUT_DIR / "pricebook.json"
    with open(pb_path, "w") as f:
        json.dump(pricebook, f, indent=2)
    print(f"  pricebook.json — {len(pricebook)} catalog items")

    # ── Raw export (for debugging) ────────────────────────────────────────
    raw_path = OUTPUT_DIR / "catalog_export.json"
    with open(raw_path, "w") as f:
        json.dump(rows, f, indent=2)
    print(f"  catalog_export.json — {len(rows)} rows (raw)")

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
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    export_trade_rates()
    export_jt_mappings()
    export_catalog_items()
    try:
        export_templates()
    except Exception as e:
        print(f"  templates: skipped ({e})")
        with open(OUTPUT_DIR / "templates.json", "w") as f:
            json.dump([], f)
        print("  templates.json — 0 (table missing)")
    print("Done.")
