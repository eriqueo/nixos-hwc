-- Calendar logger schema v1: additive/nullable for existing readers and rows.
-- CRITICAL: workflow history follows the existing hwc PostgreSQL Borg backup.
-- 001 owns estimates; 002 owns the hwc schema. Neither owns this public logger.
ALTER TABLE public.workflow_runs ADD COLUMN IF NOT EXISTS metadata jsonb;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.workflow_runs'::regclass
          AND attname = 'metadata' AND atttypid = 'jsonb'::regtype
          AND NOT attnotnull AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'WORKFLOW_METADATA_SCHEMA_MISMATCH' USING ERRCODE = '23514';
    END IF;
END
$$;
