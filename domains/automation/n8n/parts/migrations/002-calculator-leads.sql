-- Calculator leads table for the Heartwood bathroom cost calculator
-- Created: 2026-03-26
-- Purpose: Archive every lead from the website calculator for pipeline tracking
--
-- Design decisions:
--   - Lives in hwc schema (separate from public) to keep business data namespaced
--   - features stored as TEXT (comma-separated) for simplest n8n compatibility
--   - jt_account_id + jt_job_id stored for direct JT deep-links
--   - source column distinguishes calculator vs future intake channels

CREATE SCHEMA IF NOT EXISTS hwc;

CREATE TABLE IF NOT EXISTS hwc.calculator_leads (
    id              SERIAL PRIMARY KEY,

    -- Contact info (gated behind the calculator form)
    name            TEXT NOT NULL,
    email           TEXT,
    phone           TEXT NOT NULL,
    notes           TEXT,

    -- Project state captured from calculator toggles
    project_type    TEXT,          -- 'full_gut', 'refresh', etc.
    bathroom_size   TEXT,          -- 'small', 'medium', 'large', 'xl'
    shower_tub      TEXT,          -- 'shower_only', 'tub_shower', etc.
    tile_level      TEXT,          -- 'basic', 'mid', 'high'
    fixtures        TEXT,          -- 'standard', 'upgraded', 'premium'
    features        TEXT,          -- comma-separated: 'heated_floor,niches'
    timeline        TEXT,          -- 'asap', '1_3_months', '3_6_months', 'flexible'

    -- Estimate range shown to the visitor
    estimate_low    NUMERIC(10,2),
    estimate_high   NUMERIC(10,2),

    -- Attribution
    source          TEXT DEFAULT 'website_calculator',

    -- JT references (populated by n8n after account/job creation)
    jt_account_id   TEXT,
    jt_job_id       TEXT,

    -- Pipeline status
    status          TEXT DEFAULT 'new'
                    CHECK (status IN ('new', 'contacted', 'qualified', 'converted', 'dead')),

    -- Timestamps
    created_at      TIMESTAMPTZ DEFAULT now(),
    contacted_at    TIMESTAMPTZ,
    converted_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_calc_leads_status     ON hwc.calculator_leads(status);
CREATE INDEX IF NOT EXISTS idx_calc_leads_created    ON hwc.calculator_leads(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_calc_leads_jt_account ON hwc.calculator_leads(jt_account_id);

COMMENT ON TABLE hwc.calculator_leads IS
    'Leads captured from the Heartwood website bathroom cost calculator. '
    'Archived by the work_calculator_lead n8n workflow after JT account creation.';
