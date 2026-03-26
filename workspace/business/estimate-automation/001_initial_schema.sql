-- Bathroom Remodel Planner - Initial Schema
-- MVP: Local-only, deterministic cost engine, config-driven

-- ============================================================================
-- CLIENTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Contact info
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),

    -- Lead tracking (vetting)
    lead_source VARCHAR(50) DEFAULT 'website_tool',
    lead_score INTEGER DEFAULT 0,

    -- Future: JobTread sync
    jobtread_account_id VARCHAR(50),
    synced_to_jobtread_at TIMESTAMP WITH TIME ZONE,

    -- Flexible metadata
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_clients_email ON clients(email);
CREATE INDEX idx_clients_jobtread_id ON clients(jobtread_account_id);

-- ============================================================================
-- PROJECTS
-- ============================================================================
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Project type (bathroom only for MVP)
    project_type VARCHAR(50) NOT NULL DEFAULT 'bathroom',
    status VARCHAR(50) DEFAULT 'inquiry', -- inquiry, qualified, converted, archived

    -- Bathroom-specific fields (from question tree)
    bathroom_type VARCHAR(50), -- primary, kids, powder, guest, other
    size_sqft INTEGER,
    size_sqft_band VARCHAR(20), -- 0_35, 35_60, 60_90, 90_plus

    -- Budget & timeline (vetting signals)
    budget_band VARCHAR(50), -- under_15k, 15_to_30k, 30_to_50k, 50k_plus, not_sure
    timeline_readiness VARCHAR(50), -- just_exploring, 3_to_6_months, 6_to_12_months, ready_asap

    -- Calculated estimates
    estimated_total_min DECIMAL(10, 2),
    estimated_total_max DECIMAL(10, 2),
    estimated_labor_min DECIMAL(10, 2),
    estimated_labor_max DECIMAL(10, 2),
    estimated_materials_min DECIMAL(10, 2),
    estimated_materials_max DECIMAL(10, 2),

    -- Complexity scoring
    complexity_score INTEGER DEFAULT 0,
    complexity_band VARCHAR(20), -- low, medium, high

    -- PDF generation
    pdf_generated_at TIMESTAMP WITH TIME ZONE,
    pdf_url TEXT,

    -- Future: JobTread sync
    jobtread_job_id VARCHAR(50),
    jobtread_location_id VARCHAR(50),
    synced_to_jobtread_at TIMESTAMP WITH TIME ZONE,

    -- Flexible metadata
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_projects_client_id ON projects(client_id);
CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_projects_project_type ON projects(project_type);
CREATE INDEX idx_projects_created_at ON projects(created_at DESC);

-- ============================================================================
-- PROJECT ANSWERS (Generic key-value store for all question responses)
-- ============================================================================
CREATE TABLE IF NOT EXISTS project_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Question key (matches config file)
    question_key VARCHAR(100) NOT NULL,

    -- Answer value (supports strings, arrays, objects)
    value_json JSONB NOT NULL,

    UNIQUE(project_id, question_key)
);

CREATE INDEX idx_project_answers_project_id ON project_answers(project_id);
CREATE INDEX idx_project_answers_question_key ON project_answers(question_key);
CREATE INDEX idx_project_answers_value_json ON project_answers USING GIN(value_json);

-- ============================================================================
-- PROJECT COST ITEMS (Per-module cost breakdown)
-- ============================================================================
CREATE TABLE IF NOT EXISTS project_cost_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Module identification
    module_key VARCHAR(100) NOT NULL, -- e.g., tub_to_shower, wall_tile_replacement
    label VARCHAR(255) NOT NULL, -- Human-readable label for frontend

    -- Cost breakdown
    labor_min DECIMAL(10, 2) DEFAULT 0,
    labor_max DECIMAL(10, 2) DEFAULT 0,
    materials_min DECIMAL(10, 2) DEFAULT 0,
    materials_max DECIMAL(10, 2) DEFAULT 0,
    total_min DECIMAL(10, 2) DEFAULT 0,
    total_max DECIMAL(10, 2) DEFAULT 0,

    -- Metadata (which rules contributed, etc.)
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_project_cost_items_project_id ON project_cost_items(project_id);
CREATE INDEX idx_project_cost_items_module_key ON project_cost_items(module_key);

-- ============================================================================
-- COST RULES (The pricing engine - modular and updateable)
-- ============================================================================
CREATE TABLE IF NOT EXISTS cost_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Engine + module organization
    engine VARCHAR(50) NOT NULL, -- bathroom, kitchen (future)
    module_key VARCHAR(100) NOT NULL, -- tub_to_shower, wall_tile_replacement, etc.
    rule_key VARCHAR(100) NOT NULL, -- demo_base, tile_labor, glass_door, etc.

    -- Conditional logic (when does this rule apply?)
    applies_when JSONB DEFAULT '{}'::jsonb, -- e.g., {"goals_contains": "convert_tub_to_shower"}

    -- Cost components
    base_cost_min DECIMAL(10, 2) DEFAULT 0,
    base_cost_max DECIMAL(10, 2) DEFAULT 0,
    cost_per_sqft_min DECIMAL(10, 2) DEFAULT 0,
    cost_per_sqft_max DECIMAL(10, 2) DEFAULT 0,

    -- Labor/material split
    labor_fraction DECIMAL(3, 2) DEFAULT 0.60, -- e.g., 0.60 = 60% labor, 40% materials

    -- Complexity contribution
    complexity_points INTEGER DEFAULT 0,

    -- Documentation
    notes TEXT,
    active BOOLEAN DEFAULT true,

    UNIQUE(engine, module_key, rule_key)
);

CREATE INDEX idx_cost_rules_engine ON cost_rules(engine);
CREATE INDEX idx_cost_rules_module_key ON cost_rules(module_key);
CREATE INDEX idx_cost_rules_active ON cost_rules(active);
CREATE INDEX idx_cost_rules_applies_when ON cost_rules USING GIN(applies_when);

-- ============================================================================
-- PROJECT ANALYSIS (Future: LLM-generated insights)
-- ============================================================================
CREATE TABLE IF NOT EXISTS project_analysis (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Analysis type
    analysis_type VARCHAR(50) NOT NULL, -- builder, designer, risk_assessment, etc.

    -- Generated content
    content TEXT NOT NULL,

    -- Metadata (model used, prompt version, etc.)
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_project_analysis_project_id ON project_analysis(project_id);
CREATE INDEX idx_project_analysis_type ON project_analysis(analysis_type);

-- ============================================================================
-- TOOL SESSIONS (Future: Analytics for user journey)
-- ============================================================================
CREATE TABLE IF NOT EXISTS tool_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Engagement metrics
    steps_completed INTEGER DEFAULT 0,
    time_spent_seconds INTEGER,
    abandoned BOOLEAN DEFAULT false,

    -- Device/browser info
    user_agent TEXT,
    referrer TEXT,

    -- Metadata
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX idx_tool_sessions_project_id ON tool_sessions(project_id);
CREATE INDEX idx_tool_sessions_started_at ON tool_sessions(started_at DESC);

-- ============================================================================
-- TRIGGERS (Auto-update timestamps)
-- ============================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_clients_updated_at BEFORE UPDATE ON clients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_projects_updated_at BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_cost_rules_updated_at BEFORE UPDATE ON cost_rules
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- COMMENTS (Documentation for future maintainers)
-- ============================================================================
COMMENT ON TABLE clients IS 'Homeowners who submit project inquiries';
COMMENT ON TABLE projects IS 'Individual remodel projects (bathroom, kitchen, etc.)';
COMMENT ON TABLE project_answers IS 'Generic key-value store for all question responses';
COMMENT ON TABLE project_cost_items IS 'Per-module cost breakdown for project estimates';
COMMENT ON TABLE cost_rules IS 'Modular pricing rules - update these to change cost calculations';
COMMENT ON TABLE project_analysis IS 'LLM-generated insights (builder/designer analysis)';
COMMENT ON TABLE tool_sessions IS 'User engagement analytics';

COMMENT ON COLUMN cost_rules.applies_when IS 'JSONB condition for when rule applies. Examples: {"goals_contains": "convert_tub_to_shower"}, {"tile_level": "natural_stone"}';
COMMENT ON COLUMN cost_rules.labor_fraction IS 'Fraction of total cost that is labor (e.g., 0.60 = 60% labor, 40% materials)';
