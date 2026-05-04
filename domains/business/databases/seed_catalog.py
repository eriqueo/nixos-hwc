#!/usr/bin/env python3
"""Seed catalog_items from canonical_catalog_FINAL.csv.

Reads the cleaned CSV, filters to active items (not archive/merge),
looks up JT reference IDs, and upserts into the hwc database.

Usage: sudo python3 seed_catalog.py
"""
import csv
import subprocess
import json
import sys
from pathlib import Path
from decimal import Decimal, InvalidOperation

CSV_PATH = Path.home() / "canonical catalog FINAL.csv"
DB = "hwc"


def psql_exec(sql: str) -> str:
    """Execute SQL and return stdout."""
    cmd = ["sudo", "-u", "postgres", "psql", "-d", DB, "-t", "-A", "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"SQL ERROR: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def psql_json(sql: str) -> list[dict]:
    """Run SQL and return parsed JSON rows."""
    raw = psql_exec(f"SELECT json_agg(t) FROM ({sql}) t;")
    if not raw or raw == "null":
        return []
    return json.loads(raw)


def build_lookups() -> tuple[dict, dict, dict]:
    """Build lookup maps for JT cost codes, cost types, and units."""
    # Cost codes: "0100 Planning" -> JT ID
    codes = psql_json("SELECT id, display_name FROM jt_cost_codes")
    code_map = {r["display_name"]: r["id"] for r in codes}

    # Cost types: "Labor" -> JT ID
    types = psql_json("SELECT id, name FROM jt_cost_types")
    type_map = {r["name"]: r["id"] for r in types}

    # Units: "Hours" -> JT ID
    units = psql_json("SELECT id, name FROM jt_units")
    unit_map = {r["name"]: r["id"] for r in units}

    return code_map, type_map, unit_map


def safe_decimal(val: str) -> str | None:
    """Convert string to decimal or None."""
    if not val or val.strip() == "":
        return None
    try:
        return str(Decimal(val.strip()))
    except InvalidOperation:
        return None


def safe_str(val: str) -> str | None:
    """Return None for empty strings."""
    v = val.strip() if val else ""
    return v if v else None


def escape_sql(val: str | None) -> str:
    """Escape a value for SQL insertion."""
    if val is None:
        return "NULL"
    escaped = val.replace("'", "''")
    return f"'{escaped}'"


def main():
    if not CSV_PATH.exists():
        print(f"CSV not found: {CSV_PATH}", file=sys.stderr)
        sys.exit(1)

    code_map, type_map, unit_map = build_lookups()
    print(f"Lookups: {len(code_map)} cost codes, {len(type_map)} cost types, {len(unit_map)} units")

    with open(CSV_PATH) as f:
        rows = list(csv.DictReader(f))

    # Filter to active items
    active = [r for r in rows if r["proposed_action"] not in ("archive", "merge")]
    merged = [r for r in rows if r["proposed_action"] == "merge"]
    archived = [r for r in rows if r["proposed_action"] == "archive"]
    print(f"CSV: {len(rows)} total, {len(active)} active, {len(merged)} merge, {len(archived)} archive")

    # First, deactivate all existing rows (we'll reactivate matched ones)
    psql_exec("UPDATE catalog_items SET is_active = false;")
    print("Deactivated all existing rows")

    inserted = 0
    updated = 0
    errors = []

    for row in active:
        jt_catalog_id = row["Cost Item ID"].strip()
        item_type = row["proposed_type"].strip()
        trade = row["proposed_trade"].strip()
        subject = row["proposed_subject"].strip()
        spec = row.get("proposed_spec", "").strip()

        # Look up JT reference IDs
        cost_code_display = row["proposed_cost_code"].strip()
        cost_type_name = row["proposed_cost_type"].strip()
        unit_name = row["Unit"].strip()

        jt_cost_code_id = code_map.get(cost_code_display)
        jt_cost_type_id = type_map.get(cost_type_name)
        jt_unit_id = unit_map.get(unit_name) if unit_name else None

        if not jt_cost_code_id:
            errors.append(f"Unknown cost code: {cost_code_display} (item: {row['proposed_name']})")
            continue
        if not jt_cost_type_id:
            errors.append(f"Unknown cost type: {cost_type_name} (item: {row['proposed_name']})")
            continue

        unit_cost = safe_decimal(row["Unit Cost"])
        unit_price = safe_decimal(row["Unit Price"])
        production_rate = safe_decimal(row["Custom Field: Production Rate"])
        labor_wage = safe_decimal(row["Custom Field: Labor Wage"])
        labor_burden = safe_decimal(row["Custom Field: Labor Burden"])
        waste_factor = safe_decimal(row["Custom Field: Waste"])
        description = safe_str(row["Description"])
        available_finishes = safe_str(row["Custom Field: Available Finishes"])
        vendor = safe_str(row["Custom Field: Vendor"])

        # display_name = original JT name (Cost Item Name)
        display_name = row["Cost Item Name"].strip() or row["proposed_name"].strip()

        sql = f"""
            INSERT INTO catalog_items (
                jt_catalog_id, item_type, trade, subject, spec,
                display_name,
                jt_cost_code_id, jt_cost_type_id, jt_unit_id,
                unit_cost, unit_price, production_rate,
                labor_wage, labor_burden, waste_factor,
                description, available_finishes, vendor,
                is_active
            ) VALUES (
                {escape_sql(jt_catalog_id)}, {escape_sql(item_type)}, {escape_sql(trade)},
                {escape_sql(subject)}, {escape_sql(spec)},
                {escape_sql(display_name)},
                {escape_sql(jt_cost_code_id)}, {escape_sql(jt_cost_type_id)},
                {escape_sql(jt_unit_id)},
                {unit_cost or 'NULL'}, {unit_price or 'NULL'}, {production_rate or 'NULL'},
                {labor_wage or 'NULL'}, {labor_burden or 'NULL'}, {waste_factor or 'NULL'},
                {escape_sql(description)}, {escape_sql(available_finishes)}, {escape_sql(vendor)},
                true
            )
            ON CONFLICT (item_type, trade, subject, spec)
            DO UPDATE SET
                jt_catalog_id = EXCLUDED.jt_catalog_id,
                display_name = EXCLUDED.display_name,
                jt_cost_code_id = EXCLUDED.jt_cost_code_id,
                jt_cost_type_id = EXCLUDED.jt_cost_type_id,
                jt_unit_id = EXCLUDED.jt_unit_id,
                unit_cost = EXCLUDED.unit_cost,
                unit_price = EXCLUDED.unit_price,
                production_rate = EXCLUDED.production_rate,
                labor_wage = EXCLUDED.labor_wage,
                labor_burden = EXCLUDED.labor_burden,
                waste_factor = EXCLUDED.waste_factor,
                description = EXCLUDED.description,
                available_finishes = EXCLUDED.available_finishes,
                vendor = EXCLUDED.vendor,
                is_active = true,
                updated_at = now();
        """
        try:
            result = subprocess.run(
                ["sudo", "-u", "postgres", "psql", "-d", DB, "-c", sql],
                capture_output=True, text=True
            )
            if result.returncode != 0:
                errors.append(f"SQL error for {row['proposed_name']}: {result.stderr.strip()}")
            elif "INSERT" in result.stdout:
                inserted += 1
            elif "UPDATE" in result.stdout:
                updated += 1
        except Exception as e:
            errors.append(f"Exception for {row['proposed_name']}: {e}")

    print(f"\nResults: {inserted} inserted, {updated} updated")

    if errors:
        print(f"\n{len(errors)} errors:")
        for e in errors[:20]:
            print(f"  {e}")
        if len(errors) > 20:
            print(f"  ... and {len(errors) - 20} more")

    # Summary
    count = psql_exec("SELECT count(*) FROM catalog_items WHERE is_active = true;")
    total = psql_exec("SELECT count(*) FROM catalog_items;")
    print(f"\nFinal: {count} active / {total} total catalog items")


if __name__ == "__main__":
    main()
