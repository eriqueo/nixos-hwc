"""
Bathroom Remodel Planner API - Main Application
"""
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.database import get_db_pool, close_db_pool
from app.routers import projects, forms


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Lifespan context manager for startup/shutdown events
    """
    # Startup: Initialize database pool
    await get_db_pool()
    print("✓ Database connection pool initialized")

    yield

    # Shutdown: Close database pool
    await close_db_pool()
    print("✓ Database connection pool closed")


# Create FastAPI application
app = FastAPI(
    title="Bathroom Remodel Planner API",
    description="Config-driven, modular cost estimation for bathroom remodels",
    version="0.1.0",
    lifespan=lifespan
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
pdf_dir = Path("/app/pdfs")
pdf_dir.mkdir(parents=True, exist_ok=True)
app.mount("/pdfs", StaticFiles(directory=str(pdf_dir)), name="pdfs")


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
    """Health check for monitoring"""
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True  # Development only
    )
