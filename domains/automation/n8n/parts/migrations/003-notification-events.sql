-- Migration 003: Notification Events Table
-- TAXONOMY v1.0 — sys:router:notify durable event log
-- Created: 2026-03-31

CREATE TABLE IF NOT EXISTS hwc.notification_events (
  id                    SERIAL PRIMARY KEY,
  universe              VARCHAR(10)   NOT NULL,
  domain                VARCHAR(20)   NOT NULL,
  source                VARCHAR(50)   NOT NULL,
  category              VARCHAR(30)   NOT NULL,
  severity              VARCHAR(10)   NOT NULL,
  summary               TEXT          NOT NULL,
  action_hint           VARCHAR(30)   DEFAULT 'none',
  metadata              JSONB         DEFAULT '{}',
  event_timestamp       TIMESTAMPTZ   NOT NULL,
  -- routing audit
  slack_posted          BOOLEAN       DEFAULT FALSE,
  gotify_posted         BOOLEAN       DEFAULT FALSE,
  -- future self-healing
  remediation_attempted BOOLEAN       DEFAULT FALSE,
  remediation_result    TEXT,
  created_at            TIMESTAMPTZ   DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_events_universe_domain ON hwc.notification_events(universe, domain);
CREATE INDEX IF NOT EXISTS idx_events_source          ON hwc.notification_events(source);
CREATE INDEX IF NOT EXISTS idx_events_severity        ON hwc.notification_events(severity);
CREATE INDEX IF NOT EXISTS idx_events_category        ON hwc.notification_events(category);
CREATE INDEX IF NOT EXISTS idx_events_timestamp       ON hwc.notification_events(event_timestamp);
