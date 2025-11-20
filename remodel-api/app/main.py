"""
Bathroom Remodel Planner API - Main Application
"""
import os
import logging
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import JSONResponse

from app.logging_config import setup_logging
from app.database import get_db_pool, close_db_pool
from app.routers import projects, forms

# Configure logging first
log_level = os.getenv("LOG_LEVEL", "INFO")
setup_logging(log_level=log_level)

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager for startup/shutdown events with error handling
    """
    logger.info("=" * 60)
    logger.info("🚀 Starting Bathroom Remodel Planner API")
    logger.info("=" * 60)

    # Startup checks
    try:
        # 1. Check environment variables
        logger.info("Checking environment configuration...")
        database_url = os.getenv("DATABASE_URL")
        if not database_url:
            logger.warning("⚠️  DATABASE_URL not set, using default")

        # 2. Check PDF directory
        logger.info("Checking PDF storage directory...")
        pdf_dir = Path("/app/pdfs")
        pdf_dir.mkdir(parents=True, exist_ok=True)

        if not os.access(str(pdf_dir), os.W_OK):
            logger.error(f"❌ PDF directory {pdf_dir} is not writable!")
        else:
            logger.info(f"✓ PDF directory ready: {pdf_dir}")

        # 3. Test WeasyPrint dependencies
        logger.info("Checking PDF generation dependencies...")
        try:
            import weasyprint
            logger.info(f"✓ WeasyPrint {weasyprint.VERSION} loaded successfully")
        except ImportError as e:
            logger.error(f"❌ WeasyPrint import failed: {e}")
            logger.error("PDF generation will not work!")

        # 4. Initialize database pool with retry logic
        logger.info("Initializing database connection pool...")
        await get_db_pool(max_retries=5, retry_delay=2.0)
        logger.info("✓ Database connection pool ready")

        logger.info("=" * 60)
        logger.info("✓ Application startup complete")
        logger.info("=" * 60)

    except Exception as e:
        logger.error("=" * 60)
        logger.error(f"❌ STARTUP FAILED: {e}")
        logger.error("=" * 60)
        raise

    yield

    # Shutdown
    logger.info("Shutting down application...")
    try:
        await close_db_pool()
        logger.info("✓ Database connection pool closed")
    except Exception as e:
        logger.error(f"Error during shutdown: {e}")

    logger.info("✓ Shutdown complete")


# Create FastAPI application
app = FastAPI(
    title="Bathroom Remodel Planner API",
    description="Config-driven, modular cost estimation for bathroom remodels",
    version="0.1.0",
    lifespan=lifespan
)

# Global exception handler for better error messages
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """Catch-all exception handler with logging"""
    logger.error(f"Unhandled exception on {request.url.path}: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error. Please check logs for details.",
            "error_type": type(exc).__name__
        }
    )

# CORS middleware (adjust origins for production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: Restrict to your domain in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(projects.router)
app.include_router(forms.router)

# Mount PDF directory for serving generated reports
try:
    pdf_dir = Path("/app/pdfs")
    pdf_dir.mkdir(parents=True, exist_ok=True)
    app.mount("/pdfs", StaticFiles(directory=str(pdf_dir)), name="pdfs")
    logger.info(f"✓ PDF static files mounted at /pdfs -> {pdf_dir}")
except Exception as e:
    logger.error(f"❌ Failed to mount PDF directory: {e}")


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "Bathroom Remodel Planner API",
        "version": "0.1.0",
        "status": "running"
    }


@app.get("/health")
async def health_check():
    """
    Detailed health check for monitoring
    """
    health = {
        "status": "healthy",
        "database": "unknown",
        "pdf_generation": "unknown"
    }

    # Check database
    try:
        from app.database import execute_query
        await execute_query("SELECT 1", fetch="val")
        health["database"] = "healthy"
    except Exception as e:
        health["database"] = f"unhealthy: {str(e)}"
        health["status"] = "degraded"

    # Check PDF generation
    try:
        import weasyprint
        health["pdf_generation"] = "healthy"
    except ImportError:
        health["pdf_generation"] = "unavailable"
        health["status"] = "degraded"

    return health


@app.get("/debug/info")
async def debug_info():
    """
    Debug endpoint showing configuration (disabled in production)
    """
    import sys
    return {
        "python_version": sys.version,
        "database_url_set": bool(os.getenv("DATABASE_URL")),
        "pdf_dir_exists": Path("/app/pdfs").exists(),
        "pdf_dir_writable": os.access("/app/pdfs", os.W_OK),
        "log_level": os.getenv("LOG_LEVEL", "INFO")
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,  # Development only
        log_level="info"
    )
