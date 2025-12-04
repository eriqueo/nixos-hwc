#!/usr/bin/env python3
"""
HWC Local Workflows API
Exposes AI-powered workflows via HTTP API
"""
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from contextlib import asynccontextmanager
import argparse
import logging
import time
from datetime import datetime
import models
from models import *
import workflows
from workflows import WorkflowExecutor


# Global state
executor: WorkflowExecutor = None
start_time = time.time()
request_count = 0


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle"""
    global executor
    executor = WorkflowExecutor()
    logging.info("Workflows API started")
    yield
    await executor.close()
    logging.info("Workflows API shutting down")


# Create FastAPI app
app = FastAPI(
    title="HWC Local Workflows API",
    version="1.0.0",
    description="HTTP API for AI-powered local workflows",
    lifespan=lifespan
)


@app.middleware("http")
async def count_requests(request: Request, call_next):
    """Count incoming requests"""
    global request_count
    request_count += 1
    response = await call_next(request)
    return response


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "ok",
        "service": "hwc-local-workflows-api",
        "version": "1.0.0"
    }


@app.post("/api/workflows/chat")
async def chat_endpoint(req: ChatRequest):
    """
    Chat with AI model, optionally with context

    Supports streaming (SSE) or JSON response
    """
    if req.stream:
        # Stream response via SSE
        async def generate():
            async for chunk in executor.chat(req):
                yield f"data: {chunk}\n\n"
            yield "data: [DONE]\n\n"

        return StreamingResponse(
            generate(),
            media_type="text/event-stream"
        )
    else:
        # Collect full response
        response_parts = []
        async for chunk in executor.chat(req):
            response_parts.append(chunk)

        full_response = "".join(response_parts)
        return ChatResponse(
            response=full_response,
            model=req.model,
            tokens=None  # TODO: Extract from Ollama response
        )


@app.post("/api/workflows/cleanup", response_model=CleanupResponse)
async def cleanup_endpoint(req: CleanupRequest):
    """
    Analyze directory and suggest/execute file organization

    Use dry_run=true to preview actions without executing
    """
    try:
        result = await executor.cleanup(req)
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logging.error(f"Cleanup workflow error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/workflows/journal", response_model=JournalResponse)
async def journal_endpoint(req: JournalRequest):
    """
    Generate daily journal entry from system logs and metrics

    Saves to ~/Documents/HWC-AI-Journal/ if directory exists
    """
    try:
        result = await executor.journal(req)
        return result
    except Exception as e:
        logging.error(f"Journal workflow error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/workflows/autodoc", response_model=AutodocResponse)
async def autodoc_endpoint(req: AutodocRequest):
    """
    Generate documentation for a code file

    Supports technical or user-friendly styles
    """
    try:
        result = await executor.autodoc(req)
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logging.error(f"Autodoc workflow error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/workflows/status", response_model=StatusResponse)
async def status_endpoint():
    """
    Get status of all workflows and available models
    """
    uptime_seconds = int(time.time() - start_time)
    uptime_hours = uptime_seconds / 3600

    # Query Ollama for available models
    models_info = {}
    try:
        import httpx
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get("http://127.0.0.1:11434/api/tags")
            if response.status_code == 200:
                data = response.json()
                for model in data.get("models", []):
                    name = model.get("name", "unknown")
                    size = model.get("size", 0)
                    size_gb = size / (1024**3)
                    models_info[name] = ModelInfo(
                        name=name,
                        status="available",
                        size=f"{size_gb:.1f}GB"
                    )
    except:
        # Ollama not available
        pass

    # TODO: Get actual workflow status from systemd timers
    workflows_info = {
        "file_cleanup": WorkflowInfo(
            name="file_cleanup",
            enabled=True,
            last_run=None,  # TODO: Query systemd
            next_run=None,
            runs_count=0,
            status=WorkflowStatus.PENDING,
            last_error=None
        ),
        "journaling": WorkflowInfo(
            name="journaling",
            enabled=True,
            last_run=None,
            next_run=None,
            runs_count=0,
            status=WorkflowStatus.PENDING,
            last_error=None
        ),
        "autodoc": WorkflowInfo(
            name="autodoc",
            enabled=True,
            last_run=None,
            next_run=None,
            runs_count=0,
            status=WorkflowStatus.PENDING,
            last_error=None
        ),
        "chat": WorkflowInfo(
            name="chat",
            enabled=True,
            last_run=None,
            next_run=None,
            runs_count=request_count,  # Use API request count
            status=WorkflowStatus.COMPLETED,
            last_error=None
        )
    }

    return StatusResponse(
        version="1.0.0",
        workflows=workflows_info,
        models=models_info,
        api_uptime=f"{uptime_hours:.1f}h",
        requests_processed=request_count
    )


if __name__ == "__main__":
    import uvicorn

    # Setup logging
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
    )

    # Parse arguments
    parser = argparse.ArgumentParser(description="HWC Local Workflows API")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind to")
    parser.add_argument("--port", type=int, default=6021, help="Port to bind to")
    args = parser.parse_args()

    # Run server
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        log_level="info"
    )
