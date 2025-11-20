#!/usr/bin/env python3
"""
YouTube Transcript API Service
HWC NixOS Homeserver - REST API for transcript extraction with mobile integration
"""

import asyncio
import json
import logging
import os
import shutil
import time
import uuid
import zipfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set
from urllib.parse import urlparse

try:
    from fastapi import FastAPI, Request, HTTPException, BackgroundTasks, Response
    from fastapi.responses import StreamingResponse, JSONResponse
    from pydantic import BaseModel, Field, AnyHttpUrl
    import httpx
    import uvicorn
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install fastapi uvicorn pydantic httpx")
    exit(1)

# Import our CLI transcript extractor (same directory as this API module)
import sys
current_dir = Path(__file__).resolve().parent
sys.path.append(str(current_dir))
from yt_transcript import TranscriptExtractor, Config as TranscriptConfig

# Import transcript cleaners
from cleaners.basic import BasicTranscriptCleaner
from cleaners.llm import LLMTranscriptPolisher


class Config:
    """API Configuration"""
    def __init__(self):
        self.transcripts_root = Path(os.getenv("TRANSCRIPTS_ROOT", "/home/eric/01-documents/01-vaults/04-transcripts"))
        self.hot_root = Path(os.getenv("HOT_ROOT", "/mnt/hot"))
        self.allow_languages = os.getenv("LANGS", "en,en-US,en-GB").split(",")
        self.api_host = os.getenv("API_HOST", "0.0.0.0")
        self.api_port = int(os.getenv("API_PORT", "8099"))
        self.api_keys = set([x for x in os.getenv("API_KEYS", "").split(",") if x])
        self.rate_limit_per_hour = int(os.getenv("RATE_LIMIT", "10"))
        self.free_space_gb_min = int(os.getenv("FREE_SPACE_GB_MIN", "5"))
        self.retention_days = int(os.getenv("RETENTION_DAYS", "90"))
        self.webhooks_enabled = os.getenv("WEBHOOKS", "0") == "1"
        self.timezone = os.getenv("TZ", "America/Denver")

        # CouchDB configuration (optional)
        self.couchdb_url = os.getenv("COUCHDB_URL", "")
        self.couchdb_database = os.getenv("COUCHDB_DATABASE", "transcripts")

        # Read credentials from systemd LoadCredential if available
        creds_dir = os.getenv("CREDENTIALS_DIRECTORY")
        if creds_dir:
            username_file = Path(creds_dir) / "couchdb-username"
            password_file = Path(creds_dir) / "couchdb-password"
            self.couchdb_username = username_file.read_text().strip() if username_file.exists() else ""
            self.couchdb_password = password_file.read_text().strip() if password_file.exists() else ""
        else:
            # Fallback to environment variables
            self.couchdb_username = os.getenv("COUCHDB_USERNAME", "")
            self.couchdb_password = os.getenv("COUCHDB_PASSWORD", "")

        # Log credential loading status (without exposing secrets)
        self._log_credential_status(creds_dir)

    def _log_credential_status(self, creds_dir: Optional[str]) -> None:
        """Log credential loading status for debugging"""
        logger.info("=" * 70)
        logger.info("CouchDB Configuration Status")
        logger.info("=" * 70)
        logger.info(f"CREDENTIALS_DIRECTORY: {creds_dir or 'NOT SET'}")
        logger.info(f"CouchDB URL: {self.couchdb_url or 'NOT SET'}")
        logger.info(f"CouchDB Database: {self.couchdb_database}")
        logger.info(f"CouchDB Username loaded: {'YES' if self.couchdb_username else 'NO'}")
        logger.info(f"CouchDB Password loaded: {'YES' if self.couchdb_password else 'NO'}")

        if creds_dir:
            creds_path = Path(creds_dir)
            logger.info(f"Credentials directory exists: {creds_path.exists()}")
            if creds_path.exists():
                try:
                    files = list(creds_path.iterdir())
                    logger.info(f"Files in credentials directory: {[f.name for f in files]}")
                except Exception as e:
                    logger.error(f"Error reading credentials directory: {e}")

        # Check if CouchDB sync will be enabled
        if self.couchdb_url and self.couchdb_username and self.couchdb_password:
            logger.info("✓ CouchDB sync is ENABLED")
        else:
            logger.warning("✗ CouchDB sync is DISABLED - missing configuration:")
            if not self.couchdb_url:
                logger.warning("  - COUCHDB_URL not set")
            if not self.couchdb_username:
                logger.warning("  - CouchDB username not loaded")
            if not self.couchdb_password:
                logger.warning("  - CouchDB password not loaded")
        logger.info("=" * 70)


class SubmitRequest(BaseModel):
    """Request model for transcript submission"""
    url: AnyHttpUrl
    format: str = Field(default="standard", pattern="^(standard|detailed)$")
    languages: Optional[List[str]] = None
    webhook_url: Optional[AnyHttpUrl] = None


class TranscriptTextRequest(BaseModel):
    """Request model for synchronous transcript-text endpoint"""
    url: str
    languages: Optional[List[str]] = None
    format: str = Field(default="basic", pattern="^(raw|basic|llm)$")


class JobStatus(BaseModel):
    """Job status model"""
    request_id: str
    kind: str  # "video" or "playlist"
    url: str
    status: str = "queued"  # queued, running, complete, error
    progress: float = 0.0
    message: str = ""
    out_dir: str = ""
    files: List[str] = Field(default_factory=list)
    created_at: str = ""
    updated_at: str = ""


class RateLimiter:
    """Simple in-memory rate limiter"""
    def __init__(self, per_hour: int):
        self.per_hour = per_hour
        self.requests = defaultdict(list)
    
    def allow(self, key: str) -> bool:
        """Check if request is allowed for this key"""
        now = time.time()
        window_start = now - 3600  # 1 hour ago
        
        # Clean old requests
        requests = self.requests[key]
        while requests and requests[0] < window_start:
            requests.pop(0)
        
        # Check limit
        if len(requests) >= self.per_hour:
            return False
        
        # Allow request
        requests.append(now)
        return True


class JobStore:
    """Simple file-based job store"""
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.by_id: Dict[str, JobStatus] = {}
        self.lock = asyncio.Lock()
    
    def new_request(self, kind: str, url: str) -> JobStatus:
        """Create new job request"""
        request_id = uuid.uuid4().hex[:12]
        request_dir = self.root / "api-requests" / request_id
        request_dir.mkdir(parents=True, exist_ok=True)
        
        now_iso = datetime.now().isoformat()
        status = JobStatus(
            request_id=request_id,
            kind=kind,
            url=url,
            status="queued",
            out_dir=str(request_dir),
            created_at=now_iso,
            updated_at=now_iso
        )
        
        self._persist(status)
        self.by_id[request_id] = status
        return status
    
    def load(self, request_id: str) -> Optional[JobStatus]:
        """Load job status from disk"""
        status_file = self.root / "api-requests" / request_id / "status.json"
        if status_file.exists():
            try:
                data = json.loads(status_file.read_text())
                return JobStatus.model_validate(data)
            except Exception:
                return None
        return None
    
    def list_recent(self, limit: int = 50) -> List[JobStatus]:
        """List recent jobs"""
        requests_dir = self.root / "api-requests"
        if not requests_dir.exists():
            return []
        
        jobs = []
        for job_dir in sorted(requests_dir.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
            if job_dir.is_dir():
                status = self.load(job_dir.name)
                if status:
                    jobs.append(status)
                    if len(jobs) >= limit:
                        break
        
        return jobs
    
    def update(self, job: JobStatus, **kwargs) -> JobStatus:
        """Update job status"""
        for key, value in kwargs.items():
            setattr(job, key, value)
        job.updated_at = datetime.now().isoformat()
        self._persist(job)
        return job

    def _persist(self, job: JobStatus) -> None:
        """Save job status to disk"""
        status_file = Path(job.out_dir) / "status.json"
        status_file.write_text(json.dumps(job.model_dump(), indent=2))
    
    def zip_result(self, request_id: str) -> Optional[Path]:
        """Create zip file of job results"""
        status = self.load(request_id)
        if not status or status.status != "complete":
            return None
        
        out_dir = Path(status.out_dir)
        zip_path = out_dir / "result.zip"
        
        if zip_path.exists():
            return zip_path
        
        # Create zip file
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for file_path_str in status.files:
                file_path = Path(file_path_str)
                if file_path.exists() and file_path.is_file():
                    # Add file to zip with relative path
                    arcname = file_path.name
                    zf.write(file_path, arcname)
        
        return zip_path if zip_path.exists() else None


# Initialize logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Initialize global objects
cfg = Config()
store = JobStore(cfg.transcripts_root)
limiter = RateLimiter(cfg.rate_limit_per_hour)
app = FastAPI(
    title="HWC Transcript API",
    description="YouTube transcript extraction API for HWC homeserver",
    version="1.0.0"
)

# Initialize transcript cleaners (once at module level for performance)
basic_cleaner = BasicTranscriptCleaner()
llm_polisher = LLMTranscriptPolisher()


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    logger.info("Starting HWC Transcript API...")
    logger.info("HWC Transcript API startup complete")


def require_api_key(request: Request) -> str:
    """Validate API key from request headers"""
    api_key = request.headers.get("x-api-key", "")
    
    # If no API keys configured, allow all requests
    if not cfg.api_keys:
        return "open"
    
    if api_key in cfg.api_keys:
        return api_key
    
    raise HTTPException(status_code=401, detail="Invalid or missing API key")


def free_space_gb(path: Path) -> float:
    """Get free space in GB for given path"""
    try:
        stat = shutil.disk_usage(path)
        return stat.free / (1024**3)
    except Exception:
        return 0.0


async def ensure_couchdb_database() -> bool:
    """
    Ensure the CouchDB database exists, creating it if necessary.

    Returns:
        bool: True if database exists or was created successfully
    """
    if not cfg.couchdb_url or not cfg.couchdb_username or not cfg.couchdb_password:
        logger.info("CouchDB not configured, skipping database check")
        return False

    try:
        auth = (cfg.couchdb_username, cfg.couchdb_password)
        db_url = f"{cfg.couchdb_url}/{cfg.couchdb_database}"

        async with httpx.AsyncClient(timeout=10) as client:
            # Check if database exists
            response = await client.get(db_url, auth=auth)

            if response.status_code == 200:
                logger.info(f"✓ CouchDB database '{cfg.couchdb_database}' exists")
                return True
            elif response.status_code == 404:
                # Database doesn't exist, create it
                logger.info(f"Creating CouchDB database '{cfg.couchdb_database}'...")
                create_response = await client.put(db_url, auth=auth)

                if create_response.status_code in (201, 202):
                    logger.info(f"✓ Successfully created CouchDB database '{cfg.couchdb_database}'")
                    return True
                else:
                    logger.error(f"Failed to create database: {create_response.status_code} - {create_response.text}")
                    return False
            else:
                logger.error(f"Unexpected response when checking database: {response.status_code}")
                return False

    except Exception as e:
        logger.error(f"Error ensuring CouchDB database exists: {e}")
        return False


async def sync_to_couchdb(file_path: Path) -> bool:
    """
    Sync transcript markdown file to CouchDB.

    Args:
        file_path: Path to the markdown file

    Returns:
        bool: True if successful, False otherwise
    """
    logger.info(f"Starting CouchDB sync for: {file_path}")

    # Check configuration
    if not cfg.couchdb_url:
        logger.warning(f"CouchDB sync skipped for {file_path.name}: COUCHDB_URL not configured")
        return False

    if not cfg.couchdb_username or not cfg.couchdb_password:
        logger.warning(f"CouchDB sync skipped for {file_path.name}: credentials not available")
        logger.warning(f"  - Username present: {bool(cfg.couchdb_username)}")
        logger.warning(f"  - Password present: {bool(cfg.couchdb_password)}")
        return False

    try:
        # Read the markdown file
        logger.debug(f"Reading file: {file_path}")
        content = file_path.read_text(encoding="utf-8")
        logger.debug(f"File size: {len(content)} bytes")

        # Create document ID from filename
        doc_id = file_path.stem
        logger.debug(f"Document ID: {doc_id}")

        # Prepare CouchDB document
        doc = {
            "_id": doc_id,
            "filename": file_path.name,
            "content": content,
            "created_at": datetime.now().isoformat(),
            "updated_at": datetime.now().isoformat(),
            "type": "transcript"
        }

        # Build CouchDB URL
        db_url = f"{cfg.couchdb_url}/{cfg.couchdb_database}/{doc_id}"
        logger.info(f"Syncing to CouchDB: {db_url}")
        auth = (cfg.couchdb_username, cfg.couchdb_password)

        async with httpx.AsyncClient(timeout=30) as client:
            # Check if document exists
            logger.debug("Checking if document exists in CouchDB...")
            try:
                existing = await client.get(db_url, auth=auth)
                logger.debug(f"GET response status: {existing.status_code}")
                if existing.status_code == 200:
                    # Document exists, update it
                    existing_doc = existing.json()
                    doc["_rev"] = existing_doc["_rev"]
                    logger.info(f"Document exists, updating with revision: {doc['_rev']}")
                elif existing.status_code == 404:
                    logger.info("Document does not exist, creating new document")
                else:
                    logger.warning(f"Unexpected status when checking document: {existing.status_code}")
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 404:
                    logger.info("Document does not exist (404), creating new document")
                else:
                    logger.warning(f"Error checking if document exists: {e}")
            except Exception as e:
                logger.warning(f"Error checking if document exists: {e}")

            # Put document to CouchDB
            logger.debug(f"Uploading document to CouchDB...")
            response = await client.put(db_url, json=doc, auth=auth)
            logger.debug(f"PUT response status: {response.status_code}")

            if response.status_code in (200, 201):
                result = response.json()
                logger.info(f"✓ Successfully synced {file_path.name} to CouchDB (rev: {result.get('rev', 'unknown')})")
                return True
            else:
                logger.error(f"CouchDB sync failed with status {response.status_code}")
                logger.error(f"Response: {response.text}")
                response.raise_for_status()
                return False

    except httpx.HTTPStatusError as e:
        logger.error(f"CouchDB HTTP error for {file_path.name}:")
        logger.error(f"  Status: {e.response.status_code}")
        logger.error(f"  Response: {e.response.text}")
        logger.error(f"  URL: {db_url}")
        return False
    except httpx.RequestError as e:
        logger.error(f"CouchDB connection error for {file_path.name}:")
        logger.error(f"  Error: {str(e)}")
        logger.error(f"  URL: {db_url}")
        return False
    except Exception as e:
        logger.error(f"CouchDB sync failed for {file_path.name}:")
        logger.error(f"  Error type: {type(e).__name__}")
        logger.error(f"  Error message: {str(e)}")
        import traceback
        logger.error(f"  Traceback:\n{traceback.format_exc()}")
        return False


async def process_job(request_id: str, url: str, format_mode: str, languages: List[str], webhook_url: Optional[str]):
    """Background job processor"""
    try:
        # Load job and update to running
        job_status = store.load(request_id)
        if not job_status:
            return

        store.update(job_status, status="running", progress=0.1)

        # Initialize transcript extractor
        transcript_config = TranscriptConfig()
        extractor = TranscriptExtractor(transcript_config)

        # Determine job type and process
        if extractor.is_playlist_url(url):
            # Process playlist
            playlist_dir, files = await extractor.process_playlist(
                url,
                cfg.transcripts_root / "playlists",
                languages,
                mode=format_mode
            )

            # Update status with results
            all_files = [playlist_dir / "00-playlist-overview.md"] + files
            store.update(
                job_status,
                status="complete",
                progress=1.0,
                files=[str(f) for f in all_files if f.exists()],
                message=f"Processed {len(files)} videos"
            )
        else:
            # Process single video - save directly to vault root
            file_path = await extractor.process_video(url, cfg.transcripts_root, languages, mode=format_mode)

            # Update status with result
            store.update(
                job_status,
                status="complete",
                progress=1.0,
                files=[str(file_path)],
                message="Video processed successfully"
            )

        # Send webhook notification if configured
        if webhook_url and cfg.webhooks_enabled:
            try:
                async with httpx.AsyncClient(timeout=10) as client:
                    final_status = store.load(request_id)
                    if final_status:
                        await client.post(str(webhook_url), json=final_status.model_dump())
            except Exception:
                pass  # Webhook failures shouldn't fail the job

    except Exception as e:
        # Update job with error
        job_status = store.load(request_id)
        if job_status:
            store.update(job_status, status="error", message=str(e))


@app.post("/api/transcript")
async def submit_transcript_request(request: Request, body: SubmitRequest, background_tasks: BackgroundTasks):
    """Submit a transcript extraction request"""
    # Validate API key and rate limit
    api_key = require_api_key(request)
    if not limiter.allow(api_key):
        raise HTTPException(status_code=429, detail="Rate limit exceeded (max 10 requests per hour)")
    
    # Validate YouTube URL
    transcript_config = TranscriptConfig()
    extractor = TranscriptExtractor(transcript_config)
    if not extractor.is_youtube_url(str(body.url)):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")
    
    # Check disk space
    if free_space_gb(cfg.transcripts_root) < cfg.free_space_gb_min:
        raise HTTPException(status_code=507, detail="Insufficient disk space")
    
    # Create job
    job_kind = "playlist" if "playlist" in str(body.url) else "video"
    status = store.new_request(job_kind, str(body.url))
    
    # Set up languages
    languages = body.languages if body.languages else cfg.allow_languages
    
    # Start background processing
    background_tasks.add_task(
        process_job,
        status.request_id,
        str(body.url),
        body.format,
        languages,
        str(body.webhook_url) if body.webhook_url else None
    )
    
    return {"request_id": status.request_id, "status": status.status}


@app.post("/api/transcript-text")
async def get_transcript_text(request: Request, body: TranscriptTextRequest, background_tasks: BackgroundTasks):
    """
    Synchronous transcript endpoint for iOS Shortcut integration.
    Returns the transcript text immediately instead of using job queue.
    """
    # Validate API key (optional, use same auth as /api/transcript)
    # Note: Not enforcing here to maintain compatibility with iOS Shortcut
    # Uncomment the following line to enforce API key:
    # require_api_key(request)

    # Initialize transcript extractor
    transcript_config = TranscriptConfig()
    extractor = TranscriptExtractor(transcript_config)

    # Validate URL
    if not extractor.is_youtube_url(body.url):
        raise HTTPException(status_code=400, detail="Invalid YouTube URL")

    # Reject playlist URLs
    if extractor.is_playlist_url(body.url):
        raise HTTPException(status_code=400, detail="Playlists not supported. Use /api/transcript for playlists.")

    # Set up languages
    languages = body.languages if body.languages else cfg.allow_languages

    # Create temporary directory for processing
    temp_dir = cfg.hot_root / "transcript-text" / uuid.uuid4().hex[:12]
    temp_dir.mkdir(parents=True, exist_ok=True)

    try:
        # Process the video
        markdown_path = await extractor.process_video(body.url, temp_dir, languages, mode="standard")

        # Read the generated markdown
        transcript_text = markdown_path.read_text(encoding="utf-8")

        # Get video info for title
        video_info = await extractor.get_video_info(body.url)
        title = video_info.get("title", "Unknown Title")

        # Apply cleaning based on format parameter
        format_used = body.format
        if body.format == "llm":
            try:
                logger.info(f"Applying LLM polishing to transcript: {title}")
                # Chain: basic cleaning first, then LLM polish
                cleaned = basic_cleaner.clean(transcript_text, title)
                transcript_text = llm_polisher.polish(cleaned, title)
                format_used = "llm"
                logger.info(f"LLM polishing completed for: {title}")
            except Exception as e:
                logger.error(f"LLM polishing failed: {e}, falling back to basic cleaning")
                transcript_text = basic_cleaner.clean(transcript_text, title)
                format_used = "basic_fallback"
        elif body.format == "basic":
            logger.info(f"Applying basic cleaning to transcript: {title}")
            transcript_text = basic_cleaner.clean(transcript_text, title)
            format_used = "basic"
        else:
            # raw format - no cleaning
            format_used = "raw"

        # Copy to permanent location in vault root
        vault_root = cfg.transcripts_root
        vault_root.mkdir(parents=True, exist_ok=True)
        dest_path = vault_root / markdown_path.name
        shutil.copy2(markdown_path, dest_path)
        vault_path_str = str(dest_path)

        # Return response matching iOS Shortcut expectations
        return {
            "title": title,
            "text": transcript_text,
            "vault_path": vault_path_str,
            "format_used": format_used
        }

    except Exception as e:
        logger.error(f"Error processing transcript-text request: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to process transcript: {str(e)}")

    finally:
        # Clean up temporary directory
        try:
            if temp_dir.exists():
                shutil.rmtree(temp_dir)
        except Exception as e:
            logger.warning(f"Failed to clean up temp directory {temp_dir}: {e}")


@app.get("/api/status/{request_id}")
async def get_job_status(request_id: str):
    """Get job status"""
    status = store.load(request_id)
    if not status:
        raise HTTPException(status_code=404, detail="Job not found")

    return JSONResponse(status.model_dump())


@app.get("/api/download/{request_id}")
async def download_results(request_id: str):
    """Download job results as zip file"""
    zip_path = store.zip_result(request_id)
    if not zip_path:
        raise HTTPException(status_code=404, detail="Results not available")
    
    async def file_generator():
        with open(zip_path, "rb") as f:
            while chunk := f.read(1024 * 1024):  # 1MB chunks
                yield chunk
    
    return StreamingResponse(
        file_generator(),
        media_type="application/zip",
        headers={"Content-Disposition": f'attachment; filename="{request_id}.zip"'}
    )


@app.get("/api/list")
async def list_jobs():
    """List recent jobs"""
    jobs = store.list_recent(100)
    return {"jobs": [job.model_dump() for job in jobs]}


@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "disk_space_gb": free_space_gb(cfg.transcripts_root)
    }


@app.get("/health/couchdb")
async def couchdb_health_check():
    """CouchDB connectivity and authentication check"""
    result = {
        "timestamp": datetime.now().isoformat(),
        "configured": False,
        "accessible": False,
        "authenticated": False,
        "database_exists": False,
        "error": None
    }

    # Check if CouchDB is configured
    if not cfg.couchdb_url:
        result["error"] = "COUCHDB_URL not configured"
        return result

    result["configured"] = True

    if not cfg.couchdb_username or not cfg.couchdb_password:
        result["error"] = "CouchDB credentials not loaded"
        return result

    try:
        auth = (cfg.couchdb_username, cfg.couchdb_password)

        async with httpx.AsyncClient(timeout=10) as client:
            # Test basic connectivity
            try:
                response = await client.get(f"{cfg.couchdb_url}/", auth=auth)
                if response.status_code == 200:
                    result["accessible"] = True
                    result["authenticated"] = True
                    couchdb_info = response.json()
                    result["couchdb_version"] = couchdb_info.get("version")
                else:
                    result["error"] = f"CouchDB returned status {response.status_code}"
                    return result
            except httpx.RequestError as e:
                result["error"] = f"Connection error: {str(e)}"
                return result

            # Check if database exists
            try:
                db_response = await client.get(f"{cfg.couchdb_url}/{cfg.couchdb_database}", auth=auth)
                if db_response.status_code == 200:
                    result["database_exists"] = True
                    db_info = db_response.json()
                    result["database_doc_count"] = db_info.get("doc_count")
                    result["database_name"] = db_info.get("db_name")
                elif db_response.status_code == 404:
                    result["error"] = f"Database '{cfg.couchdb_database}' does not exist"
                else:
                    result["error"] = f"Database check returned status {db_response.status_code}"
            except Exception as e:
                result["error"] = f"Database check error: {str(e)}"

    except Exception as e:
        result["error"] = f"Unexpected error: {str(e)}"

    return result


@app.get("/")
async def root():
    """Root endpoint with API info"""
    return {
        "name": "HWC Transcript API",
        "version": "1.0.0",
        "endpoints": {
            "simple_transcript": "POST /api/transcript-text",
            "submit": "POST /api/transcript",
            "status": "GET /api/status/{request_id}",
            "download": "GET /api/download/{request_id}",
            "list": "GET /api/list",
            "health": "GET /health",
            "couchdb_health": "GET /health/couchdb"
        },
        "couchdb_sync": bool(cfg.couchdb_url and cfg.couchdb_username and cfg.couchdb_password)
    }


if __name__ == "__main__":
    uvicorn.run(
        app,
        host=cfg.api_host,
        port=cfg.api_port,
        workers=1,
        log_level="info"
    )
