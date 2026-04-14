# Changelog

## 2026-03-19 - Session 2: Deployment

### Database
- Ran SQL migration: `001-estimates-table.sql`
- Created `estimates` table with all indexes in `hwc` database

### Configuration
- Generated API key: `T8SLQ1N8wxg9tlwRa8FG1p17ZDUj3w1NwBKVVwQVxWQ=`
- Added `ESTIMATOR_API_KEY` to n8n config in `profiles/monitoring.nix`
- Created `.env` file in heartwood-assembler with VITE_WEBHOOK_URL and VITE_API_KEY

### Build
- Built React app successfully (dist/ updated)

### Workflows Imported via MCP
- `08a` JT Data Provider → ID: `7JRWiYxyZeppoVE0`
- `08b` Estimate Router → ID: `jbIqSwVByVnEAk7e`

### Remaining
- NixOS rebuild needed to apply n8n config
- Import workflows to n8n UI
- Configure JobTread + Slack credentials in n8n
- Test endpoints

---

## 2026-03-19 - Session 1: Initial Implementation

### Created

**N8N Workflows**
- `08a-jt-data-provider.json` - JT customer/job data endpoints
  - GET `/webhook/jt-customers` with x-api-key auth
  - GET `/webhook/jt-jobs?customerId=X` with phase filtering (1-3 only)
  - GraphQL queries to JobTread API
  - Transforms data for dropdown consumption

- `08b-estimate-router.json` - Main estimate push workflow
  - POST `/webhook/estimate-push` with x-api-key auth
  - Validates payload and job selection
  - Creates new JT job if mode=new_job
  - Pushes budget line items via GraphQL mutation
  - Archives to Postgres (always, even on JT failure)
  - Notifies Slack #hwc-estimates with job link + totals
  - Returns structured JSON with success/failure details

**Database**
- `migrations/001-estimates-table.sql`
  - estimates table with job info, financials, project_state JSONB
  - Indexes on job_number, job_id, customer_id, project_type, created_at

**React Components**
- `src/components/JobSelector.jsx`
  - Customer dropdown (fetched from n8n)
  - Job dropdown (filtered by selected customer)
  - Mode toggle: existing job vs new job
  - New job inputs: job name, address
  - Project type selector
  - Config warning if API not set

### Modified

**State Model** (`src/hooks/useProjectState.js`)
- Added: mode, customerId, customerName, jobId, jobNumber, jobName, address, projectType
- Removed old context fields (customer, address, job_name) - replaced by new structure

**ScopeTab** (`src/components/ScopeTab.jsx`)
- Added JobSelector import
- Added JobSelector component at top spanning full width

**EstimateTab** (`src/components/EstimateTab.jsx`)
- Added API_KEY constant from env/localStorage
- Added canPush() validation (requires customer + job selection)
- Updated pushToWebhook() with:
  - x-api-key header
  - Full payload including mode, projectType, newJob, projectState
  - Better error handling and response parsing
- Added status messages for no-key, no-job states
- Added pushResult display with success/failure details
- Disabled push button when job not selected

**App.jsx**
- Passes state prop to EstimateTab

**Workflow README** (`workflows/README.md`)
- Added documentation for 08a and 08b workflows
- Added new credentials to requirements section
- Updated date
