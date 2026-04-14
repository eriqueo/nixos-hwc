-- ============================================================================
-- HEARTWOOD CRAFT — Full hwc Schema Deployment
-- All tables in the hwc schema
-- ============================================================================

-- Enable pgcrypto for gen_random_uuid() if needed
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS hwc;

-- ============================================================================
-- SECTION 1: JT REFERENCE TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS hwc.jt_cost_codes (
    id              TEXT PRIMARY KEY,
    code            TEXT NOT NULL,
    name            TEXT NOT NULL,
    display_name    TEXT NOT NULL,
    sort_order      INT DEFAULT 0
);

INSERT INTO hwc.jt_cost_codes (id, code, name, display_name, sort_order) VALUES
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
('22Nm3uGRAMmp', '3100', 'Miscellaneous',       '3100 Miscellaneous', 25)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS hwc.jt_cost_types (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    default_margin  NUMERIC(4,2) DEFAULT 0.50
);

INSERT INTO hwc.jt_cost_types (id, name, default_margin) VALUES
('22PJuNqewZmV', 'Admin',          0.50),
('22Nm3uGRAMmq', 'Labor',          0.50),
('22Nm3uGRAMmr', 'Materials',      0.50),
('22Nm3uGRAMmt', 'Other',          0.50),
('22PQ4KZExZjP', 'Selections',     0.30),
('22Nm3uGRAMms', 'Subcontractor',  0.30)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS hwc.jt_units (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL
);

INSERT INTO hwc.jt_units (id, name) VALUES
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
('22Nm3uGRAMmF', 'Tons')
ON CONFLICT (id) DO NOTHING;


-- ============================================================================
-- SECTION 2: COST CATALOG
-- ============================================================================

CREATE TABLE IF NOT EXISTS hwc.trade_rates (
    id              SERIAL PRIMARY KEY,
    trade           TEXT NOT NULL UNIQUE,
    base_wage       NUMERIC(8,2) NOT NULL,
    burden_factor   NUMERIC(4,2) NOT NULL,
    markup_factor   NUMERIC(4,2) NOT NULL,
    unit_cost       NUMERIC(8,2) GENERATED ALWAYS AS (base_wage * burden_factor) STORED,
    unit_price      NUMERIC(8,2) GENERATED ALWAYS AS (base_wage * burden_factor * markup_factor) STORED,
    updated_at      TIMESTAMPTZ DEFAULT now()
);

INSERT INTO hwc.trade_rates (trade, base_wage, burden_factor, markup_factor) VALUES
('demo',              35.00, 1.35, 2.00),
('framing',           35.00, 1.35, 2.00),
('plumbing',          35.00, 1.35, 2.00),
('tile',              35.00, 1.35, 2.00),
('drywall',           35.00, 1.35, 2.00),
('painting',          35.00, 1.35, 2.00),
('finish_carpentry',  35.00, 1.35, 2.00),
('electrical',        35.00, 1.35, 2.00)
ON CONFLICT (trade) DO NOTHING;

CREATE TABLE IF NOT EXISTS hwc.catalog_items (
    id                  SERIAL PRIMARY KEY,
    canonical_name      TEXT NOT NULL UNIQUE,
    display_name        TEXT NOT NULL,
    item_type           TEXT NOT NULL CHECK (item_type IN ('labor', 'material', 'allowance', 'other')),
    trade               TEXT REFERENCES hwc.trade_rates(trade),
    jt_cost_code_id     TEXT REFERENCES hwc.jt_cost_codes(id),
    jt_cost_type_id     TEXT REFERENCES hwc.jt_cost_types(id),
    jt_unit_id          TEXT REFERENCES hwc.jt_units(id),
    jt_org_cost_item_id TEXT,
    unit_cost           NUMERIC(10,2),
    unit_price          NUMERIC(10,2),
    budget_group_path   TEXT,
    condition_trigger   TEXT,
    qty_driver          TEXT,
    qty_formula         TEXT,
    default_qty         NUMERIC(10,2) DEFAULT 1,
    waste_factor        NUMERIC(4,2) DEFAULT 1.0,
    production_rate     NUMERIC(8,2),
    source              TEXT DEFAULT 'heartwood' CHECK (source IN ('heartwood', 'craftsman', 'custom')),
    description         TEXT,
    project_type        TEXT DEFAULT 'bathroom' CHECK (project_type IN ('bathroom', 'deck', 'kitchen', 'general')),
    is_active           BOOLEAN DEFAULT true,
    created_at          TIMESTAMPTZ DEFAULT now(),
    updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_catalog_project_type ON hwc.catalog_items(project_type) WHERE is_active;
CREATE INDEX IF NOT EXISTS idx_catalog_trade ON hwc.catalog_items(trade);


-- ============================================================================
-- SECTION 3: PROJECT STATE
-- ============================================================================

CREATE TABLE IF NOT EXISTS hwc.projects (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    jt_job_id       TEXT,
    jt_job_number   INT,
    jt_account_id   TEXT,
    project_type    TEXT NOT NULL DEFAULT 'bathroom'
                    CHECK (project_type IN ('bathroom', 'deck', 'kitchen')),
    name            TEXT,
    address         TEXT,
    source          TEXT NOT NULL DEFAULT 'assembler'
                    CHECK (source IN ('assembler', 'calculator', 'manual', 'import')),
    lead_channel    TEXT CHECK (lead_channel IN (
                    'lsa', 'gbp', 'referral', 'pm_outreach',
                    'website_form', 'website_calculator', 'social', 'other')),
    stage           TEXT DEFAULT 'lead'
                    CHECK (stage IN ('lead', 'qualified', 'visited', 'estimated',
                                     'proposed', 'signed', 'in_progress', 'complete', 'lost')),
    lost_reason     TEXT,
    total_cost      NUMERIC(12,2),
    total_price     NUMERIC(12,2),
    margin_pct      NUMERIC(5,2),
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now(),
    estimated_at    TIMESTAMPTZ,
    pushed_to_jt_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_projects_stage ON hwc.projects(stage);
CREATE INDEX IF NOT EXISTS idx_projects_jt_job ON hwc.projects(jt_job_id);

CREATE TABLE IF NOT EXISTS hwc.project_state (
    id              SERIAL PRIMARY KEY,
    project_id      UUID NOT NULL REFERENCES hwc.projects(id) ON DELETE CASCADE,
    key             TEXT NOT NULL,
    value           TEXT NOT NULL,
    value_type      TEXT NOT NULL DEFAULT 'text'
                    CHECK (value_type IN ('text', 'number', 'boolean', 'json')),
    category        TEXT NOT NULL DEFAULT 'measurement'
                    CHECK (category IN ('measurement', 'condition', 'count',
                                        'selection', 'constraint', 'derived')),
    UNIQUE (project_id, key)
);

CREATE INDEX IF NOT EXISTS idx_state_project ON hwc.project_state(project_id);
CREATE INDEX IF NOT EXISTS idx_state_key ON hwc.project_state(key);


-- ============================================================================
-- SECTION 4: ESTIMATES
-- ============================================================================

CREATE TABLE IF NOT EXISTS hwc.estimates (
    id              SERIAL PRIMARY KEY,
    project_id      UUID NOT NULL REFERENCES hwc.projects(id) ON DELETE CASCADE,
    version         INT NOT NULL DEFAULT 1,
    total_cost      NUMERIC(12,2),
    total_price     NUMERIC(12,2),
    margin_pct      NUMERIC(5,2),
    item_count      INT,
    line_items_json JSONB NOT NULL,
    state_snapshot  JSONB NOT NULL,
    assembled_by    TEXT DEFAULT 'assembler',
    pushed_to_jt    BOOLEAN DEFAULT false,
    jt_push_at      TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    UNIQUE (project_id, version)
);


-- ============================================================================
-- SECTION 5: CALCULATOR LEADS (from the public calculator)
-- ============================================================================

CREATE TABLE IF NOT EXISTS hwc.calculator_leads (
    id              SERIAL PRIMARY KEY,
    name            TEXT NOT NULL,
    email           TEXT,
    phone           TEXT NOT NULL,
    notes           TEXT,
    project_type    TEXT,
    bathroom_size   TEXT,
    shower_tub      TEXT,
    tile_level      TEXT,
    fixtures        TEXT,
    features        TEXT[],
    timeline        TEXT,
    estimate_low    NUMERIC(10,2),
    estimate_high   NUMERIC(10,2),
    status          TEXT DEFAULT 'new'
                    CHECK (status IN ('new', 'contacted', 'qualified', 'converted', 'dead')),
    project_id      UUID REFERENCES hwc.projects(id),
    jt_account_id   TEXT,
    source_url      TEXT,
    utm_source      TEXT,
    utm_medium      TEXT,
    utm_campaign    TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    contacted_at    TIMESTAMPTZ,
    converted_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_leads_status ON hwc.calculator_leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_created ON hwc.calculator_leads(created_at DESC);


-- ============================================================================
-- SECTION 5b: DAILY LOGS
-- ============================================================================

CREATE TABLE IF NOT EXISTS hwc.daily_logs (
    id              SERIAL PRIMARY KEY,
    jt_job_id       TEXT,
    jt_job_number   INT,
    log_date        DATE NOT NULL,
    logged_by       TEXT,
    weather         TEXT,
    crew_count      INT,
    hours_worked    NUMERIC(5,2),
    work_completed  TEXT,
    materials_used  TEXT,
    issues          TEXT,
    photos          TEXT[],
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_daily_logs_job ON hwc.daily_logs(jt_job_id);
CREATE INDEX IF NOT EXISTS idx_daily_logs_date ON hwc.daily_logs(log_date DESC);


-- ============================================================================
-- SECTION 6: N8N WORKFLOW LOG
-- ============================================================================

CREATE TABLE IF NOT EXISTS hwc.workflow_log (
    id              SERIAL PRIMARY KEY,
    workflow_name   TEXT NOT NULL,
    trigger_source  TEXT,
    project_id      UUID REFERENCES hwc.projects(id),
    lead_id         INT REFERENCES hwc.calculator_leads(id),
    action          TEXT NOT NULL,
    target_system   TEXT NOT NULL,
    request_payload JSONB,
    response_payload JSONB,
    success         BOOLEAN NOT NULL,
    error_message   TEXT,
    duration_ms     INT,
    created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_log_project ON hwc.workflow_log(project_id);
CREATE INDEX IF NOT EXISTS idx_log_created ON hwc.workflow_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_log_errors ON hwc.workflow_log(success) WHERE NOT success;
CREATE INDEX IF NOT EXISTS idx_workflow_log_name ON hwc.workflow_log(workflow_name);


-- ============================================================================
-- SECTION 7: VIEWS
-- ============================================================================

CREATE OR REPLACE VIEW hwc.pipeline_summary AS
SELECT stage, count(*) AS count,
       sum(total_price) AS total_value,
       avg(margin_pct) AS avg_margin
FROM hwc.projects
WHERE stage NOT IN ('lost', 'complete')
GROUP BY stage
ORDER BY array_position(
    ARRAY['lead','qualified','visited','estimated','proposed','signed','in_progress'],
    stage
);

CREATE OR REPLACE VIEW hwc.lead_funnel AS
SELECT
    date_trunc('month', created_at) AS month,
    count(*) AS total_leads,
    count(*) FILTER (WHERE status != 'dead') AS active,
    count(*) FILTER (WHERE status = 'contacted') AS contacted,
    count(*) FILTER (WHERE status = 'qualified') AS qualified,
    count(*) FILTER (WHERE status = 'converted') AS converted,
    round(100.0 * count(*) FILTER (WHERE status = 'converted') / nullif(count(*), 0), 1) AS conversion_pct
FROM hwc.calculator_leads
GROUP BY 1
ORDER BY 1 DESC;

CREATE OR REPLACE VIEW hwc.channel_roi AS
SELECT
    lead_channel,
    count(*) AS total_projects,
    count(*) FILTER (WHERE stage = 'complete') AS completed,
    sum(total_price) FILTER (WHERE stage = 'complete') AS revenue,
    avg(margin_pct) FILTER (WHERE stage = 'complete') AS avg_margin
FROM hwc.projects
WHERE lead_channel IS NOT NULL
GROUP BY lead_channel
ORDER BY revenue DESC NULLS LAST;

CREATE OR REPLACE VIEW hwc.v_pipeline_summary AS
SELECT
    stage AS pipeline_stage,
    COUNT(*) as count,
    SUM(CASE WHEN stage NOT IN ('lost','complete') THEN 1 ELSE 0 END) as active
FROM hwc.projects
GROUP BY stage
ORDER BY stage;

CREATE OR REPLACE VIEW hwc.v_calculator_leads AS
SELECT
    date_trunc('week', created_at) as week,
    COUNT(*) as leads,
    COUNT(project_id) as converted
FROM hwc.calculator_leads
GROUP BY week
ORDER BY week DESC;
