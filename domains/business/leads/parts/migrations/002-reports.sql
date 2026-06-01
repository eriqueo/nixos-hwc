-- domains/business/leads/parts/migrations/002-reports.sql
--
-- Phase 4.1: hwc.reports table.
--
-- A Report is the customer-facing artifact of a calculator submission —
-- a sanitised view of the lead payload + estimate that the customer can
-- come back to at https://iheartwoodcraft.com/report/<id>. Today reports
-- exist only as URLs in confirmation emails; this table makes them
-- first-class objects with explicit storage, view tracking, and revoke
-- capability.
--
-- Why a separate table (not a JSONB column on hwc.leads):
--   - report_id is the public path-style URL identifier; lead.id is
--     internal. Different lifecycle, different access controls.
--   - A lead with no calculator stage (contact form) has no report;
--     a calculator lead might have multiple reports if the customer
--     re-runs the calculator with tweaked inputs (future use case).
--   - View tracking (viewed_at[]) and revoke (revoked_at) belong to the
--     report, not the lead.
--   - Phase 4.3's GET /api/reports/<id> can serve from a focused index
--     without joining the full hwc.leads row on every request.
--
-- The hwc-leads POST /leads handler writes the lead and (when source=
-- 'calculator' and the payload carries a reportId) the report row in
-- the SAME transaction. Both succeed or both roll back — no orphan
-- reports.
--
-- Idempotent — CREATE * IF NOT EXISTS throughout.
--
-- Applied via:
--   psql -d hwc -f /path/to/this.sql
-- (as eric — peer-auth via local socket; eric owns the hwc DB.)

BEGIN;

CREATE TABLE IF NOT EXISTS hwc.reports (
  -- Public URL identifier — short kebab-y string the calc generates
  -- client-side ("ynq8jv5a" etc.). 8-char [a-z0-9] today; the column
  -- is permissive so a future format change doesn't need a migration.
  report_id       TEXT PRIMARY KEY,

  -- FK to the lead that produced this report. ON DELETE CASCADE so
  -- archiving a lead during data-retention cleanup tidies the report
  -- too. NOT NULL — every report belongs to exactly one lead.
  lead_id         UUID NOT NULL REFERENCES hwc.leads(id) ON DELETE CASCADE,

  -- Sanitised payload the report viewer renders. Subset of the lead's
  -- payload — excludes contact PII beyond first name, excludes the
  -- HMAC-relevant raw bytes, excludes attribution. Shape matches the
  -- ReportPayload schema in parts/src/src/schemas/report.ts (Phase
  -- 4.2 lands the schema).
  payload         JSONB NOT NULL,

  -- Which template the viewer should render with (today there's one;
  -- this leaves room for per-calculator-kind layouts without a column
  -- add later).
  template_id     TEXT NOT NULL DEFAULT 'v1-generic',

  -- Append-only view log. Each entry is an ISO-8601 timestamp; the
  -- length of this array is the view count. Array beats a separate
  -- table at our volume (a handful of views per report) and keeps the
  -- read path single-row.
  viewed_at       TIMESTAMPTZ[] NOT NULL DEFAULT '{}',

  -- Soft delete. Set by an operator action (future MCP `revoke`).
  -- Phase 4.3's GET /api/reports/<id> returns 410 Gone when this is
  -- set.
  revoked_at      TIMESTAMPTZ,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Lookups by lead id (operator views, audit joins).
CREATE INDEX IF NOT EXISTS idx_reports_lead_id    ON hwc.reports(lead_id);
-- Recency listing for the operator dashboard / MCP.
CREATE INDEX IF NOT EXISTS idx_reports_created    ON hwc.reports(created_at DESC);
-- Partial index — only the live reports are interesting for the public
-- API read path. Postgres can satisfy GET /api/reports/<id> with this
-- index without touching revoked rows.
CREATE INDEX IF NOT EXISTS idx_reports_live
  ON hwc.reports(report_id)
  WHERE revoked_at IS NULL;

COMMENT ON TABLE  hwc.reports IS
  'Customer-facing report artifacts produced by calculator lead '
  'submissions. Keyed by the public report_id used in URL '
  'https://iheartwoodcraft.com/report/<id>. Written in the same '
  'transaction as the originating hwc.leads row.';

COMMENT ON COLUMN hwc.reports.report_id IS
  'Public URL slug. Generated client-side by the calculator; 8-char '
  '[a-z0-9] today. Column is TEXT to keep future format changes from '
  'requiring a migration.';

COMMENT ON COLUMN hwc.reports.payload IS
  'Sanitised view of the lead payload — calc selections + estimate, '
  'no PII beyond first name. Shape: ReportPayload schema in '
  'parts/src/src/schemas/report.ts.';

COMMENT ON COLUMN hwc.reports.viewed_at IS
  'Append-only ISO-8601 timestamp array. Length = total view count. '
  'GET /api/reports/<id> appends a new entry per uncached fetch.';

COMMENT ON COLUMN hwc.reports.revoked_at IS
  'Soft delete. When set, GET /api/reports/<id> returns 410 Gone. '
  'Operator action via future MCP `revoke`.';

COMMIT;
