-- ============================================================================
-- HEARTWOOD CRAFT — Local Postgres Schema
-- The single local data store for all Heartwood apps and workflows
-- Lives on the NixOS homeserver alongside n8n
-- ============================================================================

-- Design principles:
--   1. JT is the customer/job source of truth. We mirror IDs, never duplicate CRM.
--   2. Project state lives here. JT doesn't store measurements/toggles/conditions.
--   3. The cost catalog lives here. Exported to JSON for apps at build time.
--   4. Every app reads/writes through n8n webhooks, never directly.
--   5. This schema supports: assembler, calculator, future deck/kitchen estimators.

BEGIN;

-- ============================================================================
-- SECTION 1: JT REFERENCE TABLES
-- Mirrors of JT's classification system. Seeded once, updated rarely.
-- These give your n8n workflows and assembler the actual JT IDs they need
-- without hardcoding them into app code.
-- ============================================================================

CREATE TABLE jt_cost_codes (
    id              TEXT PRIMARY KEY,        -- JT's actual ID (e.g., '22Nm3uGRAMma')
    code            TEXT NOT NULL,           -- e.g., '1800'
    name            TEXT NOT NULL,           -- e.g., 'Tiling'
    display_name    TEXT NOT NULL,           -- e.g., '1800 Tiling'
    sort_order      INT DEFAULT 0
);

-- Seed from your actual JT org:
INSERT INTO jt_cost_codes (id, code, name, display_name, sort_order) VALUES
('22Nm3uGRAMmG', '0000', 'Uncategorized',      '0000 Uncategorized', 0),
('22Nm3uGRAMmH', '0100', 'Planning',            '0100 Planning', 1),
('22NxeGLaJCQT', '0110', 'Site Preparation',    '0110 Site Preparation', 2),
('22Nm3uGRAMmJ', '0200', 'Demolition',          '0200 Demolition', 3),
('22Nm3uGRAMmL', '0400', 'Utilities',           '0400 Utilities', 4),
('22Nm3uGRAMmM', '0500', 'Foundation',          '0500 Foundation', 5),
('22Nm3uGRAMmN', '0600', 'Framing',             '0600 Framing', 6),
('22Nm3uGRAMmQ', '0800', 'Siding',              '0800 Siding', 7),
('22Nm3uGRAMmS', '1000', 'Electrical',          '1000 Electrical', 8),
('22Nm3uGRAMmT', '1100', 'Plumbing',            '1100 Plumbing', 9),
('22Nm3uGRAMmV', '1300', 'Insulation',          '1300 Insulation', 10),
('22Nm3uGRAMmW', '1400', 'Drywall',             '1400 Drywall', 11),
('22Nm3uGRAMmX', '1500', 'Doors & Windows',     '1500 Doors & Windows', 12),
('22Nm3uGRAMmZ', '1700', 'Flooring',            '1700 Flooring', 13),
('22Nm3uGRAMma', '1800', 'Tiling',              '1800 Tiling', 14),
('22Nm3uGRAMmb', '1900', 'Cabinetry',           '1900 Cabinetry', 15),
('22Nm3uGRAMmc', '2000', 'Countertops',         '2000 Countertops', 16),
('22Nm3uGRAMmd', '2100', 'Trimwork',            '2100 Trimwork', 17),
('22Nm3uGRAMme', '2200', 'Specialty Finishes',  '2200 Specialty Finishes', 18),
('22Nm3uGRAMmf', '2300', 'Painting',            '2300 Painting', 19),
('22Nm3uGRAMmg', '2400', 'Appliances',          '2400 Appliances', 20),
('22Nm3uGRAMmh', '2500', 'Decking',             '2500 Decking', 21),
('22Nm3uGRAMmi', '2600', 'Fencing',             '2600 Fencing', 22),
('22Nm3uGRAMmk', '2800', 'Concrete',            '2800 Concrete', 23),
('22Nm3uGRAMmn', '3000', 'Furnishings',         '3000 Furnishings', 24),
('22Nm3uGRAMmp', '3100', 'Miscellaneous',       '3100 Miscellaneous', 25);

CREATE TABLE jt_cost_types (
    id              TEXT PRIMARY KEY,        -- JT's actual ID
    name            TEXT NOT NULL,           -- e.g., 'Labor', 'Materials'
    default_margin  NUMERIC(4,2) DEFAULT 0.50
);

INSERT INTO jt_cost_types (id, name, default_margin) VALUES
('22PJuNqewZmV', 'Admin',          0.50),
('22Nm3uGRAMmq', 'Labor',          0.50),
('22Nm3uGRAMmr', 'Materials',      0.50),
('22Nm3uGRAMmt', 'Other',          0.50),
('22PQ4KZExZjP', 'Selections',     0.30),
('22Nm3uGRAMms', 'Subcontractor',  0.30);

CREATE TABLE jt_units (
    id              TEXT PRIMARY KEY,        -- JT's actual ID
    name            TEXT NOT NULL            -- e.g., 'Hours', 'Square Feet'
);

INSERT INTO jt_units (id, name) VALUES
('22Nm3uGRAMm5', 'Cubic Yards'),
('22Nm3uGRAMm6', 'Days'),
('22Nm3uGRAMm7', 'Each'),
('22Nm3uGRAMm8', 'Gallons'),
('22Nm3uGRAMm9', 'Hours'),
('22Nm3uGRAMmA', 'Linear Feet'),
('22Nm3uGRAMmB', 'Lump Sum'),
('22Nm3uGRAMmC', 'Pounds'),
('22Nm3uGRAMmD', 'Square Feet'),
('22Nm3uGRAMmE', 'Squares'),
('22Nm3uGRAMmF', 'Tons');


-- ============================================================================
-- SECTION 2: COST CATALOG
-- The stable knowledge that changes slowly. Your assembler's brain.
-- Exported to JSON for apps at build time.
-- ============================================================================

CREATE TABLE trade_rates (
    id              SERIAL PRIMARY KEY,
    trade           TEXT NOT NULL UNIQUE,     -- e.g., 'demo', 'tile', 'plumbing'
    base_wage       NUMERIC(8,2) NOT NULL,   -- $/hr (e.g., 35.00)
    burden_factor   NUMERIC(4,2) NOT NULL,   -- e.g., 1.35
    markup_factor   NUMERIC(4,2) NOT NULL,   -- e.g., 2.00
    -- derived (stored for convenience, recalculated on update)
    unit_cost       NUMERIC(8,2) GENERATED ALWAYS AS (base_wage * burden_factor) STORED,
    unit_price      NUMERIC(8,2) GENERATED ALWAYS AS (base_wage * burden_factor * markup_factor) STORED,
    updated_at      TIMESTAMPTZ DEFAULT now()
);

INSERT INTO trade_rates (trade, base_wage, burden_factor, markup_factor) VALUES
('demo',              35.00, 1.35, 2.00),
('framing',           35.00, 1.35, 2.00),
('plumbing',          35.00, 1.35, 2.00),
('tile',              35.00, 1.35, 2.00),
('drywall',           35.00, 1.35, 2.00),
('painting',          35.00, 1.35, 2.00),
('finish_carpentry',  35.00, 1.35, 2.00),
('electrical',        35.00, 1.35, 2.00);

CREATE TABLE catalog_items (
    id                  SERIAL PRIMARY KEY,
    canonical_name      TEXT NOT NULL UNIQUE,     -- 'Labor | Tile | Shower Installation'
    display_name        TEXT NOT NULL,            -- Human-readable for JT
    item_type           TEXT NOT NULL CHECK (item_type IN ('labor', 'material', 'allowance', 'other')),
    trade               TEXT REFERENCES trade_rates(trade),
    -- JT classification (references the jt_ tables)
    jt_cost_code_id     TEXT REFERENCES jt_cost_codes(id),
    jt_cost_type_id     TEXT REFERENCES jt_cost_types(id),
    jt_unit_id          TEXT REFERENCES jt_units(id),
    -- For linking to JT's org-level cost item catalog
    jt_org_cost_item_id TEXT,                    -- JT's org catalog item ID if synced
    -- Pricing
    unit_cost           NUMERIC(10,2),           -- For materials: actual cost. For labor: from trade_rates
    unit_price          NUMERIC(10,2),           -- For materials: cost * 1.43. For labor: from trade_rates
    -- Assembly logic
    budget_group_path   TEXT,                    -- e.g., 'Tilework > Shower Tile Labor'
    condition_trigger   TEXT,                    -- Boolean expression: 'has_shower AND tile_level != "none"'
    qty_driver          TEXT,                    -- State key(s) that drive quantity: 'wall_tile_sqft'
    qty_formula         TEXT,                    -- Expression: 'wall_tile_sqft * 0.25' or 'niche_count * 4'
    default_qty         NUMERIC(10,2) DEFAULT 1,
    waste_factor        NUMERIC(4,2) DEFAULT 1.0,
    production_rate     NUMERIC(8,2),            -- hrs/sqft or hrs/unit for labor items
    -- Metadata
    source              TEXT DEFAULT 'heartwood' CHECK (source IN ('heartwood', 'craftsman', 'custom')),
    description         TEXT,
    project_type        TEXT DEFAULT 'bathroom' CHECK (project_type IN ('bathroom', 'deck', 'kitchen', 'general')),
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ DEFAULT now(),
    updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_catalog_project_type ON catalog_items(project_type) WHERE is_active;
CREATE INDEX idx_catalog_trade ON catalog_items(trade);


-- ============================================================================
-- SECTION 3: PROJECT STATE
-- The variable per-job data that drives assembly.
-- This is the canonical schema that ALL apps share.
-- ============================================================================

CREATE TABLE projects (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- JT linkage (populated after JT job is created)
    jt_job_id       TEXT,                    -- JT's job ID
    jt_job_number   INT,                     -- JT's job number (e.g., 257, 281)
    jt_account_id   TEXT,                    -- JT's customer account ID
    -- Project metadata
    project_type    TEXT NOT NULL DEFAULT 'bathroom'
                    CHECK (project_type IN ('bathroom', 'deck', 'kitchen')),
    name            TEXT,                    -- Client name or project label
    address         TEXT,
    -- Source tracking (which app/channel created this)
    source          TEXT NOT NULL DEFAULT 'assembler'
                    CHECK (source IN ('assembler', 'calculator', 'manual', 'import')),
    lead_channel    TEXT CHECK (lead_channel IN (
                    'lsa', 'gbp', 'referral', 'pm_outreach',
                    'website_form', 'website_calculator', 'social', 'other')),
    -- Pipeline status
    stage           TEXT DEFAULT 'lead'
                    CHECK (stage IN ('lead', 'qualified', 'visited', 'estimated', 
                                     'proposed', 'signed', 'in_progress', 'complete', 'lost')),
    lost_reason     TEXT,
    -- Estimate summary (denormalized for quick reads)
    total_cost      NUMERIC(12,2),
    total_price     NUMERIC(12,2),
    margin_pct      NUMERIC(5,2),
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    estimated_at    TIMESTAMPTZ,
    pushed_to_jt_at TIMESTAMPTZ
);

CREATE INDEX idx_projects_stage ON projects(stage);
CREATE INDEX idx_projects_jt_job ON projects(jt_job_id);

-- The actual state: flat key-value pairs per project.
-- This is what the assembler writes and reads.
-- Keys follow zone.attribute convention: bathroom.tile_height, bathroom.has_tub
CREATE TABLE project_state (
    id              SERIAL PRIMARY KEY,
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    key             TEXT NOT NULL,            -- e.g., 'room_length', 'has_tub', 'wall_tile_family'
    value           TEXT NOT NULL,            -- All values stored as text, cast as needed
    value_type      TEXT NOT NULL DEFAULT 'text'
                    CHECK (value_type IN ('text', 'number', 'boolean', 'json')),
    category        TEXT NOT NULL DEFAULT 'measurement'
                    CHECK (category IN ('measurement', 'condition', 'count',
                                        'selection', 'constraint', 'derived')),
    UNIQUE (project_id, key)
);

CREATE INDEX idx_state_project ON project_state(project_id);
CREATE INDEX idx_state_key ON project_state(key);


-- ============================================================================
-- SECTION 4: ESTIMATES
-- Assembled output. Versioned so you can track changes over time.
-- ============================================================================

CREATE TABLE estimates (
    id              SERIAL PRIMARY KEY,
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    version         INT NOT NULL DEFAULT 1,
    -- Summary
    total_cost      NUMERIC(12,2),
    total_price     NUMERIC(12,2),
    margin_pct      NUMERIC(5,2),
    item_count      INT,
    -- The full assembled output (for archival + change order diffs)
    line_items_json JSONB NOT NULL,          -- Array of assembled line items
    state_snapshot  JSONB NOT NULL,          -- Project state at time of assembly
    -- Metadata
    assembled_by    TEXT DEFAULT 'assembler', -- 'assembler' or 'manual'
    pushed_to_jt    BOOLEAN DEFAULT false,
    jt_push_at      TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE (project_id, version)
);


-- ============================================================================
-- SECTION 5: LEADS (from the public calculator)
-- Simplified state from website visitors. Feeds Stage 1 of client journey.
-- ============================================================================

CREATE TABLE calculator_leads (
    id              SERIAL PRIMARY KEY,
    -- Contact info (gated behind the form)
    name            TEXT NOT NULL,
    email           TEXT,
    phone           TEXT NOT NULL,
    notes           TEXT,
    -- Simplified project state from calculator
    project_type    TEXT,                    -- 'full_gut', 'refresh', etc.
    bathroom_size   TEXT,                    -- 'small', 'medium', 'large', 'xl'
    shower_tub      TEXT,                    -- 'shower_only', 'tub_shower', etc.
    tile_level      TEXT,                    -- 'basic', 'mid', 'high'
    fixtures        TEXT,                    -- 'standard', 'upgraded', 'premium'
    features        TEXT[],                  -- ARRAY['heated_floor', 'niches', ...]
    timeline        TEXT,                    -- 'asap', '1_3_months', etc.
    -- Calculated range shown to visitor
    estimate_low    NUMERIC(10,2),
    estimate_high   NUMERIC(10,2),
    -- Pipeline tracking
    status          TEXT DEFAULT 'new'
                    CHECK (status IN ('new', 'contacted', 'qualified', 'converted', 'dead')),
    -- Link to full project if converted
    project_id      UUID REFERENCES projects(id),
    jt_account_id   TEXT,                    -- JT account ID once created
    -- Metadata
    source_url      TEXT,
    utm_source      TEXT,
    utm_medium      TEXT,
    utm_campaign    TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    contacted_at    TIMESTAMPTZ,
    converted_at    TIMESTAMPTZ
);

CREATE INDEX idx_leads_status ON calculator_leads(status);
CREATE INDEX idx_leads_created ON calculator_leads(created_at DESC);


-- ============================================================================
-- SECTION 6: N8N WORKFLOW LOG
-- Every external action n8n takes gets logged here.
-- Debugging breadcrumbs for when things go wrong.
-- ============================================================================

CREATE TABLE workflow_log (
    id              SERIAL PRIMARY KEY,
    workflow_name   TEXT NOT NULL,            -- e.g., 'assembler_push', 'calculator_lead', 'jt_sync'
    trigger_source  TEXT,                     -- 'assembler', 'calculator', 'cron', 'webhook'
    project_id      UUID REFERENCES projects(id),
    lead_id         INT REFERENCES calculator_leads(id),
    -- What happened
    action          TEXT NOT NULL,            -- 'create_account', 'push_budget', 'send_slack', etc.
    target_system   TEXT NOT NULL,            -- 'jobtread', 'slack', 'postgres', 'email'
    request_payload JSONB,                   -- What was sent
    response_payload JSONB,                  -- What came back
    -- Result
    success         BOOLEAN NOT NULL,
    error_message   TEXT,
    duration_ms     INT,
    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_log_project ON workflow_log(project_id);
CREATE INDEX idx_log_created ON workflow_log(created_at DESC);
CREATE INDEX idx_log_errors ON workflow_log(success) WHERE NOT success;


-- ============================================================================
-- SECTION 7: VIEWS FOR COMMON QUERIES
-- ============================================================================

-- Pipeline overview: how many projects at each stage
CREATE VIEW pipeline_summary AS
SELECT stage, count(*) AS count,
       sum(total_price) AS total_value,
       avg(margin_pct) AS avg_margin
FROM projects
WHERE stage NOT IN ('lost', 'complete')
GROUP BY stage
ORDER BY array_position(
    ARRAY['lead','qualified','visited','estimated','proposed','signed','in_progress'],
    stage
);

-- Lead conversion funnel
CREATE VIEW lead_funnel AS
SELECT 
    date_trunc('month', created_at) AS month,
    count(*) AS total_leads,
    count(*) FILTER (WHERE status != 'dead') AS active,
    count(*) FILTER (WHERE status = 'contacted') AS contacted,
    count(*) FILTER (WHERE status = 'qualified') AS qualified,
    count(*) FILTER (WHERE status = 'converted') AS converted,
    round(100.0 * count(*) FILTER (WHERE status = 'converted') / nullif(count(*), 0), 1) AS conversion_pct
FROM calculator_leads
GROUP BY 1
ORDER BY 1 DESC;

-- Marketing ROI by channel
CREATE VIEW channel_roi AS
SELECT 
    lead_channel,
    count(*) AS total_projects,
    count(*) FILTER (WHERE stage = 'complete') AS completed,
    sum(total_price) FILTER (WHERE stage = 'complete') AS revenue,
    avg(margin_pct) FILTER (WHERE stage = 'complete') AS avg_margin
FROM projects
WHERE lead_channel IS NOT NULL
GROUP BY lead_channel
ORDER BY revenue DESC NULLS LAST;

-- ============================================================================
-- SECTION 8: VENDORS
-- Normalized vendor directory. Used by receipts OCR and purchasable by
-- estimator line items. Name variants allow fuzzy OCR matching.
-- ============================================================================

CREATE TABLE vendors (
    id              SERIAL PRIMARY KEY,
    name_normalized TEXT UNIQUE NOT NULL,
    name_variants   TEXT[] DEFAULT '{}',
    category        TEXT,                     -- e.g., 'hardware_store', 'lumber_yard'
    tax_id          TEXT,
    account_number  TEXT,
    contact_name    TEXT,
    contact_email   TEXT,
    contact_phone   TEXT,
    address         TEXT,
    payment_terms   TEXT,
    preferred       BOOLEAN DEFAULT FALSE,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_vendors_name ON vendors(name_normalized);
CREATE INDEX idx_vendors_category ON vendors(category);


-- ============================================================================
-- SECTION 9: EXPENSE CATEGORIES
-- Maps to JT cost codes for receipt categorization.
-- ============================================================================

CREATE TABLE expense_categories (
    id                  SERIAL PRIMARY KEY,
    name                TEXT UNIQUE NOT NULL,
    parent_category_id  INTEGER REFERENCES expense_categories(id),
    jt_cost_code_id     TEXT REFERENCES jt_cost_codes(id),   -- link to JT taxonomy
    tax_deductible      BOOLEAN DEFAULT TRUE,
    billable_to_client  BOOLEAN DEFAULT TRUE,
    description         TEXT,
    created_at          TIMESTAMPTZ DEFAULT now()
);

-- Seed default categories (linked to JT cost codes where applicable)
INSERT INTO expense_categories (name, jt_cost_code_id, tax_deductible, billable_to_client) VALUES
    ('Materials',        '22Nm3uGRAMmr', TRUE, TRUE),   -- not a cost code but close mapping
    ('Labor',            NULL,            TRUE, TRUE),
    ('Tools',            NULL,            TRUE, FALSE),
    ('Office Supplies',  NULL,            TRUE, FALSE),
    ('Fuel',             NULL,            TRUE, FALSE),
    ('Permits & Fees',   NULL,            TRUE, TRUE),
    ('Subcontractors',   NULL,            TRUE, TRUE)
ON CONFLICT (name) DO NOTHING;

-- Subcategories under Materials
INSERT INTO expense_categories (name, parent_category_id, tax_deductible, billable_to_client)
SELECT sub.name, ec.id, TRUE, TRUE
FROM (VALUES ('Lumber'), ('Hardware'), ('Paint & Finishing'), ('Electrical'), ('Plumbing')) AS sub(name)
CROSS JOIN expense_categories ec WHERE ec.name = 'Materials'
ON CONFLICT (name) DO NOTHING;


-- ============================================================================
-- SECTION 10: RECEIPTS OCR PIPELINE
-- Receipt images → OCR → LLM normalization → structured data.
-- Receipts link to projects (which carry JT job IDs) and vendors.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE receipts (
    id                      SERIAL PRIMARY KEY,
    uuid                    UUID DEFAULT gen_random_uuid() UNIQUE NOT NULL,

    -- File information
    image_path              TEXT NOT NULL,
    image_filename          TEXT NOT NULL,
    file_size_bytes         INTEGER,
    file_hash               TEXT,             -- SHA-256 for duplicate detection
    mime_type               TEXT,

    -- Timestamps
    upload_timestamp        TIMESTAMPTZ DEFAULT now(),
    process_start_timestamp TIMESTAMPTZ,
    process_end_timestamp   TIMESTAMPTZ,

    -- Processing status
    status                  TEXT CHECK (status IN (
                                'pending', 'processing', 'completed',
                                'failed', 'review_needed', 'archived'
                            )) DEFAULT 'pending',

    -- OCR extracted data
    receipt_date            DATE,
    receipt_time            TIME,
    vendor_raw              TEXT,
    vendor_normalized       TEXT,
    vendor_id               INTEGER REFERENCES vendors(id),

    -- Financial data
    subtotal                NUMERIC(10,2),
    tax_amount              NUMERIC(10,2),
    tip_amount              NUMERIC(10,2),
    discount_amount         NUMERIC(10,2),
    total_amount            NUMERIC(10,2),    -- nullable: OCR may fail to extract
    currency                TEXT DEFAULT 'USD',

    -- Business context — links to projects (which carry JT job IDs)
    project_id              UUID REFERENCES projects(id),
    category_id             INTEGER REFERENCES expense_categories(id),
    payment_method          TEXT CHECK (payment_method IN (
                                'cash', 'credit_card', 'debit_card',
                                'check', 'wire_transfer', 'other'
                            )),
    payment_reference       TEXT,

    -- Review and validation
    ocr_confidence          NUMERIC(3,2) CHECK (ocr_confidence BETWEEN 0 AND 1),
    needs_review            BOOLEAN DEFAULT FALSE,
    review_reason           TEXT,
    reviewed_by             TEXT,
    reviewed_at             TIMESTAMPTZ,

    -- Raw data preservation
    ocr_raw_text            TEXT,
    ocr_raw_json            JSONB,
    llm_metadata            JSONB,

    -- Audit fields
    notes                   TEXT,
    tags                    TEXT[],
    created_by              TEXT DEFAULT 'system',
    updated_by              TEXT,
    created_at              TIMESTAMPTZ DEFAULT now(),
    updated_at              TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_receipts_status ON receipts(status);
CREATE INDEX idx_receipts_date ON receipts(receipt_date);
CREATE INDEX idx_receipts_project ON receipts(project_id);
CREATE INDEX idx_receipts_vendor ON receipts(vendor_id);
CREATE INDEX idx_receipts_review ON receipts(needs_review) WHERE needs_review = TRUE;
CREATE INDEX idx_receipts_uuid ON receipts(uuid);
CREATE INDEX idx_receipts_hash ON receipts(file_hash);

-- Line items extracted from a receipt
CREATE TABLE receipt_items (
    id              SERIAL PRIMARY KEY,
    receipt_id      INTEGER REFERENCES receipts(id) ON DELETE CASCADE NOT NULL,
    line_number     INTEGER,
    description     TEXT NOT NULL,
    quantity        NUMERIC(10,3) DEFAULT 1,
    unit_price      NUMERIC(10,2),
    total_price     NUMERIC(10,2) NOT NULL,
    category_id     INTEGER REFERENCES expense_categories(id),
    sku             TEXT,
    upc             TEXT,
    tax_rate        NUMERIC(5,4),
    taxable         BOOLEAN DEFAULT TRUE,
    -- Optional: link item to a specific project (for splitting across projects)
    project_id      UUID REFERENCES projects(id),
    billable        BOOLEAN DEFAULT TRUE,
    -- Optional: link to cost catalog for matching
    catalog_item_id INTEGER REFERENCES catalog_items(id),
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE(receipt_id, line_number)
);

CREATE INDEX idx_receipt_items_receipt ON receipt_items(receipt_id);
CREATE INDEX idx_receipt_items_project ON receipt_items(project_id);

-- Audit log for each processing step
CREATE TABLE receipt_processing_log (
    id              SERIAL PRIMARY KEY,
    receipt_id      INTEGER REFERENCES receipts(id) ON DELETE CASCADE,
    timestamp       TIMESTAMPTZ DEFAULT now(),
    step            TEXT NOT NULL CHECK (step IN (
                        'upload', 'validation', 'preprocessing', 'ocr',
                        'llm_normalization', 'extraction', 'database_insert',
                        'review', 'failure', 'retry'
                    )),
    status          TEXT NOT NULL CHECK (status IN (
                        'started', 'success', 'failed', 'skipped'
                    )),
    duration_ms     INTEGER,
    error_message   TEXT,
    error_stack     TEXT,
    metadata        JSONB,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_proc_log_receipt ON receipt_processing_log(receipt_id);
CREATE INDEX idx_proc_log_ts ON receipt_processing_log(timestamp);

-- Manual review queue
CREATE TABLE receipt_review_queue (
    id              SERIAL PRIMARY KEY,
    receipt_id      INTEGER REFERENCES receipts(id) ON DELETE CASCADE UNIQUE NOT NULL,
    priority        INTEGER DEFAULT 0,
    reason          TEXT NOT NULL,
    assigned_to     TEXT,
    status          TEXT CHECK (status IN ('pending', 'in_progress', 'completed'))
                    DEFAULT 'pending',
    flagged_at      TIMESTAMPTZ DEFAULT now(),
    started_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    resolution_notes TEXT,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_review_status ON receipt_review_queue(status);
CREATE INDEX idx_review_priority ON receipt_review_queue(priority DESC);


-- ============================================================================
-- SECTION 11: RECEIPT VIEWS
-- ============================================================================

-- Receipts enriched with project/vendor/category data
CREATE VIEW v_receipts_enriched AS
SELECT
    r.id,
    r.uuid,
    r.receipt_date,
    r.total_amount,
    r.status,
    r.needs_review,
    r.ocr_confidence,
    v.name_normalized   AS vendor_name,
    v.category          AS vendor_category,
    p.name              AS project_name,
    p.jt_job_id,
    p.jt_job_number,
    ec.name             AS category_name,
    r.image_path,
    r.upload_timestamp,
    r.notes,
    r.tags
FROM receipts r
LEFT JOIN vendors v ON r.vendor_id = v.id
LEFT JOIN projects p ON r.project_id = p.id
LEFT JOIN expense_categories ec ON r.category_id = ec.id;

-- Project expense summary (replaces old v_job_cost_summary)
CREATE VIEW v_project_expense_summary AS
SELECT
    p.id,
    p.name              AS project_name,
    p.jt_job_id,
    p.jt_job_number,
    p.total_price       AS estimated_price,
    COALESCE(SUM(r.total_amount), 0) AS actual_spend,
    p.total_price - COALESCE(SUM(r.total_amount), 0) AS remaining_budget,
    COUNT(r.id)         AS receipt_count,
    MAX(r.receipt_date) AS last_expense_date
FROM projects p
LEFT JOIN receipts r ON p.id = r.project_id AND r.status = 'completed'
GROUP BY p.id, p.name, p.jt_job_id, p.jt_job_number, p.total_price;

-- Receipts pending review
CREATE VIEW v_receipts_pending_review AS
SELECT
    rq.id           AS queue_id,
    rq.priority,
    rq.reason,
    rq.assigned_to,
    rq.flagged_at,
    r.id            AS receipt_id,
    r.uuid,
    r.receipt_date,
    r.vendor_raw,
    r.total_amount,
    r.ocr_confidence,
    r.image_path
FROM receipt_review_queue rq
JOIN receipts r ON rq.receipt_id = r.id
WHERE rq.status = 'pending'
ORDER BY rq.priority DESC, rq.flagged_at ASC;

-- Processing statistics
CREATE VIEW v_processing_stats AS
SELECT
    DATE(timestamp)     AS process_date,
    step,
    status,
    COUNT(*)            AS count,
    AVG(duration_ms)    AS avg_duration_ms,
    MAX(duration_ms)    AS max_duration_ms
FROM receipt_processing_log
GROUP BY DATE(timestamp), step, status
ORDER BY process_date DESC, step;


-- ============================================================================
-- SECTION 12: TRIGGERS (auto-update timestamps)
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_receipts_ts BEFORE UPDATE ON receipts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_vendors_ts BEFORE UPDATE ON vendors
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_receipt_items_ts BEFORE UPDATE ON receipt_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO business_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO business_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO business_user;

COMMIT;
