"""Initial schema for transcript service

Revision ID: 001
Revises:
Create Date: 2026-01-01 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create schema
    op.execute("CREATE SCHEMA IF NOT EXISTS yt_transcripts")

    # Jobs table (user requests)
    op.create_table(
        'jobs',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('entity_type', sa.Text(), nullable=False),
        sa.Column('entity_id', sa.Text(), nullable=False),
        sa.Column('status', sa.Text(), nullable=False, server_default='pending'),
        sa.Column('requested_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        sa.Column('started_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('completed_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('output_format', sa.Text(), nullable=False, server_default='markdown'),
        sa.Column('language_preference', postgresql.ARRAY(sa.Text()), nullable=True),
        sa.Column('total_videos', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('successful_videos', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('failed_videos', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('output_location', sa.Text(), nullable=True),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('idempotency_key', sa.Text(), nullable=True, unique=True),
        schema='yt_transcripts'
    )

    # GLOBAL video metadata (deduplicated across all jobs)
    op.create_table(
        'videos',
        sa.Column('video_id', sa.Text(), primary_key=True),
        sa.Column('title', sa.Text(), nullable=True),
        sa.Column('channel_id', sa.Text(), nullable=True),
        sa.Column('channel_name', sa.Text(), nullable=True),
        sa.Column('duration_seconds', sa.Integer(), nullable=True),
        sa.Column('published_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('last_fetched_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        schema='yt_transcripts'
    )

    # GLOBAL transcripts (deduplicated, one per video_id + language)
    # Store file path and hash, NOT full text (too large for DB)
    op.create_table(
        'transcripts',
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('language_code', sa.Text(), nullable=False),
        sa.Column('strategy_used', sa.Text(), nullable=False),
        sa.Column('file_path', sa.Text(), nullable=True),
        sa.Column('file_hash', sa.Text(), nullable=True),
        sa.Column('text_preview', sa.Text(), nullable=True),
        sa.Column('segment_count', sa.Integer(), nullable=True),
        sa.Column('extracted_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['video_id'], ['yt_transcripts.videos.video_id'], ),
        sa.PrimaryKeyConstraint('video_id', 'language_code'),
        schema='yt_transcripts'
    )

    # Many-to-many: which videos are in which jobs
    op.create_table(
        'job_videos',
        sa.Column('job_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('language_code', sa.Text(), nullable=True),
        sa.Column('position', sa.Integer(), nullable=True),
        sa.ForeignKeyConstraint(['job_id'], ['yt_transcripts.jobs.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['video_id'], ['yt_transcripts.videos.video_id'], ),
        sa.PrimaryKeyConstraint('job_id', 'video_id'),
        schema='yt_transcripts'
    )

    # Extraction attempts (for retry logic and debugging)
    op.create_table(
        'extraction_attempts',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('language_code', sa.Text(), nullable=False),
        sa.Column('strategy', sa.Text(), nullable=False),
        sa.Column('attempted_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        sa.Column('success', sa.Boolean(), nullable=False),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('retry_after', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['video_id'], ['yt_transcripts.videos.video_id'], ),
        schema='yt_transcripts'
    )

    # Playlist expansion cache
    op.create_table(
        'playlist_cache',
        sa.Column('playlist_id', sa.Text(), primary_key=True),
        sa.Column('video_ids', postgresql.ARRAY(sa.Text()), nullable=False),
        sa.Column('fetched_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        sa.Column('expires_at', sa.TIMESTAMP(timezone=True), nullable=False),
        schema='yt_transcripts'
    )

    # Create indexes
    op.create_index('idx_jobs_status', 'jobs', ['status'], schema='yt_transcripts')
    op.create_index('idx_jobs_entity', 'jobs', ['entity_type', 'entity_id'], schema='yt_transcripts')
    op.create_index('idx_jobs_requested_at', 'jobs', [sa.text('requested_at DESC')], schema='yt_transcripts')
    op.create_index('idx_videos_channel', 'videos', ['channel_id'], schema='yt_transcripts')
    op.create_index('idx_transcripts_extracted', 'transcripts', [sa.text('extracted_at DESC')], schema='yt_transcripts')
    op.create_index('idx_job_videos_job', 'job_videos', ['job_id'], schema='yt_transcripts')
    op.create_index('idx_playlist_cache_expires', 'playlist_cache', ['expires_at'], schema='yt_transcripts')


def downgrade() -> None:
    op.drop_table('playlist_cache', schema='yt_transcripts')
    op.drop_table('extraction_attempts', schema='yt_transcripts')
    op.drop_table('job_videos', schema='yt_transcripts')
    op.drop_table('transcripts', schema='yt_transcripts')
    op.drop_table('videos', schema='yt_transcripts')
    op.drop_table('jobs', schema='yt_transcripts')
    op.execute("DROP SCHEMA yt_transcripts CASCADE")
