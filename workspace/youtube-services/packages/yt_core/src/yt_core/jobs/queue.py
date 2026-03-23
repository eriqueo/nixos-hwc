"""Job queue with PostgreSQL FOR UPDATE SKIP LOCKED and lease-based crash recovery"""

from datetime import datetime, timedelta
from typing import List, Optional
import asyncpg
import structlog
import socket

logger = structlog.get_logger()


def get_worker_id() -> str:
    """Get worker identifier (hostname)"""
    return socket.gethostname()


async def claim_jobs(
    conn: asyncpg.Connection,
    schema: str,
    max_jobs: int = 1,
    job_types: Optional[List[str]] = None,
    worker_id: Optional[str] = None,
    lease_duration_seconds: int = 3600,
) -> List[asyncpg.Record]:
    """
    Atomically claim pending jobs using PostgreSQL row-level locking with lease-based crash recovery.

    Lease semantics (for crash recovery):
    - locked_at: When the job was claimed
    - locked_by: Worker ID that claimed it (hostname)
    - lease_expires_at: When the lease expires
    - Jobs with expired leases are re-claimed automatically
    - attempts: Incremented on each claim (enforces max_attempts)

    Uses FOR UPDATE SKIP LOCKED to ensure each job is claimed
    by exactly one worker, even across multiple instances.

    Args:
        conn: Database connection
        schema: Schema name (e.g., 'yt_transcripts', 'yt_videos')
        max_jobs: Maximum number of jobs to claim
        job_types: Optional list of entity types to filter by
        worker_id: Worker identifier (defaults to hostname)
        lease_duration_seconds: How long the lease is valid (default: 1 hour)

    Returns:
        List of claimed job records
    """
    if worker_id is None:
        worker_id = get_worker_id()

    lease_expires = datetime.now() + timedelta(seconds=lease_duration_seconds)

    type_filter = ""
    params = [max_jobs, worker_id, lease_expires]
    param_num = 4

    if job_types:
        placeholders = ",".join(f"${i+param_num}" for i in range(len(job_types)))
        type_filter = f"AND entity_type IN ({placeholders})"
        params.extend(job_types)

    query = f"""
        UPDATE {schema}.jobs
        SET
            status = 'processing',
            started_at = COALESCE(started_at, NOW()),
            locked_at = NOW(),
            locked_by = $2,
            lease_expires_at = $3,
            attempts = attempts + 1
        WHERE id IN (
            SELECT id FROM {schema}.jobs
            WHERE (
                status = 'pending'
                OR (status = 'processing' AND lease_expires_at < NOW())
            )
            AND (next_run_at IS NULL OR next_run_at <= NOW())
            AND attempts < max_attempts
            {type_filter}
            ORDER BY requested_at ASC
            FOR UPDATE SKIP LOCKED
            LIMIT $1
        )
        RETURNING *
    """

    jobs = await conn.fetch(query, *params)

    if jobs:
        logger.info(
            "jobs.claimed",
            schema=schema,
            worker_id=worker_id,
            count=len(jobs),
            job_ids=[str(job["id"]) for job in jobs],
        )

    return jobs


async def reset_expired_leases(
    conn: asyncpg.Connection,
    schema: str,
) -> int:
    """
    Reset jobs with expired leases back to pending (reaper for crash recovery).

    Should be called periodically (e.g., every 5 minutes) to recover from worker crashes.

    Returns:
        Number of jobs reset
    """
    query = f"""
        UPDATE {schema}.jobs
        SET
            status = 'pending',
            locked_at = NULL,
            locked_by = NULL,
            lease_expires_at = NULL
        WHERE
            status = 'processing'
            AND lease_expires_at < NOW()
        RETURNING id
    """

    reset_jobs = await conn.fetch(query)
    count = len(reset_jobs)

    if count > 0:
        logger.warning(
            "jobs.leases_expired",
            schema=schema,
            count=count,
            job_ids=[str(j["id"]) for j in reset_jobs],
        )

    return count


async def update_job_status(
    conn: asyncpg.Connection,
    schema: str,
    job_id: str,
    status: str,
    error_message: Optional[str] = None,
    **extra_fields,
) -> None:
    """
    Update job status and completion metadata.

    Args:
        conn: Database connection
        schema: Schema name
        job_id: Job UUID
        status: New status ('processing', 'completed', 'failed', 'cancelled')
        error_message: Optional error message for failed jobs
        **extra_fields: Additional fields to update (e.g., total_videos, successful_videos)
    """
    set_clauses = ["status = $2"]
    params = [job_id, status]
    param_num = 3

    if status in ("completed", "failed", "cancelled"):
        set_clauses.append("completed_at = NOW()")

    if error_message:
        set_clauses.append(f"error_message = ${param_num}")
        params.append(error_message)
        param_num += 1

    for field, value in extra_fields.items():
        set_clauses.append(f"{field} = ${param_num}")
        params.append(value)
        param_num += 1

    query = f"""
        UPDATE {schema}.jobs
        SET {', '.join(set_clauses)}
        WHERE id = $1
    """

    await conn.execute(query, *params)

    logger.info(
        "job.status_updated",
        schema=schema,
        job_id=job_id,
        status=status,
        error=error_message,
    )
