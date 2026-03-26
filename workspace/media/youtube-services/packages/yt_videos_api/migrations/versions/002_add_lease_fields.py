"""Add lease and retry fields for crash recovery

Revision ID: 002
Revises: 001
Create Date: 2026-01-01 12:00:00.000000

Adds lease-based crash recovery fields to jobs table:
- locked_at: When job was claimed
- locked_by: Worker ID (hostname)
- lease_expires_at: When lease expires (for re-claiming)
- attempts: Retry counter
- max_attempts: Maximum retry limit
- next_run_at: Scheduled retry time
- quota_units_used: YouTube API quota tracking

"""
from alembic import op
import sqlalchemy as sa

revision = '002'
down_revision = '001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add lease fields for crash recovery
    op.add_column('jobs', sa.Column('locked_at', sa.TIMESTAMP(timezone=True), nullable=True), schema='yt_videos')
    op.add_column('jobs', sa.Column('locked_by', sa.Text(), nullable=True), schema='yt_videos')
    op.add_column('jobs', sa.Column('lease_expires_at', sa.TIMESTAMP(timezone=True), nullable=True), schema='yt_videos')

    # Add retry logic fields
    op.add_column('jobs', sa.Column('attempts', sa.Integer(), nullable=False, server_default='0'), schema='yt_videos')
    op.add_column('jobs', sa.Column('max_attempts', sa.Integer(), nullable=False, server_default='3'), schema='yt_videos')
    op.add_column('jobs', sa.Column('next_run_at', sa.TIMESTAMP(timezone=True), nullable=True), schema='yt_videos')

    # Add quota tracking
    op.add_column('jobs', sa.Column('quota_units_used', sa.Integer(), nullable=False, server_default='0'), schema='yt_videos')

    # Create performance indexes
    # Index for claim_jobs() query (status + next_run_at filter)
    op.create_index(
        'idx_jobs_claim_scan',
        'jobs',
        ['status', 'next_run_at', 'attempts', 'requested_at'],
        schema='yt_videos'
    )

    # Index for reset_expired_leases() query
    op.create_index(
        'idx_jobs_lease_expires',
        'jobs',
        ['lease_expires_at'],
        schema='yt_videos',
        postgresql_where=sa.text("status = 'processing'")
    )


def downgrade() -> None:
    # Drop indexes
    op.drop_index('idx_jobs_lease_expires', schema='yt_videos')
    op.drop_index('idx_jobs_claim_scan', schema='yt_videos')

    # Drop columns
    op.drop_column('jobs', 'quota_units_used', schema='yt_videos')
    op.drop_column('jobs', 'next_run_at', schema='yt_videos')
    op.drop_column('jobs', 'max_attempts', schema='yt_videos')
    op.drop_column('jobs', 'attempts', schema='yt_videos')
    op.drop_column('jobs', 'lease_expires_at', schema='yt_videos')
    op.drop_column('jobs', 'locked_by', schema='yt_videos')
    op.drop_column('jobs', 'locked_at', schema='yt_videos')
