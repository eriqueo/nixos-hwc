-- Bozeman event curation and Discord approval ledger.
-- Retention: AUTO-MANAGED; hwc.prune_event_cases() removes terminal cases
-- 180 days after last observation. Reserved/uncertain effects are retained.

CREATE SCHEMA IF NOT EXISTS hwc;

CREATE TABLE IF NOT EXISTS hwc.event_cases (
    fingerprint       TEXT PRIMARY KEY CHECK (fingerprint ~ '^[a-f0-9]{64}$'),
    schema_version    INT NOT NULL DEFAULT 1 CHECK (schema_version = 1),
    state             TEXT NOT NULL DEFAULT 'candidate'
                      CHECK (state IN ('candidate', 'reserved', 'delivered', 'uncertain', 'handled')),
    title             TEXT NOT NULL,
    start_at          TIMESTAMPTZ NOT NULL,
    end_at            TIMESTAMPTZ,
    location          TEXT NOT NULL,
    description       TEXT,
    url               TEXT,
    source            TEXT NOT NULL,
    track             TEXT NOT NULL CHECK (track IN ('family', 'business', 'both')),
    first_seen_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hwc.event_curation_judgments (
    id                BIGSERIAL PRIMARY KEY,
    fingerprint       TEXT NOT NULL REFERENCES hwc.event_cases(fingerprint) ON DELETE CASCADE,
    run_key           TEXT NOT NULL,
    rule_version      TEXT NOT NULL,
    outcome           TEXT NOT NULL CHECK (outcome IN ('selected', 'withheld', 'needs_review')),
    score             INT NOT NULL CHECK (score BETWEEN -100 AND 100),
    score_components  JSONB NOT NULL,
    reasons           JSONB NOT NULL,
    judged_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (fingerprint, run_key, rule_version)
);

CREATE TABLE IF NOT EXISTS hwc.event_deliveries (
    fingerprint       TEXT PRIMARY KEY REFERENCES hwc.event_cases(fingerprint) ON DELETE CASCADE,
    reservation_key   TEXT NOT NULL,
    state             TEXT NOT NULL CHECK (state IN ('reserved', 'delivered', 'uncertain', 'failed')),
    discord_message_id TEXT,
    attempted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS hwc.event_interactions (
    interaction_id    TEXT PRIMARY KEY,
    fingerprint       TEXT NOT NULL REFERENCES hwc.event_cases(fingerprint) ON DELETE CASCADE,
    action            TEXT NOT NULL CHECK (action IN ('add_calendar', 'ignore')),
    actor_id          TEXT NOT NULL,
    discord_message_id TEXT NOT NULL,
    state             TEXT NOT NULL CHECK (state IN ('reserved', 'applied', 'uncertain')),
    result            JSONB,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at      TIMESTAMPTZ
);

-- Human actions are events. Rows are appended; the operational reservation
-- above may change state, but this judgment trail is never updated in place.
CREATE TABLE IF NOT EXISTS hwc.event_human_events (
    id                BIGSERIAL PRIMARY KEY,
    fingerprint       TEXT NOT NULL REFERENCES hwc.event_cases(fingerprint) ON DELETE CASCADE,
    interaction_id    TEXT NOT NULL,
    actor_id          TEXT NOT NULL,
    action            TEXT NOT NULL,
    outcome           TEXT NOT NULL,
    detail            JSONB NOT NULL DEFAULT '{}'::jsonb,
    occurred_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (interaction_id, outcome)
);

CREATE INDEX IF NOT EXISTS event_cases_last_seen_idx
    ON hwc.event_cases(last_seen_at);
CREATE INDEX IF NOT EXISTS event_judgments_fingerprint_idx
    ON hwc.event_curation_judgments(fingerprint, judged_at DESC);
CREATE INDEX IF NOT EXISTS event_human_events_fingerprint_idx
    ON hwc.event_human_events(fingerprint, occurred_at DESC);

CREATE OR REPLACE FUNCTION hwc.reserve_event_action(
    p_fingerprint TEXT,
    p_action TEXT,
    p_interaction_id TEXT,
    p_actor_id TEXT,
    p_discord_message_id TEXT
) RETURNS TABLE(disposition TEXT, action_result JSONB, replayed BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    prior hwc.event_interactions%ROWTYPE;
    terminal_outcome TEXT;
    terminal_result JSONB;
BEGIN
    SELECT * INTO prior
      FROM hwc.event_interactions AS i
     WHERE i.interaction_id = p_interaction_id;
    IF FOUND THEN
        RETURN QUERY SELECT
            CASE WHEN prior.state = 'reserved' THEN 'duplicate' ELSE 'replay' END,
            COALESCE(prior.result, jsonb_build_object(
                'outcome', 'queued',
                'message', 'This event action is still being applied. Do not press again.'
            )),
            true;
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext(p_fingerprint));
    IF NOT EXISTS (SELECT 1 FROM hwc.event_cases AS c WHERE c.fingerprint = p_fingerprint) THEN
        RETURN QUERY SELECT 'not_found', NULL::jsonb, false;
        RETURN;
    END IF;

    SELECT h.outcome INTO terminal_outcome
      FROM hwc.event_human_events AS h
     WHERE h.fingerprint = p_fingerprint
       AND h.outcome IN ('added', 'ignored')
     ORDER BY h.occurred_at DESC
     LIMIT 1;

    IF terminal_outcome IS NOT NULL THEN
        terminal_result := CASE terminal_outcome
            WHEN 'added' THEN jsonb_build_object(
                'outcome', 'already_added',
                'message', 'This event was already added to the calendar.'
            )
            ELSE jsonb_build_object(
                'outcome', 'already_ignored',
                'message', 'This event was already ignored.'
            )
        END;
        INSERT INTO hwc.event_interactions (
            interaction_id, fingerprint, action, actor_id, discord_message_id,
            state, result, completed_at
        ) VALUES (
            p_interaction_id, p_fingerprint, p_action, p_actor_id, p_discord_message_id,
            'applied', terminal_result, now()
        );
        INSERT INTO hwc.event_human_events (
            fingerprint, interaction_id, actor_id, action, outcome, detail
        ) VALUES (
            p_fingerprint, p_interaction_id, p_actor_id, p_action,
            terminal_result->>'outcome', terminal_result
        );
        RETURN QUERY SELECT 'replay', terminal_result, false;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1 FROM hwc.event_interactions AS i
         WHERE i.fingerprint = p_fingerprint AND i.state IN ('reserved', 'uncertain')
    ) THEN
        RETURN QUERY SELECT 'duplicate', jsonb_build_object(
            'outcome', 'queued',
            'message', 'An event action is already in progress. Do not press again.'
        ), false;
        RETURN;
    END IF;

    INSERT INTO hwc.event_interactions (
        interaction_id, fingerprint, action, actor_id, discord_message_id, state
    ) VALUES (
        p_interaction_id, p_fingerprint, p_action, p_actor_id, p_discord_message_id, 'reserved'
    );
    INSERT INTO hwc.event_human_events (
        fingerprint, interaction_id, actor_id, action, outcome
    ) VALUES (
        p_fingerprint, p_interaction_id, p_actor_id, p_action, 'requested'
    );
    RETURN QUERY SELECT 'execute', NULL::jsonb, false;
END;
$$;

CREATE OR REPLACE FUNCTION hwc.complete_event_action(
    p_interaction_id TEXT,
    p_outcome TEXT,
    p_message TEXT
) RETURNS TABLE(action_result JSONB, replayed BOOLEAN)
LANGUAGE plpgsql
AS $$
DECLARE
    current_interaction hwc.event_interactions%ROWTYPE;
    final_result JSONB;
    final_state TEXT;
BEGIN
    SELECT * INTO current_interaction
      FROM hwc.event_interactions AS i
     WHERE i.interaction_id = p_interaction_id
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'event interaction not reserved';
    END IF;
    IF current_interaction.state <> 'reserved' THEN
        RETURN QUERY SELECT current_interaction.result, true;
        RETURN;
    END IF;
    IF p_outcome NOT IN ('added', 'ignored', 'queued') THEN
        RAISE EXCEPTION 'invalid event action outcome';
    END IF;

    final_result := jsonb_build_object('outcome', p_outcome, 'message', p_message);
    final_state := CASE WHEN p_outcome = 'queued' THEN 'uncertain' ELSE 'applied' END;
    UPDATE hwc.event_interactions
       SET state = final_state, result = final_result, completed_at = now()
     WHERE interaction_id = p_interaction_id;
    UPDATE hwc.event_cases
       SET state = CASE WHEN p_outcome = 'queued' THEN 'uncertain' ELSE 'handled' END,
           updated_at = now()
     WHERE fingerprint = current_interaction.fingerprint;
    INSERT INTO hwc.event_human_events (
        fingerprint, interaction_id, actor_id, action, outcome, detail
    ) VALUES (
        current_interaction.fingerprint, current_interaction.interaction_id,
        current_interaction.actor_id, current_interaction.action, p_outcome, final_result
    ) ON CONFLICT (interaction_id, outcome) DO NOTHING;
    RETURN QUERY SELECT final_result, false;
END;
$$;

CREATE OR REPLACE FUNCTION hwc.prune_event_cases(p_retention INTERVAL DEFAULT INTERVAL '180 days')
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    removed INTEGER;
BEGIN
    DELETE FROM hwc.event_cases AS c
     WHERE c.last_seen_at < now() - p_retention
       AND c.state NOT IN ('reserved', 'uncertain');
    GET DIAGNOSTICS removed = ROW_COUNT;
    RETURN removed;
END;
$$;

COMMENT ON TABLE hwc.event_cases IS
    'AUTO-MANAGED Bozeman event cases. Rebuilt from source; terminal rows retained 180 days.';
COMMENT ON TABLE hwc.event_curation_judgments IS
    'Append-only, versioned curation decisions. Outcome is distinct from event lifecycle state.';
COMMENT ON TABLE hwc.event_human_events IS
    'Append-only Discord reviewer actions and their terminal outcomes.';
