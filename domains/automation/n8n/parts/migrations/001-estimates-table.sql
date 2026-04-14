-- Estimates table for Heartwood Estimator → JobTread integration
-- Created: 2026-03-19
-- Purpose: Archive estimate history + project state for change order tracking

CREATE TABLE IF NOT EXISTS estimates (
    id SERIAL PRIMARY KEY,

    -- Job identification
    job_number VARCHAR(50),
    job_id VARCHAR(50),           -- JT job UUID
    job_name VARCHAR(255),
    customer_name VARCHAR(255),
    customer_id VARCHAR(50),      -- JT account UUID
    project_type VARCHAR(50),     -- bathroom, deck, kitchen, general

    -- Financials
    total_cost DECIMAL(12,2),
    total_price DECIMAL(12,2),
    margin_percent DECIMAL(5,2),
    labor_hours DECIMAL(8,2),
    item_count INTEGER,

    -- Full data for replay/change orders
    project_state JSONB,          -- Toggle inputs, measurements, selections
    jt_payload JSONB,             -- JT-formatted line items

    -- Status tracking
    created_at TIMESTAMP DEFAULT NOW(),
    pushed_to_jt BOOLEAN DEFAULT FALSE,
    jt_push_error TEXT,           -- Error message if push failed
    jt_push_result JSONB          -- Success response from JT
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_estimates_job_number ON estimates(job_number);
CREATE INDEX IF NOT EXISTS idx_estimates_job_id ON estimates(job_id);
CREATE INDEX IF NOT EXISTS idx_estimates_customer_id ON estimates(customer_id);
CREATE INDEX IF NOT EXISTS idx_estimates_project_type ON estimates(project_type);
CREATE INDEX IF NOT EXISTS idx_estimates_created_at ON estimates(created_at);

-- Comment on table
COMMENT ON TABLE estimates IS 'Heartwood estimator archive - stores estimate history for change order tracking';
