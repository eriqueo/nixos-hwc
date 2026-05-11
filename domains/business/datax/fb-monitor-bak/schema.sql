-- fb-monitor schema
-- Facebook group monitoring tables for DataX business intelligence

CREATE TABLE IF NOT EXISTS fb_posts (
    post_id TEXT PRIMARY KEY,
    body TEXT NOT NULL,
    author TEXT,
    source_group TEXT,
    url TEXT,
    post_timestamp TIMESTAMPTZ,
    comment_count INTEGER,
    first_captured TIMESTAMPTZ DEFAULT NOW(),
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    classification TEXT,       -- 'datax_mention', 'related', 'not_related'
    classification_tags TEXT[], -- ['estimating', 'integration_gap', 'ai_usage', ...]
    notes TEXT
);

CREATE TABLE IF NOT EXISTS fb_comments (
    id SERIAL PRIMARY KEY,
    post_id TEXT NOT NULL REFERENCES fb_posts(post_id),
    comment_hash TEXT NOT NULL,
    author TEXT,
    body TEXT,
    depth INTEGER DEFAULT 0,
    comment_timestamp TIMESTAMPTZ,
    captured_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, comment_hash)
);

CREATE TABLE IF NOT EXISTS fb_capture_log (
    id SERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ DEFAULT NOW(),
    source_url TEXT,
    posts_total INTEGER,
    posts_new INTEGER,
    posts_updated INTEGER,
    comments_new INTEGER
);

CREATE INDEX IF NOT EXISTS idx_fb_comments_post ON fb_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_fb_posts_class ON fb_posts(classification);
CREATE INDEX IF NOT EXISTS idx_fb_posts_updated ON fb_posts(last_updated);
