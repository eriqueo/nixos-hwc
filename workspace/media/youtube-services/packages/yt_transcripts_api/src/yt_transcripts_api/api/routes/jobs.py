"""Job submission and status endpoints"""

from fastapi import APIRouter, Depends, HTTPException
from yt_core.database import DatabasePool
from uuid import UUID
from typing import Optional, List
import structlog

from ..dependencies import get_db_pool
from ..models import JobCreateRequest, JobResponse, JobListResponse

router = APIRouter()
logger = structlog.get_logger()


@router.post("", response_model=JobResponse, status_code=201)
async def create_job(
    request: JobCreateRequest,
    db_pool: DatabasePool = Depends(get_db_pool),
):
    """
    Submit a new transcript extraction job.

    - **entity_type**: video, playlist, or channel
    - **entity_id**: YouTube video/playlist/channel ID
    - **output_format**: markdown or jsonl
    - **language_preference**: Optional list of preferred languages (e.g., ["en", "en-US"])
    - **idempotency_key**: Optional key for idempotent job submission
    """
    async with db_pool.acquire() as conn:
        # Check for existing job with idempotency key
        if request.idempotency_key:
            existing = await conn.fetchrow(
                """
                SELECT * FROM yt_transcripts.jobs
                WHERE idempotency_key = $1
                """,
                request.idempotency_key,
            )
            if existing:
                logger.info(
                    "job.idempotent_resubmission",
                    job_id=str(existing["id"]),
                    idempotency_key=request.idempotency_key,
                )
                return JobResponse.model_validate(dict(existing))

        # Create new job
        job = await conn.fetchrow(
            """
            INSERT INTO yt_transcripts.jobs (
                entity_type, entity_id, output_format,
                language_preference, idempotency_key
            )
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            """,
            request.entity_type,
            request.entity_id,
            request.output_format,
            request.language_preference,
            request.idempotency_key,
        )

        logger.info(
            "job.created",
            job_id=str(job["id"]),
            entity_type=request.entity_type,
            entity_id=request.entity_id,
        )

        return JobResponse.model_validate(dict(job))


@router.get("/{job_id}", response_model=JobResponse)
async def get_job(
    job_id: UUID,
    db_pool: DatabasePool = Depends(get_db_pool),
):
    """Get job status and results"""
    async with db_pool.acquire() as conn:
        job = await conn.fetchrow(
            """
            SELECT * FROM yt_transcripts.jobs
            WHERE id = $1
            """,
            job_id,
        )

        if not job:
            raise HTTPException(status_code=404, detail="Job not found")

        return JobResponse.model_validate(dict(job))


@router.get("", response_model=JobListResponse)
async def list_jobs(
    status: Optional[str] = None,
    entity_type: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    db_pool: DatabasePool = Depends(get_db_pool),
):
    """
    List jobs with pagination and filtering.

    - **status**: Filter by status (pending, processing, completed, failed)
    - **entity_type**: Filter by entity type (video, playlist, channel)
    - **limit**: Page size (default 50, max 100)
    - **offset**: Pagination offset
    """
    if limit > 100:
        limit = 100

    filters = []
    params: List = [limit, offset]
    param_num = 3

    if status:
        filters.append(f"status = ${param_num}")
        params.append(status)
        param_num += 1

    if entity_type:
        filters.append(f"entity_type = ${param_num}")
        params.append(entity_type)
        param_num += 1

    where_clause = f"WHERE {' AND '.join(filters)}" if filters else ""

    async with db_pool.acquire() as conn:
        # Get jobs
        jobs = await conn.fetch(
            f"""
            SELECT * FROM yt_transcripts.jobs
            {where_clause}
            ORDER BY requested_at DESC
            LIMIT $1 OFFSET $2
            """,
            *params,
        )

        # Get total count
        total = await conn.fetchval(
            f"""
            SELECT COUNT(*) FROM yt_transcripts.jobs
            {where_clause}
            """,
            *params[2:],  # Skip limit and offset
        )

        return JobListResponse(
            jobs=[JobResponse.model_validate(dict(j)) for j in jobs],
            total=total,
            limit=limit,
            offset=offset,
        )


@router.delete("/{job_id}", status_code=204)
async def cancel_job(
    job_id: UUID,
    db_pool: DatabasePool = Depends(get_db_pool),
):
    """Cancel a pending or processing job"""
    async with db_pool.acquire() as conn:
        result = await conn.execute(
            """
            UPDATE yt_transcripts.jobs
            SET status = 'cancelled', completed_at = NOW()
            WHERE id = $1 AND status IN ('pending', 'processing')
            """,
            job_id,
        )

        if result == "UPDATE 0":
            raise HTTPException(
                status_code=404,
                detail="Job not found or cannot be cancelled",
            )

        logger.info("job.cancelled", job_id=str(job_id))
