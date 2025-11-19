-- Receipts OCR Pipeline Database Schema
-- PostgreSQL 15+
--
-- Purpose: Store receipts, OCR data, and business intelligence for remodeling business
-- Dependencies: PostgreSQL with pgcrypto extension for UUID generation

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- CORE TABLES
-- ============================================================================

-- Jobs table (remodeling business projects)
CREATE TABLE IF NOT EXISTS jobs (
    id SERIAL PRIMARY KEY,
    job_number TEXT UNIQUE NOT NULL,
    job_name TEXT NOT NULL,
    client_name TEXT,
    client_contact TEXT,
    start_date DATE,
    end_date DATE,
    estimated_completion DATE,
    status TEXT CHECK (status IN ('quoted', 'approved', 'in_progress', 'completed', 'cancelled')) DEFAULT 'quoted',
    budget NUMERIC(12,2),
    actual_cost NUMERIC(12,2) DEFAULT 0,
    margin_percent NUMERIC(5,2),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Vendors table
CREATE TABLE IF NOT EXISTS vendors (
    id SERIAL PRIMARY KEY,
    name_normalized TEXT UNIQUE NOT NULL,
    name_variants TEXT[] DEFAULT '{}',
    category TEXT,
    tax_id TEXT,
    account_number TEXT,
    contact_name TEXT,
    contact_email TEXT,
    contact_phone TEXT,
    address TEXT,
    payment_terms TEXT,
    preferred BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Expense categories
CREATE TABLE IF NOT EXISTS expense_categories (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    parent_category_id INTEGER REFERENCES expense_categories(id),
    tax_deductible BOOLEAN DEFAULT TRUE,
    billable_to_client BOOLEAN DEFAULT TRUE,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Receipts table (main OCR data)
CREATE TABLE IF NOT EXISTS receipts (
    id SERIAL PRIMARY KEY,
    uuid UUID DEFAULT gen_random_uuid() UNIQUE NOT NULL,

    -- File information
    image_path TEXT NOT NULL,
    image_filename TEXT NOT NULL,
    file_size_bytes INTEGER,
    file_hash TEXT,
    mime_type TEXT,

    -- Timestamps
    upload_timestamp TIMESTAMPTZ DEFAULT NOW(),
    process_start_timestamp TIMESTAMPTZ,
    process_end_timestamp TIMESTAMPTZ,

    -- Processing status
    status TEXT CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'review_needed', 'archived')) DEFAULT 'pending',

    -- OCR extracted data
    receipt_date DATE,
    receipt_time TIME,
    vendor_raw TEXT,
    vendor_normalized TEXT,
    vendor_id INTEGER REFERENCES vendors(id),

    -- Financial data
    subtotal NUMERIC(10,2),
    tax_amount NUMERIC(10,2),
    tip_amount NUMERIC(10,2),
    discount_amount NUMERIC(10,2),
    total_amount NUMERIC(10,2) NOT NULL,
    currency TEXT DEFAULT 'USD',

    -- Business context
    job_id INTEGER REFERENCES jobs(id),
    category_id INTEGER REFERENCES expense_categories(id),
    payment_method TEXT CHECK (payment_method IN ('cash', 'credit_card', 'debit_card', 'check', 'wire_transfer', 'other')),
    payment_reference TEXT,

    -- Review and validation
    ocr_confidence NUMERIC(3,2) CHECK (ocr_confidence BETWEEN 0 AND 1),
    needs_review BOOLEAN DEFAULT FALSE,
    review_reason TEXT,
    reviewed_by TEXT,
    reviewed_at TIMESTAMPTZ,

    -- Raw data preservation
    ocr_raw_text TEXT,
    ocr_raw_json JSONB,
    llm_metadata JSONB,

    -- Audit fields
    notes TEXT,
    tags TEXT[],
    created_by TEXT DEFAULT 'system',
    updated_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Receipt line items
CREATE TABLE IF NOT EXISTS receipt_items (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER REFERENCES receipts(id) ON DELETE CASCADE NOT NULL,

    -- Item details
    line_number INTEGER,
    description TEXT NOT NULL,
    quantity NUMERIC(10,3) DEFAULT 1,
    unit_price NUMERIC(10,2),
    total_price NUMERIC(10,2) NOT NULL,

    -- Categorization
    category_id INTEGER REFERENCES expense_categories(id),
    sku TEXT,
    upc TEXT,

    -- Tax information
    tax_rate NUMERIC(5,4),
    taxable BOOLEAN DEFAULT TRUE,

    -- Job allocation (for splitting items across jobs)
    job_id INTEGER REFERENCES jobs(id),
    billable BOOLEAN DEFAULT TRUE,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE(receipt_id, line_number)
);

-- Processing audit log
CREATE TABLE IF NOT EXISTS receipt_processing_log (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER REFERENCES receipts(id) ON DELETE CASCADE,

    timestamp TIMESTAMPTZ DEFAULT NOW(),
    step TEXT NOT NULL CHECK (step IN (
        'upload', 'validation', 'preprocessing', 'ocr', 'llm_normalization',
        'extraction', 'database_insert', 'review', 'failure', 'retry'
    )),
    status TEXT NOT NULL CHECK (status IN ('started', 'success', 'failed', 'skipped')),

    duration_ms INTEGER,
    error_message TEXT,
    error_stack TEXT,
    metadata JSONB,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Review queue
CREATE TABLE IF NOT EXISTS receipt_review_queue (
    id SERIAL PRIMARY KEY,
    receipt_id INTEGER REFERENCES receipts(id) ON DELETE CASCADE UNIQUE NOT NULL,

    priority INTEGER DEFAULT 0,
    reason TEXT NOT NULL,
    assigned_to TEXT,
    status TEXT CHECK (status IN ('pending', 'in_progress', 'completed')) DEFAULT 'pending',

    flagged_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    resolution_notes TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- Receipts indexes
CREATE INDEX idx_receipts_status ON receipts(status);
CREATE INDEX idx_receipts_upload_timestamp ON receipts(upload_timestamp);
CREATE INDEX idx_receipts_receipt_date ON receipts(receipt_date);
CREATE INDEX idx_receipts_job_id ON receipts(job_id);
CREATE INDEX idx_receipts_vendor_id ON receipts(vendor_id);
CREATE INDEX idx_receipts_needs_review ON receipts(needs_review) WHERE needs_review = TRUE;
CREATE INDEX idx_receipts_uuid ON receipts(uuid);
CREATE INDEX idx_receipts_file_hash ON receipts(file_hash);

-- Receipt items indexes
CREATE INDEX idx_receipt_items_receipt_id ON receipt_items(receipt_id);
CREATE INDEX idx_receipt_items_job_id ON receipt_items(job_id);
CREATE INDEX idx_receipt_items_category_id ON receipt_items(category_id);

-- Processing log indexes
CREATE INDEX idx_processing_log_receipt_id ON receipt_processing_log(receipt_id);
CREATE INDEX idx_processing_log_timestamp ON receipt_processing_log(timestamp);
CREATE INDEX idx_processing_log_status ON receipt_processing_log(status);

-- Review queue indexes
CREATE INDEX idx_review_queue_status ON receipt_review_queue(status);
CREATE INDEX idx_review_queue_priority ON receipt_review_queue(priority DESC);
CREATE INDEX idx_review_queue_assigned_to ON receipt_review_queue(assigned_to);

-- Jobs indexes
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_start_date ON jobs(start_date);
CREATE INDEX idx_jobs_job_number ON jobs(job_number);

-- Vendors indexes
CREATE INDEX idx_vendors_name_normalized ON vendors(name_normalized);
CREATE INDEX idx_vendors_category ON vendors(category);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_receipts_updated_at BEFORE UPDATE ON receipts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_jobs_updated_at BEFORE UPDATE ON jobs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_vendors_updated_at BEFORE UPDATE ON vendors
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_receipt_items_updated_at BEFORE UPDATE ON receipt_items
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Auto-calculate job actual cost from receipts
CREATE OR REPLACE FUNCTION update_job_actual_cost()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE jobs
    SET actual_cost = (
        SELECT COALESCE(SUM(total_amount), 0)
        FROM receipts
        WHERE job_id = COALESCE(NEW.job_id, OLD.job_id)
        AND status = 'completed'
    )
    WHERE id = COALESCE(NEW.job_id, OLD.job_id);
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_job_cost_on_receipt_insert AFTER INSERT ON receipts
    FOR EACH ROW EXECUTE FUNCTION update_job_actual_cost();

CREATE TRIGGER update_job_cost_on_receipt_update AFTER UPDATE ON receipts
    FOR EACH ROW EXECUTE FUNCTION update_job_actual_cost();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View: Receipts with enriched data
CREATE OR REPLACE VIEW v_receipts_enriched AS
SELECT
    r.id,
    r.uuid,
    r.receipt_date,
    r.total_amount,
    r.status,
    r.needs_review,
    r.ocr_confidence,
    v.name_normalized AS vendor_name,
    v.category AS vendor_category,
    j.job_number,
    j.job_name,
    ec.name AS category_name,
    r.image_path,
    r.upload_timestamp,
    r.notes,
    r.tags
FROM receipts r
LEFT JOIN vendors v ON r.vendor_id = v.id
LEFT JOIN jobs j ON r.job_id = j.id
LEFT JOIN expense_categories ec ON r.category_id = ec.id;

-- View: Job cost summary
CREATE OR REPLACE VIEW v_job_cost_summary AS
SELECT
    j.id,
    j.job_number,
    j.job_name,
    j.budget,
    j.actual_cost,
    j.budget - j.actual_cost AS remaining_budget,
    CASE
        WHEN j.budget > 0 THEN ((j.actual_cost / j.budget) * 100)::NUMERIC(5,2)
        ELSE 0
    END AS budget_used_percent,
    COUNT(r.id) AS receipt_count,
    MAX(r.receipt_date) AS last_expense_date
FROM jobs j
LEFT JOIN receipts r ON j.id = r.job_id AND r.status = 'completed'
GROUP BY j.id, j.job_number, j.job_name, j.budget, j.actual_cost;

-- View: Receipts pending review
CREATE OR REPLACE VIEW v_receipts_pending_review AS
SELECT
    rq.id AS queue_id,
    rq.priority,
    rq.reason,
    rq.assigned_to,
    rq.flagged_at,
    r.id AS receipt_id,
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

-- View: Processing statistics
CREATE OR REPLACE VIEW v_processing_stats AS
SELECT
    DATE(timestamp) AS process_date,
    step,
    status,
    COUNT(*) AS count,
    AVG(duration_ms) AS avg_duration_ms,
    MAX(duration_ms) AS max_duration_ms
FROM receipt_processing_log
GROUP BY DATE(timestamp), step, status
ORDER BY process_date DESC, step;

-- ============================================================================
-- SEED DATA
-- ============================================================================

-- Default expense categories
INSERT INTO expense_categories (name, parent_category_id, tax_deductible, billable_to_client) VALUES
    ('Materials', NULL, TRUE, TRUE),
    ('Labor', NULL, TRUE, TRUE),
    ('Tools', NULL, TRUE, FALSE),
    ('Office Supplies', NULL, TRUE, FALSE),
    ('Fuel', NULL, TRUE, FALSE),
    ('Permits & Fees', NULL, TRUE, TRUE),
    ('Subcontractors', NULL, TRUE, TRUE)
ON CONFLICT (name) DO NOTHING;

-- Insert materials subcategories
INSERT INTO expense_categories (name, parent_category_id, tax_deductible, billable_to_client)
SELECT 'Lumber', id, TRUE, TRUE FROM expense_categories WHERE name = 'Materials'
ON CONFLICT (name) DO NOTHING;

INSERT INTO expense_categories (name, parent_category_id, tax_deductible, billable_to_client)
SELECT 'Hardware', id, TRUE, TRUE FROM expense_categories WHERE name = 'Materials'
ON CONFLICT (name) DO NOTHING;

INSERT INTO expense_categories (name, parent_category_id, tax_deductible, billable_to_client)
SELECT 'Paint & Finishing', id, TRUE, TRUE FROM expense_categories WHERE name = 'Materials'
ON CONFLICT (name) DO NOTHING;

INSERT INTO expense_categories (name, parent_category_id, tax_deductible, billable_to_client)
SELECT 'Electrical', id, TRUE, TRUE FROM expense_categories WHERE name = 'Materials'
ON CONFLICT (name) DO NOTHING;

INSERT INTO expense_categories (name, parent_category_id, tax_deductible, billable_to_client)
SELECT 'Plumbing', id, TRUE, TRUE FROM expense_categories WHERE name = 'Materials'
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- GRANTS (adjust for your user)
-- ============================================================================

-- Grant permissions to business_user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO business_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO business_user;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO business_user;
