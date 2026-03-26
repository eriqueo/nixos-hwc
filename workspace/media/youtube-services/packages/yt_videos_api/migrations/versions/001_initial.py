"""Initial schema for video download service

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
    op.execute("CREATE SCHEMA IF NOT EXISTS yt_videos")

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
        sa.Column('output_directory', sa.Text(), nullable=False),
        sa.Column('container_policy', sa.Text(), nullable=False, server_default='webm'),
        sa.Column('embed_metadata', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('embed_cover_art', sa.Boolean(), nullable=False, server_default='true'),
        sa.Column('remove_after_download', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('total_videos', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('successful_downloads', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('failed_downloads', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_bytes_downloaded', sa.BigInteger(), nullable=False, server_default='0'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('idempotency_key', sa.Text(), nullable=True, unique=True),
        schema='yt_videos'
    )

    # GLOBAL video metadata
    op.create_table(
        'videos',
        sa.Column('video_id', sa.Text(), primary_key=True),
        sa.Column('title', sa.Text(), nullable=True),
        sa.Column('channel_id', sa.Text(), nullable=True),
        sa.Column('channel_name', sa.Text(), nullable=True),
        sa.Column('duration_seconds', sa.Integer(), nullable=True),
        sa.Column('published_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('last_fetched_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        schema='yt_videos'
    )

    # GLOBAL downloads (deduplicated by video_id + container_policy)
    op.create_table(
        'downloads',
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('container_policy', sa.Text(), nullable=False),
        sa.Column('extractor_used', sa.Text(), nullable=True),
        sa.Column('file_path', sa.Text(), nullable=False),
        sa.Column('file_hash', sa.Text(), nullable=True),
        sa.Column('file_size_bytes', sa.BigInteger(), nullable=False),
        sa.Column('video_codec', sa.Text(), nullable=True),
        sa.Column('audio_codec', sa.Text(), nullable=True),
        sa.Column('resolution', sa.Text(), nullable=True),
        sa.Column('started_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('completed_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['video_id'], ['yt_videos.videos.video_id'], ),
        sa.PrimaryKeyConstraint('video_id', 'container_policy'),
        schema='yt_videos'
    )

    # Many-to-many: which videos are in which jobs
    op.create_table(
        'job_videos',
        sa.Column('job_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('position', sa.Integer(), nullable=True),
        sa.Column('downloaded', sa.Boolean(), nullable=False, server_default='false'),
        sa.ForeignKeyConstraint(['job_id'], ['yt_videos.jobs.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['video_id'], ['yt_videos.videos.video_id'], ),
        sa.PrimaryKeyConstraint('job_id', 'video_id'),
        schema='yt_videos'
    )

    # Download attempts (for multi-extractor fallback)
    op.create_table(
        'download_attempts',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('extractor', sa.Text(), nullable=False),
        sa.Column('attempted_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        sa.Column('success', sa.Boolean(), nullable=False),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['video_id'], ['yt_videos.videos.video_id'], ),
        schema='yt_videos'
    )

    # Staging area tracking (for atomic finalization)
    op.create_table(
        'staging',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('staging_path', sa.Text(), nullable=False, unique=True),
        sa.Column('final_path', sa.Text(), nullable=False),
        sa.Column('created_at', sa.TIMESTAMP(timezone=True), nullable=False, server_default=sa.text('NOW()')),
        sa.Column('lock_expires_at', sa.TIMESTAMP(timezone=True), nullable=False),
        sa.Column('finalized', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('finalized_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['video_id'], ['yt_videos.videos.video_id'], ),
        schema='yt_videos'
    )

    # Playlist tracking (for optional removal after download)
    op.create_table(
        'playlist_items',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), primary_key=True),
        sa.Column('playlist_id', sa.Text(), nullable=False),
        sa.Column('video_id', sa.Text(), nullable=False),
        sa.Column('position', sa.Integer(), nullable=False),
        sa.Column('playlist_item_id', sa.Text(), nullable=True),
        sa.Column('should_remove', sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('removed_at', sa.TIMESTAMP(timezone=True), nullable=True),
        sa.Column('removal_error', sa.Text(), nullable=True),
        sa.UniqueConstraint('playlist_id', 'video_id'),
        schema='yt_videos'
    )

    # Create indexes
    op.create_index('idx_video_jobs_status', 'jobs', ['status'], schema='yt_videos')
    op.create_index('idx_video_jobs_entity', 'jobs', ['entity_type', 'entity_id'], schema='yt_videos')
    op.create_index('idx_video_jobs_requested_at', 'jobs', [sa.text('requested_at DESC')], schema='yt_videos')
    op.create_index('idx_videos_channel', 'videos', ['channel_id'], schema='yt_videos')
    op.create_index('idx_downloads_completed', 'downloads', [sa.text('completed_at DESC')], schema='yt_videos')
    op.create_index('idx_job_videos_job', 'job_videos', ['job_id'], schema='yt_videos')
    op.create_index('idx_staging_expired', 'staging', ['lock_expires_at'], schema='yt_videos')


def downgrade() -> None:
    op.drop_table('playlist_items', schema='yt_videos')
    op.drop_table('staging', schema='yt_videos')
    op.drop_table('download_attempts', schema='yt_videos')
    op.drop_table('job_videos', schema='yt_videos')
    op.drop_table('downloads', schema='yt_videos')
    op.drop_table('videos', schema='yt_videos')
    op.drop_table('jobs', schema='yt_videos')
    op.execute("DROP SCHEMA yt_videos CASCADE")
