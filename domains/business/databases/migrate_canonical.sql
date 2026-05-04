-- ============================================================================
-- MIGRATION: Add canonical naming convention to catalog_items
-- Run: sudo -u postgres psql -d hwc -f migrate_canonical.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Drop FK and constraints that block schema changes (must be first!)
-- ============================================================================

ALTER TABLE catalog_items DROP CONSTRAINT IF EXISTS catalog_items_trade_fkey;
ALTER TABLE catalog_items DROP CONSTRAINT IF EXISTS catalog_items_item_type_check;
ALTER TABLE catalog_items DROP CONSTRAINT IF EXISTS catalog_items_canonical_name_key;
ALTER TABLE catalog_items DROP CONSTRAINT IF EXISTS catalog_items_source_check;
ALTER TABLE catalog_items DROP CONSTRAINT IF EXISTS catalog_items_project_type_check;

-- ============================================================================
-- STEP 2: Update trade_rates — add all convention trades
-- Keep lowercase keys for rate lookups. Add missing trades with defaults.
-- ============================================================================

-- Rename existing trades to match convention lowercase keys
UPDATE trade_rates SET trade = 'planning' WHERE trade = 'admin';
UPDATE trade_rates SET trade = 'trimwork' WHERE trade = 'finish_carpentry';

-- Add missing trades (15 new)
INSERT INTO trade_rates (trade, base_wage, burden_factor, markup_factor) VALUES
    ('appliances',      35.00, 1.35, 1.85),
    ('cabinetry',       35.00, 1.35, 1.85),
    ('cleanup',         35.00, 1.35, 1.85),
    ('concrete',        35.00, 1.35, 1.85),
    ('countertop',      35.00, 1.35, 1.85),
    ('decking',         35.00, 1.35, 1.85),
    ('doors_windows',   35.00, 1.35, 1.85),
    ('flooring',        35.00, 1.35, 1.85),
    ('furnishings',     35.00, 1.35, 1.85),
    ('hvac',            35.00, 1.35, 1.85),
    ('insulation',      35.00, 1.35, 1.85),
    ('miscellaneous',   35.00, 1.35, 1.85),
    ('siding',          35.00, 1.35, 1.85),
    ('sitework',        35.00, 1.35, 1.85),
    ('specialty',       35.00, 1.35, 1.85)
ON CONFLICT (trade) DO NOTHING;

-- ============================================================================
-- STEP 3: Add new columns
-- ============================================================================

ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS subject TEXT;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS spec TEXT DEFAULT '';
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS jt_catalog_id TEXT;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS labor_wage NUMERIC(8,2);
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS labor_burden NUMERIC(5,3);
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS vendor TEXT;
ALTER TABLE catalog_items ADD COLUMN IF NOT EXISTS available_finishes TEXT;

-- ============================================================================
-- STEP 4: Parse existing canonical_name into structured fields
-- Existing format: "Type | Trade | Subject" or "Type | Trade | Subject | Spec"
-- Update item_type/trade to Title Case from canonical_name segments
-- ============================================================================

UPDATE catalog_items SET
    item_type = (string_to_array(canonical_name, ' | '))[1],
    trade     = (string_to_array(canonical_name, ' | '))[2],
    subject   = (string_to_array(canonical_name, ' | '))[3],
    spec      = COALESCE((string_to_array(canonical_name, ' | '))[4], '')
WHERE subject IS NULL;

-- Copy jt_org_cost_item_id to jt_catalog_id for existing rows
UPDATE catalog_items SET jt_catalog_id = jt_org_cost_item_id
WHERE jt_catalog_id IS NULL AND jt_org_cost_item_id IS NOT NULL;

-- ============================================================================
-- STEP 5: Drop old canonical_name, recreate as generated column
-- ============================================================================

ALTER TABLE catalog_items DROP COLUMN canonical_name;
ALTER TABLE catalog_items ADD COLUMN canonical_name TEXT GENERATED ALWAYS AS (
    item_type || ' | ' || trade || ' | ' || subject ||
    CASE WHEN spec IS NOT NULL AND spec != '' THEN ' | ' || spec ELSE '' END
) STORED;

-- ============================================================================
-- STEP 6: Add new constraints
-- ============================================================================

-- item_type: Title Case to match naming convention
ALTER TABLE catalog_items ADD CONSTRAINT catalog_items_item_type_check
    CHECK (item_type IN ('Labor', 'Material', 'Subcontract', 'Allowance', 'Other'));

-- Unique on structured fields (prevents duplicate canonical names)
ALTER TABLE catalog_items ADD CONSTRAINT catalog_items_unique_canonical
    UNIQUE (item_type, trade, subject, spec);

-- Index on jt_catalog_id (not unique — allowance tiers share JT IDs)
CREATE INDEX IF NOT EXISTS idx_catalog_jt_catalog_id
    ON catalog_items(jt_catalog_id) WHERE jt_catalog_id IS NOT NULL;

-- ============================================================================
-- STEP 7: Add useful indexes
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_catalog_type ON catalog_items(item_type);
CREATE INDEX IF NOT EXISTS idx_catalog_subject ON catalog_items(subject);

COMMIT;
