-- ============================================================================
-- Migration 001: Catalog Schema Split
-- Separates catalog_items into three layers:
--   1. catalog_items  — price book (what things cost)
--   2. assembly_rules — project intelligence (how to use items in estimates)
--   3. estimate_line_items — project output (editable per-job line items)
--
-- Run against: hwc database, public schema (catalog) + hwc schema (estimates)
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Create assembly_rules table
-- ============================================================================

CREATE TABLE assembly_rules (
    id                  SERIAL PRIMARY KEY,
    catalog_item_id     INT NOT NULL REFERENCES catalog_items(id),
    project_type        TEXT NOT NULL,

    -- Assembly logic (moved from catalog_items)
    budget_group_path   TEXT NOT NULL,
    condition_trigger   TEXT NOT NULL DEFAULT 'always',
    qty_formula         TEXT,
    qty_driver          TEXT,
    default_qty         NUMERIC(10,2) DEFAULT 1,
    production_rate     NUMERIC(8,4),
    waste_factor        NUMERIC(4,2) DEFAULT 1.0,
    sort_order          INT NOT NULL,

    -- Optional pricing overrides (null = use catalog item values)
    unit_cost_override  NUMERIC(10,2),
    unit_price_override NUMERIC(10,2),

    -- Metadata
    description         TEXT,
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ DEFAULT now(),
    updated_at          TIMESTAMPTZ DEFAULT now()
);

-- No unique constraint on (catalog_item_id, project_type, sort_order) —
-- same item can appear twice in a project type with different conditions.
-- Use indexes for lookups instead.
CREATE INDEX idx_rules_project ON assembly_rules(project_type) WHERE is_active;
CREATE INDEX idx_rules_catalog ON assembly_rules(catalog_item_id);
CREATE INDEX idx_rules_sort ON assembly_rules(project_type, sort_order) WHERE is_active;

-- ============================================================================
-- STEP 2: Migrate assembly data from catalog_items to assembly_rules
-- ============================================================================

-- Assembly items are those with both condition_trigger and sort_order set
INSERT INTO assembly_rules (
    catalog_item_id,
    project_type,
    budget_group_path,
    condition_trigger,
    qty_formula,
    qty_driver,
    default_qty,
    production_rate,
    waste_factor,
    sort_order,
    description
)
SELECT
    id,
    COALESCE(project_type, 'bathroom'),
    COALESCE(budget_group_path, ''),
    COALESCE(condition_trigger, 'always'),
    qty_formula,
    qty_driver,
    COALESCE(default_qty, 1),
    production_rate,
    COALESCE(waste_factor, 1.0),
    sort_order,
    description
FROM catalog_items
WHERE is_active = true
  AND condition_trigger IS NOT NULL
  AND sort_order IS NOT NULL;

-- ============================================================================
-- STEP 3: Create estimate_line_items table (in hwc schema, next to estimates)
-- ============================================================================

CREATE TABLE hwc.estimate_line_items (
    id                  SERIAL PRIMARY KEY,
    estimate_id         INT NOT NULL REFERENCES hwc.estimates(id) ON DELETE CASCADE,

    -- Origin tracking
    catalog_item_id     INT REFERENCES catalog_items(id),
    assembly_rule_id    INT REFERENCES assembly_rules(id),
    source              TEXT NOT NULL DEFAULT 'assembled'
                        CHECK (source IN ('assembled', 'catalog_pick', 'custom')),

    -- Line item data (snapshot — independent of catalog after creation)
    name                TEXT NOT NULL,
    budget_group        TEXT,
    item_type           TEXT NOT NULL,
    trade               TEXT,
    cost_code           TEXT,
    unit                TEXT,

    -- Quantities and pricing (editable per project)
    quantity            NUMERIC(10,2) NOT NULL,
    unit_cost           NUMERIC(10,2) NOT NULL,
    unit_price          NUMERIC(10,2) NOT NULL,
    extended_cost       NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_cost) STORED,
    extended_price      NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,

    -- Assembly traceability
    qty_formula_used    TEXT,
    waste_factor_used   NUMERIC(4,2),
    used_default        BOOLEAN DEFAULT false,

    -- Project-level edits
    is_edited           BOOLEAN DEFAULT false,
    notes               TEXT,

    -- Ordering
    sort_order          INT,
    created_at          TIMESTAMPTZ DEFAULT now(),
    updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_line_items_estimate ON hwc.estimate_line_items(estimate_id);

-- ============================================================================
-- STEP 4: Clean up catalog_items
-- Remove assembly-only columns. Keep budget_group_path as default for
-- catalog picks (critique: browser needs it for non-assembled items).
-- ============================================================================

-- Drop assembly-specific columns from catalog_items.
-- These now live on assembly_rules.
-- NOTE: We keep budget_group_path on catalog_items as the default group
-- for catalog-pick line items. Assembly rules override it.
ALTER TABLE catalog_items DROP COLUMN IF EXISTS condition_trigger;
ALTER TABLE catalog_items DROP COLUMN IF EXISTS qty_formula;
ALTER TABLE catalog_items DROP COLUMN IF EXISTS qty_driver;
ALTER TABLE catalog_items DROP COLUMN IF EXISTS default_qty;
ALTER TABLE catalog_items DROP COLUMN IF EXISTS production_rate;
ALTER TABLE catalog_items DROP COLUMN IF EXISTS waste_factor;
ALTER TABLE catalog_items DROP COLUMN IF EXISTS sort_order;

-- Remove the project_type constraint — price book items are universal.
-- Keep the column temporarily for migration verification, then drop.
-- For now, set all items to NULL to indicate they're universal.
ALTER TABLE catalog_items ALTER COLUMN project_type DROP DEFAULT;
-- Don't drop project_type yet — assembly_rules references it for migration
-- verification. We'll drop it in a future migration once verified.

-- Drop the project_type index (no longer meaningful on catalog_items)
DROP INDEX IF EXISTS idx_catalog_project_type;

-- ============================================================================
-- STEP 5: Grants
-- ============================================================================

GRANT ALL PRIVILEGES ON assembly_rules TO business_user;
GRANT ALL PRIVILEGES ON SEQUENCE assembly_rules_id_seq TO business_user;
GRANT ALL PRIVILEGES ON hwc.estimate_line_items TO business_user;
GRANT ALL PRIVILEGES ON SEQUENCE hwc.estimate_line_items_id_seq TO business_user;

-- ============================================================================
-- STEP 6: Triggers (auto-update timestamps)
-- ============================================================================

-- Ensure trigger function exists in public schema
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_assembly_rules_ts BEFORE UPDATE ON assembly_rules
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_estimate_line_items_ts BEFORE UPDATE ON hwc.estimate_line_items
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================================
-- Verification queries (run manually after migration)
-- ============================================================================

-- Should match original assembly item count (123):
-- SELECT count(*) FROM assembly_rules;

-- Should show same distribution:
-- SELECT project_type, count(*) FROM assembly_rules WHERE is_active GROUP BY project_type;

-- Every rule should reference a valid catalog item:
-- SELECT count(*) FROM assembly_rules ar
-- LEFT JOIN catalog_items ci ON ar.catalog_item_id = ci.id
-- WHERE ci.id IS NULL;

COMMIT;
