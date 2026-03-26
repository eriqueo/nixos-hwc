#!/usr/bin/env python3
"""Migrate Heartwood catalog from SQLite to Postgres.

Usage: python3 migrate_catalog.py [--dry-run]

Prerequisites:
  - PostgreSQL running and accessible via `sudo -u postgres psql`
  - schema.sql already applied (this script applies it if needed)
"""
import sqlite3
import subprocess
import sys
import os

SQLITE_PATH = os.path.join(os.path.dirname(__file__), "catalog.db")
SCHEMA_PATH = os.path.join(os.path.dirname(__file__), "schema.sql")
DB_NAME = "hwc"
DRY_RUN = "--dry-run" in sys.argv

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def psql(sql, db=DB_NAME, check=True):
    """Run SQL via sudo -u postgres psql. Returns (returncode, stdout, stderr)."""
    cmd = ["sudo", "-u", "postgres", "psql", "-v", "ON_ERROR_STOP=1",
           "-d", db, "-c", sql]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(f"psql error:\n{result.stderr}\nSQL: {sql}")
    return result.returncode, result.stdout, result.stderr


def psql_file(path, db=DB_NAME):
    """Run a SQL file via sudo -u postgres psql."""
    cmd = ["sudo", "-u", "postgres", "psql", "-v", "ON_ERROR_STOP=1",
           "-d", db, "-f", path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"psql file error:\n{result.stderr}")
    return result.stdout


def q(val):
    """Escape a value for SQL (returns 'NULL' or a quoted string/number)."""
    if val is None:
        return "NULL"
    if isinstance(val, (int, float)):
        return str(val)
    # escape single quotes
    return "'" + str(val).replace("'", "''") + "'"


# ---------------------------------------------------------------------------
# Step 1: Ensure hwc database exists
# ---------------------------------------------------------------------------

def ensure_database():
    print("→ Checking hwc database...")
    rc, out, _ = psql("SELECT 1", db="postgres", check=False)
    # Check if hwc exists
    rc2, out2, _ = psql("SELECT datname FROM pg_database WHERE datname='hwc';",
                         db="postgres", check=False)
    if "hwc" not in out2:
        print("  Creating hwc database...")
        if not DRY_RUN:
            psql("CREATE DATABASE hwc;", db="postgres")
        print("  ✓ hwc database created")
    else:
        print("  ✓ hwc database already exists")


# ---------------------------------------------------------------------------
# Step 2: Ensure schema exists
# ---------------------------------------------------------------------------

def ensure_schema():
    print("→ Checking schema...")
    rc, out, _ = psql(
        "SELECT to_regclass('public.catalog_items')::text;", check=False)
    if "catalog_items" in out:
        print("  ✓ Schema already applied")
        return
    print("  Applying schema.sql...")
    if not DRY_RUN:
        psql_file(SCHEMA_PATH)
    print("  ✓ Schema applied")


# ---------------------------------------------------------------------------
# Step 3: Seed admin trade rate (9th trade, missing from schema.sql seed)
# ---------------------------------------------------------------------------

def seed_admin_trade():
    print("→ Seeding admin trade rate...")
    sql = """
        INSERT INTO trade_rates (trade, base_wage, burden_factor, markup_factor)
        VALUES ('admin', 35.00, 1.35, 2.00)
        ON CONFLICT (trade) DO NOTHING;
    """
    if not DRY_RUN:
        psql(sql)
    print("  ✓ admin trade rate seeded")


# ---------------------------------------------------------------------------
# Step 4: Read SQLite data and build insert statements
# ---------------------------------------------------------------------------

# Manual mapping: SQLite cost_type_id → Postgres jt_cost_types.id
COST_TYPE_JT_IDS = {
    "ct_admin":      "22PJuNqewZmV",
    "ct_labor":      "22Nm3uGRAMmq",
    "ct_materials":  "22Nm3uGRAMmr",
    "ct_other":      "22Nm3uGRAMmt",
    "ct_selections": "22PQ4KZExZjP",
}

# SQLite cost_type_id → Postgres catalog_items.item_type
ITEM_TYPE_MAP = {
    "ct_admin":      "other",
    "ct_labor":      "labor",
    "ct_materials":  "material",
    "ct_other":      "other",
    "ct_selections": "allowance",
}

# budget_group_path prefix → trade_rates.trade
TRADE_MAP = {
    "Demo":              "demo",
    "Rough Carpentry":   "framing",
    "Plumbing":          "plumbing",
    "Tilework":          "tile",
    "Drywall":           "drywall",
    "Painting":          "painting",
    "Finish Carpentry":  "finish_carpentry",
    "Electrical":        "electrical",
    "Preconstruction":   "admin",
    "Allowances":        None,
}


def get_trade(budget_group_path):
    prefix = budget_group_path.split(" > ")[0]
    return TRADE_MAP.get(prefix)


def migrate_catalog():
    print("→ Reading SQLite catalog...")
    conn = sqlite3.connect(SQLITE_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    # Build lookup maps from SQLite reference tables
    cur.execute("SELECT id, jt_id FROM cost_codes")
    code_to_jt = {row["id"]: row["jt_id"] for row in cur.fetchall()}

    cur.execute("SELECT id, jt_id FROM units")
    unit_to_jt = {row["id"]: row["jt_id"] for row in cur.fetchall()}

    # Fetch all active cost items
    cur.execute("""
        SELECT canonical_name, description, budget_group_path,
               cost_code_id, cost_type_id, unit_id,
               default_qty, unit_cost, unit_price,
               waste_factor, production_rate,
               qty_driver_key, qty_formula, condition_trigger,
               source, notes, jt_org_cost_item_id, is_active
        FROM cost_items
        WHERE is_active = 1
        ORDER BY id
    """)
    rows = cur.fetchall()
    conn.close()

    print(f"  Found {len(rows)} active items in SQLite")

    inserts = []
    skipped = []
    for row in rows:
        jt_code_id = code_to_jt.get(row["cost_code_id"])
        jt_unit_id = unit_to_jt.get(row["unit_id"])
        jt_type_id = COST_TYPE_JT_IDS.get(row["cost_type_id"])
        item_type  = ITEM_TYPE_MAP.get(row["cost_type_id"], "other")
        trade      = get_trade(row["budget_group_path"])

        # display_name: use canonical_name (strip the pipe-prefix for readability)
        display_name = row["canonical_name"]

        # Combine description + notes into a single description field
        desc_parts = [p for p in [row["description"], row["notes"]] if p and p.strip()]
        description = " | ".join(desc_parts) if desc_parts else None

        sql = f"""
INSERT INTO catalog_items (
    canonical_name, display_name, item_type, trade,
    jt_cost_code_id, jt_cost_type_id, jt_unit_id, jt_org_cost_item_id,
    unit_cost, unit_price, budget_group_path,
    condition_trigger, qty_driver, qty_formula,
    default_qty, waste_factor, production_rate,
    source, description, project_type, is_active
) VALUES (
    {q(row['canonical_name'])}, {q(display_name)}, {q(item_type)}, {q(trade)},
    {q(jt_code_id)}, {q(jt_type_id)}, {q(jt_unit_id)}, {q(row['jt_org_cost_item_id'])},
    {q(row['unit_cost'])}, {q(row['unit_price'])}, {q(row['budget_group_path'])},
    {q(row['condition_trigger'])}, {q(row['qty_driver_key'])}, {q(row['qty_formula'])},
    {q(row['default_qty'])}, {q(row['waste_factor'])}, {q(row['production_rate'])},
    {q(row['source'])}, {q(description)}, 'bathroom', {'true' if row['is_active'] else 'false'}
)
ON CONFLICT (canonical_name) DO UPDATE SET
    display_name       = EXCLUDED.display_name,
    item_type          = EXCLUDED.item_type,
    trade              = EXCLUDED.trade,
    jt_cost_code_id    = EXCLUDED.jt_cost_code_id,
    jt_cost_type_id    = EXCLUDED.jt_cost_type_id,
    jt_unit_id         = EXCLUDED.jt_unit_id,
    jt_org_cost_item_id = EXCLUDED.jt_org_cost_item_id,
    unit_cost          = EXCLUDED.unit_cost,
    unit_price         = EXCLUDED.unit_price,
    budget_group_path  = EXCLUDED.budget_group_path,
    condition_trigger  = EXCLUDED.condition_trigger,
    qty_driver         = EXCLUDED.qty_driver,
    qty_formula        = EXCLUDED.qty_formula,
    default_qty        = EXCLUDED.default_qty,
    waste_factor       = EXCLUDED.waste_factor,
    production_rate    = EXCLUDED.production_rate,
    source             = EXCLUDED.source,
    description        = EXCLUDED.description,
    project_type       = EXCLUDED.project_type,
    is_active          = EXCLUDED.is_active::boolean,
    updated_at         = now();
""".strip()
        inserts.append((row["canonical_name"], sql))

    print(f"  Migrating {len(inserts)} items...")
    errors = []
    for name, sql in inserts:
        if DRY_RUN:
            print(f"  [DRY RUN] Would insert: {name}")
            continue
        try:
            psql(sql)
        except RuntimeError as e:
            errors.append((name, str(e)))
            print(f"  ✗ FAILED: {name}")
            print(f"    {e}")

    if errors:
        print(f"\n  ✗ {len(errors)} items failed to insert")
        for name, err in errors:
            print(f"    - {name}: {err}")
    else:
        print(f"  ✓ All {len(inserts)} items migrated")

    return len(errors) == 0


# ---------------------------------------------------------------------------
# Step 5: Verify
# ---------------------------------------------------------------------------

def verify():
    print("→ Verifying migration...")

    _, out, _ = psql("SELECT count(*) FROM catalog_items;")
    pg_count = int(out.strip().split("\n")[2].strip())

    _, out2, _ = psql("SELECT count(*) FROM trade_rates;")
    tr_count = int(out2.strip().split("\n")[2].strip())

    conn = sqlite3.connect(SQLITE_PATH)
    cur = conn.cursor()
    cur.execute("SELECT count(*) FROM cost_items WHERE is_active = 1")
    sqlite_count = cur.fetchone()[0]
    conn.close()

    print(f"  SQLite active items : {sqlite_count}")
    print(f"  Postgres catalog    : {pg_count}")
    print(f"  Postgres trade_rates: {tr_count}")

    if pg_count == sqlite_count:
        print("  ✓ Counts match!")
    else:
        print(f"  ✗ Count mismatch ({pg_count} vs {sqlite_count})")

    _, out3, _ = psql("SELECT source, count(*) FROM catalog_items GROUP BY source ORDER BY source;")
    print(f"\n  By source:\n{out3}")

    _, out4, _ = psql("SELECT trade, unit_cost, unit_price FROM trade_rates ORDER BY trade;")
    print(f"  Trade rates:\n{out4}")

    return pg_count == sqlite_count and tr_count >= 9


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if DRY_RUN:
        print("=== DRY RUN MODE — no changes will be made ===\n")

    try:
        ensure_database()
        ensure_schema()
        seed_admin_trade()
        ok = migrate_catalog()
        if not DRY_RUN:
            verified = verify()
            if ok and verified:
                print("\n✓ Migration complete.")
            else:
                print("\n✗ Migration completed with errors. Check output above.")
                sys.exit(1)
    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        sys.exit(1)
