#!/usr/bin/env python3
"""Export Postgres catalog as JT-importable CSV with formulas and custom fields.

Merges data from:
  - Postgres catalog_items + assembly_rules (canonical names, pricing, rates)
  - JT export CSV (existing formulas, URLs, dimensions, specs)

Postgres is source of truth for pricing/rates. JT export provides formulas
and custom fields not stored in Postgres. Existing JT formulas are preserved;
new formulas are generated from standard patterns for items that lack them.

Usage:
  python3 export_jt_import_csv.py
"""

import csv
import json
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
OUTPUT = SCRIPT_DIR / "hwc_catalog_for_jt_import.csv"
JT_EXPORT = SCRIPT_DIR / "catalog-2026-05-04.csv"
DB = "hwc"

# ── Reference maps ───────────────────────────────────────────────────────────

COST_CODE_NAMES = {
    "22Nm3uGRAMmG": "0000 Uncategorized",
    "22Nm3uGRAMmH": "0100 Planning",
    "22NxeGLaJCQT": "0110 Site Preparation",
    "22Nm3uGRAMmJ": "0200 Demolition",
    "22Nm3uGRAMmL": "0400 Utilities",
    "22Nm3uGRAMmM": "0500 Foundation",
    "22Nm3uGRAMmN": "0600 Framing",
    "22Nm3uGRAMmQ": "0800 Siding",
    "22Nm3uGRAMmS": "1000 Electrical",
    "22Nm3uGRAMmT": "1100 Plumbing",
    "22Nm3uGRAMmV": "1300 Insulation",
    "22Nm3uGRAMmW": "1400 Drywall",
    "22Nm3uGRAMmX": "1500 Doors & Windows",
    "22Nm3uGRAMmZ": "1700 Flooring",
    "22Nm3uGRAMma": "1800 Tiling",
    "22Nm3uGRAMmb": "1900 Cabinetry",
    "22Nm3uGRAMmc": "2000 Countertops",
    "22Nm3uGRAMmd": "2100 Trimwork",
    "22Nm3uGRAMme": "2200 Specialty Finishes",
    "22Nm3uGRAMmf": "2300 Painting",
    "22Nm3uGRAMmg": "2400 Appliances",
    "22Nm3uGRAMmh": "2500 Decking",
    "22Nm3uGRAMmi": "2600 Fencing",
    "22Nm3uGRAMmk": "2800 Concrete",
    "22Nm3uGRAMmn": "3000 Furnishings",
    "22Nm3uGRAMmp": "3100 Miscellaneous",
}

TRADE_TO_COST_CODE = {
    "Admin": "0100 Planning", "Planning": "0100 Planning",
    "Sitework": "0110 Site Preparation", "Cleanup": "0110 Site Preparation",
    "Demo": "0200 Demolition", "Foundation": "0500 Foundation",
    "Framing": "0600 Framing", "Siding": "0800 Siding",
    "Electrical": "1000 Electrical", "HVAC": "1000 Electrical",
    "Plumbing": "1100 Plumbing", "Insulation": "1300 Insulation",
    "Drywall": "1400 Drywall", "Doors & Windows": "1500 Doors & Windows",
    "Flooring": "1700 Flooring", "Tile": "1800 Tiling",
    "Waterproofing": "1800 Tiling", "Cabinetry": "1900 Cabinetry",
    "Countertop": "2000 Countertops", "Trimwork": "2100 Trimwork",
    "Finish Carpentry": "2100 Trimwork", "Specialty": "2200 Specialty Finishes",
    "Painting": "2300 Painting", "Appliances": "2400 Appliances",
    "Decking": "2500 Decking", "Stairs": "2500 Decking", "Railing": "2500 Decking",
    "Concrete": "2800 Concrete", "Furnishings": "3000 Furnishings",
    "Miscellaneous": "3100 Miscellaneous", "Protection": "3100 Miscellaneous",
    "Allowances": "3100 Miscellaneous", "Fixtures": "1100 Plumbing",
}

TYPE_TO_COST_TYPE = {
    "Labor": "Labor", "Material": "Materials", "Allowance": "Selections",
    "Other": "Other", "Subcontract": "Subcontractor",
}

UNIT_NAMES = {
    "22Nm3uGRAMm5": "Cubic Yards", "22Nm3uGRAMm6": "Days",
    "22Nm3uGRAMm7": "Each", "22Nm3uGRAMm8": "Gallons",
    "22Nm3uGRAMm9": "Hours", "22Nm3uGRAMmA": "Linear Feet",
    "22Nm3uGRAMmB": "Lump Sum", "22Nm3uGRAMmC": "Pounds",
    "22Nm3uGRAMmD": "Square Feet", "22Nm3uGRAMmE": "Squares",
    "22Nm3uGRAMmF": "Tons",
}

HEADERS = [
    "Cost Item ID", "Cost Item Name", "Description", "Quantity", "Quantity Formula",
    "Unit", "Unit Cost", "Unit Cost Formula", "Unit Price", "Unit Price Formula",
    "Cost Code", "Cost Type", "Taxable", "Allowance Type",
    "Allows Customer Write-In", "Specification", "Require Specification Approval",
    "Show Description", "Show Quantity",
    "Custom Field: URL", "Custom Field: Production Rate",
    "Custom Field: Available Finishes", "Custom Field: Labor Wage",
    "Custom Field: Labor Burden", "Custom Field: Category",
    "Custom Field: Vendor", "Custom Field: Waste",
    "Custom Field: Formula Notes", "Custom Field: Ordered Status",
    "Custom Field: Dimensions", "Custom Field: Specifications",
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def psql_json(sql: str) -> list[dict]:
    result = subprocess.run(
        ["psql", "-d", DB, "-t", "-A", "-c",
         f"SELECT json_agg(t) FROM ({sql}) t"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"psql error: {result.stderr}")
    raw = result.stdout.strip()
    if not raw or raw == "null":
        return []
    return json.loads(raw)


def fmt_num(v):
    """Format a numeric value: empty if None, no trailing zeros."""
    if v is None:
        return ""
    if isinstance(v, str):
        return v
    if v == int(v):
        return str(int(v))
    return str(round(v, 4)).rstrip('0').rstrip('.')


def load_jt_export() -> dict[str, dict]:
    """Load JT export CSV indexed by Cost Item ID."""
    if not JT_EXPORT.exists():
        print(f"  WARNING: {JT_EXPORT.name} not found — no JT fallback data")
        return {}
    jt = {}
    with open(JT_EXPORT, encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            jt[row["Cost Item ID"]] = row
    print(f"  Loaded {len(jt)} items from JT export")
    return jt


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("Loading Postgres data...")
    rows = psql_json("""
        SELECT
            ci.id as pg_id,
            ci.canonical_name,
            ci.display_name,
            ci.description,
            ci.item_type,
            ci.trade,
            ci.jt_catalog_id,
            ci.jt_cost_code_id,
            ci.jt_cost_type_id,
            ci.jt_unit_id,
            ci.unit_cost::float,
            ci.unit_price::float,
            ci.labor_wage::float,
            ci.labor_burden::float,
            ci.available_finishes,
            ci.vendor,
            ci.budget_group_path,
            ar.production_rate::float,
            ar.waste_factor::float,
            ar.qty_formula as assembler_formula,
            ar.default_qty::float,
            ar.condition_trigger,
            ar.project_type as rule_project_type
        FROM catalog_items ci
        LEFT JOIN LATERAL (
            SELECT * FROM assembly_rules ar2
            WHERE ar2.catalog_item_id = ci.id AND ar2.is_active = true
            ORDER BY
                CASE ar2.project_type
                    WHEN 'bathroom' THEN 1
                    WHEN 'deck' THEN 2
                    ELSE 3
                END
            LIMIT 1
        ) ar ON true
        WHERE ci.is_active = true
        ORDER BY ci.id
    """)
    print(f"  {len(rows)} Postgres items")

    print("Loading JT export...")
    jt_by_id = load_jt_export()

    # ── Build CSV rows ───────────────────────────────────────────────────
    errors = []
    names_seen: dict[str, int] = {}
    stats = {
        "with_jt_id": 0, "without_jt_id": 0,
        "qty_formula": 0, "ucf": 0, "upf": 0,
        "prod_rate": 0, "labor_wage": 0, "labor_burden": 0,
        "waste": 0, "url": 0, "uncategorized": 0,
    }

    csv_rows = []
    for r in rows:
        name = r["canonical_name"] or ""
        if not name:
            errors.append(f"PG#{r['pg_id']}: empty canonical_name")
            continue
        if name in names_seen:
            errors.append(f"PG#{r['pg_id']}: duplicate name '{name}' (first: PG#{names_seen[name]})")
        names_seen[name] = r["pg_id"]

        jt_id = r["jt_catalog_id"] or ""
        jt = jt_by_id.get(jt_id, {})
        item_type = r["item_type"] or ""
        is_labor = item_type == "Labor"
        is_material = item_type == "Material"
        is_allowance = item_type == "Allowance"

        # ── Cost code ────────────────────────────────────────────────
        cc_id = r["jt_cost_code_id"]
        cost_code = COST_CODE_NAMES.get(cc_id, "") if cc_id else ""
        if not cost_code or cost_code == "0000 Uncategorized":
            cost_code = TRADE_TO_COST_CODE.get(r["trade"] or "", "")
            if not cost_code:
                errors.append(f"PG#{r['pg_id']}: no cost code for trade '{r['trade']}'")
                cost_code = "3100 Miscellaneous"
            stats["uncategorized"] += 1

        # ── Cost type ────────────────────────────────────────────────
        cost_type = TYPE_TO_COST_TYPE.get(item_type, "Other")

        # ── Unit ─────────────────────────────────────────────────────
        unit = UNIT_NAMES.get(r["jt_unit_id"] or "", "")
        if not unit:
            if is_labor: unit = "Hours"
            elif is_material: unit = "Each"
            elif is_allowance: unit = "Each"
            else: unit = "Lump Sum"

        # ── Taxable ──────────────────────────────────────────────────
        if jt_id and jt.get("Taxable"):
            taxable = jt["Taxable"]
        else:
            taxable = "true" if is_material else "false"

        # ── Quantity ─────────────────────────────────────────────────
        default_qty = r["default_qty"]
        jt_qty = jt.get("Quantity", "").strip()
        if default_qty is not None:
            qty = fmt_num(default_qty)
        elif jt_qty:
            qty = jt_qty
        else:
            qty = "1"

        # ── Quantity Formula ─────────────────────────────────────────
        # Prefer existing JT formula, then generate from standard pattern
        existing_qf = jt.get("Quantity Formula", "").strip()
        if existing_qf:
            qty_formula = existing_qf
        elif r["production_rate"] and is_labor:
            qty_formula = "ceil({parent quantity} * {production rate})"
        elif r["waste_factor"] and r["waste_factor"] > 1.0 and is_material:
            qty_formula = "{parent quantity} * {waste}"
        else:
            qty_formula = ""

        # ── Unit Cost & Formula ──────────────────────────────────────
        unit_cost = r["unit_cost"]
        jt_uc = jt.get("Unit Cost", "").strip()
        if unit_cost is None and jt_uc:
            unit_cost = jt_uc  # keep as string

        existing_ucf = jt.get("Unit Cost Formula", "").strip()
        if existing_ucf:
            ucf = existing_ucf
        elif is_labor and r["labor_wage"] and r["labor_burden"]:
            ucf = "{Labor Wage} * (1 + {Labor Burden})"
        else:
            ucf = ""

        # ── Unit Price & Formula ─────────────────────────────────────
        unit_price = r["unit_price"]
        jt_up = jt.get("Unit Price", "").strip()
        if unit_price is None and jt_up:
            unit_price = jt_up

        existing_upf = jt.get("Unit Price Formula", "").strip()
        if existing_upf:
            upf = existing_upf
        elif is_labor:
            upf = "({Unit Cost} + {Overhead Rate}) * (1 + {Net Profit})"
        else:
            upf = ""

        # ── Custom fields: Postgres sources ──────────────────────────
        prod_rate = r["production_rate"]
        jt_pr = jt.get("Custom Field: Production Rate", "").strip()
        cf_prod_rate = fmt_num(prod_rate) if prod_rate is not None else jt_pr

        labor_wage = r["labor_wage"]
        jt_lw = jt.get("Custom Field: Labor Wage", "").strip()
        cf_labor_wage = fmt_num(labor_wage) if labor_wage is not None else jt_lw

        labor_burden = r["labor_burden"]
        jt_lb = jt.get("Custom Field: Labor Burden", "").strip()
        cf_labor_burden = fmt_num(labor_burden) if labor_burden is not None else jt_lb

        waste = r["waste_factor"]
        jt_w = jt.get("Custom Field: Waste", "").strip()
        cf_waste = fmt_num(waste) if waste is not None else jt_w

        cf_vendor = r["vendor"] or jt.get("Custom Field: Vendor", "")
        cf_finishes = r["available_finishes"] or jt.get("Custom Field: Available Finishes", "")

        # ── Custom fields: JT-only sources ───────────────────────────
        cf_url = jt.get("Custom Field: URL", "")
        cf_category = jt.get("Custom Field: Category", "")
        cf_formula_notes = jt.get("Custom Field: Formula Notes", "")
        cf_ordered = jt.get("Custom Field: Ordered Status", "false")
        cf_dimensions = jt.get("Custom Field: Dimensions", "")
        cf_specs = jt.get("Custom Field: Specifications", "")

        # ── Description ──────────────────────────────────────────────
        desc = r["description"] or jt.get("Description", "")

        # ── Stats tracking ───────────────────────────────────────────
        if jt_id: stats["with_jt_id"] += 1
        else: stats["without_jt_id"] += 1
        if qty_formula: stats["qty_formula"] += 1
        if ucf: stats["ucf"] += 1
        if upf: stats["upf"] += 1
        if cf_prod_rate: stats["prod_rate"] += 1
        if cf_labor_wage: stats["labor_wage"] += 1
        if cf_labor_burden: stats["labor_burden"] += 1
        if cf_waste: stats["waste"] += 1
        if cf_url: stats["url"] += 1

        # ── Build row ────────────────────────────────────────────────
        csv_rows.append({
            "Cost Item ID": jt_id,
            "Cost Item Name": name,
            "Description": desc,
            "Quantity": qty,
            "Quantity Formula": qty_formula,
            "Unit": unit,
            "Unit Cost": fmt_num(unit_cost),
            "Unit Cost Formula": ucf,
            "Unit Price": fmt_num(unit_price),
            "Unit Price Formula": upf,
            "Cost Code": cost_code,
            "Cost Type": cost_type,
            "Taxable": taxable,
            "Allowance Type": "costAndFee" if is_allowance else "",
            "Allows Customer Write-In": "true" if is_allowance else "false",
            "Specification": "false",
            "Require Specification Approval": "false",
            "Show Description": "true",
            "Show Quantity": "true",
            "Custom Field: URL": cf_url,
            "Custom Field: Production Rate": cf_prod_rate,
            "Custom Field: Available Finishes": cf_finishes,
            "Custom Field: Labor Wage": cf_labor_wage,
            "Custom Field: Labor Burden": cf_labor_burden,
            "Custom Field: Category": cf_category,
            "Custom Field: Vendor": cf_vendor,
            "Custom Field: Waste": cf_waste,
            "Custom Field: Formula Notes": cf_formula_notes,
            "Custom Field: Ordered Status": cf_ordered,
            "Custom Field: Dimensions": cf_dimensions,
            "Custom Field: Specifications": cf_specs,
        })

    # ── Validation ───────────────────────────────────────────────────
    print(f"""
VALIDATION REPORT
=================
Total items: {len(csv_rows)} (Postgres active: {len(rows)})
With JT ID (will update): {stats['with_jt_id']}
Without JT ID (will create): {stats['without_jt_id']}

Formulas:
  Quantity Formula populated:   {stats['qty_formula']:>4}  (was 123 in JT export)
  Unit Cost Formula populated:  {stats['ucf']:>4}  (was 56 in JT export)
  Unit Price Formula populated: {stats['upf']:>4}  (was 20 in JT export)

Custom Fields:
  Production Rate: {stats['prod_rate']:>4}  (was 178 in JT export)
  Labor Wage:      {stats['labor_wage']:>4}  (was 196 in JT export)
  Labor Burden:    {stats['labor_burden']:>4}  (was 179 in JT export)
  Waste:           {stats['waste']:>4}  (was 253 in JT export)
  URL:             {stats['url']:>4}  (was 207 in JT export)

Cost Codes:
  Fixed from trade (were uncategorized): {stats['uncategorized']}""")

    if errors:
        print(f"\nERRORS ({len(errors)}):")
        for e in errors:
            print(f"  {e}")

    # ── Diff vs current JT ───────────────────────────────────────────
    if jt_by_id:
        our_ids = {r["Cost Item ID"] for r in csv_rows if r["Cost Item ID"]}
        jt_ids = set(jt_by_id.keys())
        updated = our_ids & jt_ids
        new = len(csv_rows) - len(our_ids)
        dropped = jt_ids - our_ids
        print(f"""
Diff vs JT catalog ({JT_EXPORT.name}, {len(jt_ids)} items):
  Will update (matching ID): {len(updated)}
  Will create (no ID):       {new}
  Dropping from JT:          {len(dropped)}""")

        # Categorize dropped items
        dropped_uncat = sum(1 for d in dropped if jt_by_id[d].get("Cost Code", "") == "0000 Uncategorized")
        dropped_other = len(dropped) - dropped_uncat
        print(f"    Uncategorized:  {dropped_uncat}")
        print(f"    Other:          {dropped_other}")

    # ── Regression check ─────────────────────────────────────────────
    regressions = []
    jt_stats = {"qty_formula": 123, "ucf": 56, "upf": 20,
                "prod_rate": 178, "labor_wage": 196, "labor_burden": 179,
                "waste": 253, "url": 207}
    for key, jt_count in jt_stats.items():
        our_count = stats[key]
        if our_count < jt_count:
            regressions.append(f"  {key}: {our_count} < {jt_count} (LOST {jt_count - our_count})")

    if regressions:
        print(f"\nWARNING — DATA REGRESSIONS (output has fewer than JT export):")
        for r in regressions:
            print(r)
        print("These fields dropped because the JT items were renamed/replaced")
        print("and the old JT IDs no longer match. Check if this is expected.")
    else:
        print("\nNo regressions — all field counts >= JT export.")

    # ── Write CSV ────────────────────────────────────────────────────
    with open(OUTPUT, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=HEADERS)
        writer.writeheader()
        writer.writerows(csv_rows)

    print(f"\nWritten: {OUTPUT}")
    print(f"Rows: {len(csv_rows)}")


if __name__ == "__main__":
    main()
