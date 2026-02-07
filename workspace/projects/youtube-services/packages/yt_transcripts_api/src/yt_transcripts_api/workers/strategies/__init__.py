"""Transcript extraction strategies"""

from youtube_transcript_api import YouTubeTranscriptApi, NoTranscriptFound
from yt_core.database import DatabasePool
from yt_core.ratelimit import YouTubeRateLimiter
import structlog
import hashlib

logger = structlog.get_logger()


async def extract_transcript(
    db_pool: DatabasePool,
    video_id: str,
    language_prefs: list[str],
    http_limiter: YouTubeRateLimiter,
) -> dict:
    """
    Extract transcript using fallback strategy chain:
    1. Official captions
    2. Auto-generated captions
    3. No transcript available

    Returns dict with:
        - strategy: "official", "auto", or "none"
        - language: language code
        - text: full transcript text
        - segments: list of segment dicts
    """
    # Check if we already have a transcript
    async with db_pool.acquire() as conn:
        existing = await conn.fetchrow(
            """
            SELECT * FROM yt_transcripts.transcripts
            WHERE video_id = $1
            AND language_code = ANY($2)
            ORDER BY CASE strategy_used
                WHEN 'official' THEN 1
                WHEN 'auto' THEN 2
                ELSE 3
            END
            LIMIT 1
            """,
            video_id,
            language_prefs,
        )

        if existing and existing["file_path"]:
            logger.info(
                "transcript.cache_hit",
                video_id=video_id,
                strategy=existing["strategy_used"],
            )
            # TODO: Read transcript from file_path
            return {
                "strategy": existing["strategy_used"],
                "language": existing["language_code"],
                "text": "",  # Loaded from file
                "segments": [],
            }

    # Extract new transcript
    async with http_limiter:
        try:
            # Try to get transcript
            transcript_list = YouTubeTranscriptApi.list_transcripts(video_id)

            # Try manual (official) captions first
            for lang in language_prefs:
                try:
                    transcript = transcript_list.find_transcript([lang])
                    if not transcript.is_generated:
                        segments = transcript.fetch()
                        text = " ".join([s["text"] for s in segments])

                        # Store in database
                        await _store_transcript(
                            db_pool,
                            video_id,
                            lang,
                            "official",
                            text,
                            segments,
                        )

                        logger.info(
                            "transcript.extracted",
                            video_id=video_id,
                            strategy="official",
                            language=lang,
                        )

                        return {
                            "strategy": "official",
                            "language": lang,
                            "text": text,
                            "segments": segments,
                        }
                except:
                    continue

            # Try auto-generated captions
            for lang in language_prefs:
                try:
                    transcript = transcript_list.find_generated_transcript([lang])
                    segments = transcript.fetch()
                    text = " ".join([s["text"] for s in segments])

                    await _store_transcript(
                        db_pool, video_id, lang, "auto", text, segments
                    )

                    logger.info(
                        "transcript.extracted",
                        video_id=video_id,
                        strategy="auto",
                        language=lang,
                    )

                    return {
                        "strategy": "auto",
                        "language": lang,
                        "text": text,
                        "segments": segments,
                    }
                except:
                    continue

        except NoTranscriptFound:
            pass
        except Exception as e:
            logger.error(
                "transcript.extraction_error", video_id=video_id, error=str(e)
            )

    # No transcript available
    await _store_transcript(db_pool, video_id, language_prefs[0], "none", None, None)

    logger.warning("transcript.not_available", video_id=video_id)

    return {"strategy": "none", "language": None, "text": None, "segments": None}


async def _store_transcript(
    db_pool: DatabasePool,
    video_id: str,
    language: str,
    strategy: str,
    text: str | None,
    segments: list | None,
):
    """Store transcript in database"""
    # Calculate hash
    file_hash = None
    text_preview = None
    segment_count = 0

    if text:
        file_hash = hashlib.sha256(text.encode()).hexdigest()
        text_preview = text[:500]
        segment_count = len(segments) if segments else 0

    async with db_pool.acquire() as conn:
        await conn.execute(
            """
            INSERT INTO yt_transcripts.transcripts (
                video_id, language_code, strategy_used,
                file_hash, text_preview, segment_count
            )
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (video_id, language_code)
            DO UPDATE SET
                strategy_used = EXCLUDED.strategy_used,
                file_hash = EXCLUDED.file_hash,
                text_preview = EXCLUDED.text_preview,
                segment_count = EXCLUDED.segment_count,
                extracted_at = NOW()
            """,
            video_id,
            language,
            strategy,
            file_hash,
            text_preview,
            segment_count,
        )
