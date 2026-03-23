-- ============================================================
-- Social Intelligence Pipeline — Database Schema
-- Run this once against your Postgres instance to create
-- the two tables used by the n8n workflows.
-- ============================================================

-- Table 1: Stores every analyzed social media post
CREATE TABLE IF NOT EXISTS social_intelligence (
    id                  SERIAL PRIMARY KEY,
    author              TEXT,
    post_date           TEXT,
    source              TEXT,                  -- 'Facebook', 'Reddit', 'Nextdoor'
    group_name          TEXT,                  -- e.g. 'r/Bozeman', 'JobTread Users'
    post_text           TEXT,
    reactions           TEXT,
    comments_count      INTEGER DEFAULT 0,
    comments_raw        JSONB,                 -- Full comment array as JSON
    summary             TEXT,                  -- LLM-generated summary
    category            TEXT,                  -- e.g. 'Pain Point', 'Service Request'
    themes              JSONB,                 -- Array of keyword strings
    sentiment           TEXT,                  -- 'Positive', 'Negative', 'Neutral', 'Mixed'
    business_relevance  TEXT,                  -- 'High', 'Medium', 'Low'
    marketing_angle     TEXT,                  -- LLM-suggested marketing use
    pain_points         JSONB,                 -- Array of specific pain point strings
    content_generated   BOOLEAN DEFAULT false, -- Flag: has content been generated from this?
    processed_at        TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for fast querying
CREATE INDEX IF NOT EXISTS idx_si_source           ON social_intelligence(source);
CREATE INDEX IF NOT EXISTS idx_si_category         ON social_intelligence(category);
CREATE INDEX IF NOT EXISTS idx_si_sentiment        ON social_intelligence(sentiment);
CREATE INDEX IF NOT EXISTS idx_si_relevance        ON social_intelligence(business_relevance);
CREATE INDEX IF NOT EXISTS idx_si_content_flag     ON social_intelligence(content_generated);
CREATE INDEX IF NOT EXISTS idx_si_processed_at     ON social_intelligence(processed_at DESC);

-- Full-text search index on post text and summary
CREATE INDEX IF NOT EXISTS idx_si_fts ON social_intelligence
    USING GIN(to_tsvector('english', coalesce(post_text,'') || ' ' || coalesce(summary,'')));

-- ============================================================

-- Table 2: Stores all generated content drafts
CREATE TABLE IF NOT EXISTS content_drafts (
    id          SERIAL PRIMARY KEY,
    intel_id    INTEGER REFERENCES social_intelligence(id),
    blog_title  TEXT,
    blog_meta   TEXT,       -- SEO meta description
    blog_outline JSONB,     -- Array of section headings
    blog_intro  TEXT,       -- Opening paragraph
    blog_cta    TEXT,       -- Call to action
    ad_headline TEXT,
    ad_text     TEXT,
    ad_cta      TEXT,
    social_text TEXT,       -- Organic social post copy
    status      TEXT DEFAULT 'draft',  -- 'draft', 'approved', 'published'
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    published_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cd_status     ON content_drafts(status);
CREATE INDEX IF NOT EXISTS idx_cd_created_at ON content_drafts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_cd_intel_id   ON content_drafts(intel_id);

-- ============================================================
-- USEFUL QUERIES FOR EXPLORING YOUR DATA
-- ============================================================

-- Find all high-relevance pain points
-- SELECT author, source, group_name, summary, pain_points, marketing_angle
-- FROM social_intelligence
-- WHERE business_relevance = 'High' AND category = 'Pain Point'
-- ORDER BY processed_at DESC;

-- Full-text search across all posts
-- SELECT author, source, summary, sentiment
-- FROM social_intelligence
-- WHERE to_tsvector('english', post_text || ' ' || summary) @@ plainto_tsquery('english', 'contractor availability')
-- ORDER BY processed_at DESC;

-- See all content drafts ready for review
-- SELECT cd.blog_title, cd.ad_headline, si.source, si.group_name, si.summary
-- FROM content_drafts cd
-- JOIN social_intelligence si ON cd.intel_id = si.id
-- WHERE cd.status = 'draft'
-- ORDER BY cd.created_at DESC;

-- Category breakdown by source
-- SELECT source, category, COUNT(*) as count
-- FROM social_intelligence
-- GROUP BY source, category
-- ORDER BY source, count DESC;
