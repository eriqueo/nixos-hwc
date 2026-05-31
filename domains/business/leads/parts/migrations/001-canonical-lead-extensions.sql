-- domains/business/leads/parts/migrations/001-canonical-lead-extensions.sql
--
-- Creates hwc.leads — the source-agnostic canonical Lead table for the
-- Phase 2 hwc-leads service. The existing hwc.calculator_leads is
-- LEFT UNTOUCHED — its 21 historical rows + the (about-to-be-retired)
-- n8n workflow continue to write/read there. Phase 2.6 cutover will
-- decide whether to backfill / view-link / archive it.
--
-- Why a new table:
--   - calculator_leads has 9 NOT NULL columns specific to bathroom
--     calculator submissions (report_id, calculator, estimate_low/high,
--     project_state, contact_phone, ...). A contact-form lead can't
--     fit that schema without relaxing 7 constraints, and an
--     appointment-form lead has different required fields again.
--   - The clean answer is a discriminated-union table keyed on source:
--     every Lead has id+source+status+payload+contact_*; per-source
--     fields live in the payload JSONB.
--
-- Idempotent — CREATE * IF NOT EXISTS throughout.
--
-- Applied 2026-05-31 via:
--   psql -d hwc -f /path/to/this.sql
-- (as eric — peer-auth via local socket; eric owns the hwc DB.)

BEGIN;

CREATE TABLE IF NOT EXISTS hwc.leads (
  -- Server-generated UUID. ON CONFLICT (id) for idempotent retries.
  id              UUID PRIMARY KEY,

  source          TEXT NOT NULL
                  CHECK (source IN ('contact', 'calculator', 'appointment')),

  status          TEXT NOT NULL
                  CHECK (status IN ('received', 'validated', 'pending_jt',
                                    'complete', 'failed')),

  -- Full LeadInput payload. Sole source of truth for per-source fields
  -- (calculator selections + estimate, appointment date/time, etc.).
  payload         JSONB NOT NULL,

  received_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Denormalised contact fields for cheap filtering / sorting / display.
  -- Always populated; the payload's contact block is the canonical copy.
  contact_name    TEXT NOT NULL,
  contact_email   TEXT NOT NULL,
  contact_phone   TEXT,
  contact_notes   TEXT,

  -- JT graph references. Populated by Phase 2.4 NotifyAdapter after
  -- successful account → location → contact → job creation.
  jt_account_id   TEXT,
  jt_location_id  TEXT,
  jt_contact_id   TEXT,
  jt_job_id       TEXT,

  -- Pipeline timestamps. Each downstream side-effect sets its own.
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  jt_synced_at    TIMESTAMPTZ,
  notify_sent_at  TIMESTAMPTZ,
  email_sent_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_leads_received   ON hwc.leads(received_at DESC);
CREATE INDEX IF NOT EXISTS idx_leads_source     ON hwc.leads(source);
CREATE INDEX IF NOT EXISTS idx_leads_status     ON hwc.leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_jt_account ON hwc.leads(jt_account_id);
CREATE INDEX IF NOT EXISTS idx_leads_email      ON hwc.leads(contact_email);

COMMENT ON TABLE  hwc.leads IS
  'Canonical Lead records from the Phase 2 hwc-leads service. '
  'Source-agnostic: contact / calculator / appointment all live here, '
  'with per-source fields in payload JSONB. Existing hwc.calculator_leads '
  'is preserved for the 21 historical rows + n8n workflow until Phase 2.6 cutover.';
COMMENT ON COLUMN hwc.leads.payload IS
  'Full validated LeadInput from POST /leads. Schema: '
  'parts/src/src/schemas/lead.ts (Zod).';
COMMENT ON COLUMN hwc.leads.received_at IS
  'When hwc-leads validated the lead. Distinct from created_at which '
  'is whenever this row was inserted into the DB.';

COMMIT;
