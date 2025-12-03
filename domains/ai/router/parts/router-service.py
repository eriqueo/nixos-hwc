#!/usr/bin/env python3
"""
AI Model Router - Intelligent routing between local Ollama and cloud APIs
Ollama-compatible API format for transparent integration
"""

import asyncio
import json
import logging
import os
import time
from typing import Optional, Dict, Any
from dataclasses import dataclass

from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import StreamingResponse, JSONResponse
import httpx
import uvicorn


# Configuration from environment
HOST = os.getenv("ROUTER_HOST", "127.0.0.1")
PORT = int(os.getenv("ROUTER_PORT", "11435"))
OLLAMA_ENDPOINT = os.getenv("OLLAMA_ENDPOINT", "http://127.0.0.1:11434")
STRATEGY = os.getenv("ROUTING_STRATEGY", "local-first")
LOCAL_TIMEOUT = int(os.getenv("LOCAL_TIMEOUT", "30"))
CLOUD_TIMEOUT = int(os.getenv("CLOUD_TIMEOUT", "60"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
LOG_REQUESTS = os.getenv("LOG_REQUESTS", "true").lower() == "true"

# Cloud API configuration
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_ENDPOINT = os.getenv("OPENAI_API_ENDPOINT", "https://api.openai.com/v1")
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
ANTHROPIC_ENDPOINT = os.getenv("ANTHROPIC_API_ENDPOINT", "https://api.anthropic.com/v1")

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(title="AI Model Router", version="1.0.0")


@dataclass
class RoutingDecision:
    """Decision about where to route a request"""
    target: str  # "local" or "cloud"
    endpoint: str
    model: str
    reason: str


class ModelRouter:
    """Intelligent router for AI model requests"""

    def __init__(self):
        self.stats = {
            "total_requests": 0,
            "local_requests": 0,
            "cloud_requests": 0,
            "local_failures": 0,
            "cloud_failures": 0,
        }

    async def check_local_available(self) -> bool:
        """Check if local Ollama is available"""
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(f"{OLLAMA_ENDPOINT}/api/tags", timeout=5.0)
                return response.status_code == 200
        except Exception as e:
            logger.debug(f"Local Ollama not available: {e}")
            return False

    def decide_route(self, model: str, request_data: Dict[str, Any]) -> RoutingDecision:
        """Decide where to route the request"""
        self.stats["total_requests"] += 1

        # Check if model has explicit cloud prefix (openai:, anthropic:)
        if ":" in model:
            provider, cloud_model = model.split(":", 1)
            if provider == "openai" and OPENAI_API_KEY:
                return RoutingDecision(
                    target="cloud",
                    endpoint=OPENAI_ENDPOINT,
                    model=cloud_model,
                    reason=f"Explicit cloud routing: {provider}"
                )
            elif provider == "anthropic" and ANTHROPIC_API_KEY:
                return RoutingDecision(
                    target="cloud",
                    endpoint=ANTHROPIC_ENDPOINT,
                    model=cloud_model,
                    reason=f"Explicit cloud routing: {provider}"
                )

        # Default: try local first (local-first strategy)
        if STRATEGY == "local-first":
            return RoutingDecision(
                target="local",
                endpoint=OLLAMA_ENDPOINT,
                model=model,
                reason="Local-first strategy"
            )

        # Fallback to local
        return RoutingDecision(
            target="local",
            endpoint=OLLAMA_ENDPOINT,
            model=model,
            reason="Default to local"
        )

    async def route_to_local(self, path: str, method: str, data: Dict[str, Any], stream: bool = False):
        """Route request to local Ollama"""
        self.stats["local_requests"] += 1

        try:
            url = f"{OLLAMA_ENDPOINT}{path}"
            async with httpx.AsyncClient() as client:
                if stream:
                    async with client.stream(
                        method,
                        url,
                        json=data,
                        timeout=LOCAL_TIMEOUT
                    ) as response:
                        response.raise_for_status()
                        async for chunk in response.aiter_bytes():
                            yield chunk
                else:
                    response = await client.request(
                        method,
                        url,
                        json=data,
                        timeout=LOCAL_TIMEOUT
                    )
                    response.raise_for_status()
                    yield response.json()
        except Exception as e:
            self.stats["local_failures"] += 1
            logger.error(f"Local routing failed: {e}")
            raise

    async def route_to_cloud(self, provider: str, path: str, data: Dict[str, Any], stream: bool = False):
        """Route request to cloud API (not implemented in this basic version)"""
        self.stats["cloud_requests"] += 1

        # This is a placeholder - full cloud integration would require
        # translating between Ollama format and cloud provider formats
        raise HTTPException(
            status_code=501,
            detail="Cloud routing not yet implemented. Use explicit local models or wait for full cloud integration."
        )


router = ModelRouter()


@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "ai-model-router",
        "version": "1.0.0",
        "strategy": STRATEGY,
    }


@app.get("/api/tags")
async def list_models():
    """List available models (proxies to Ollama)"""
    try:
        async for response in router.route_to_local("/api/tags", "GET", {}):
            return response
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Failed to list models: {str(e)}")


@app.post("/api/generate")
async def generate(request: Request):
    """Generate completion (Ollama-compatible endpoint)"""
    data = await request.json()
    model = data.get("model", "")
    stream = data.get("stream", False)

    if LOG_REQUESTS:
        logger.info(f"Generate request: model={model}, stream={stream}")

    decision = router.decide_route(model, data)

    if LOG_REQUESTS:
        logger.info(f"Routing decision: {decision.target} ({decision.reason})")

    try:
        if decision.target == "local":
            if stream:
                return StreamingResponse(
                    router.route_to_local("/api/generate", "POST", data, stream=True),
                    media_type="application/x-ndjson"
                )
            else:
                async for response in router.route_to_local("/api/generate", "POST", data):
                    return JSONResponse(response)
        else:
            # Cloud routing
            async for response in router.route_to_cloud(decision.target, "/api/generate", data, stream):
                return JSONResponse(response)
    except Exception as e:
        logger.error(f"Request failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/chat")
async def chat(request: Request):
    """Chat completion (Ollama-compatible endpoint)"""
    data = await request.json()
    model = data.get("model", "")
    stream = data.get("stream", False)

    if LOG_REQUESTS:
        logger.info(f"Chat request: model={model}, stream={stream}")

    decision = router.decide_route(model, data)

    if LOG_REQUESTS:
        logger.info(f"Routing decision: {decision.target} ({decision.reason})")

    try:
        if decision.target == "local":
            if stream:
                return StreamingResponse(
                    router.route_to_local("/api/chat", "POST", data, stream=True),
                    media_type="application/x-ndjson"
                )
            else:
                async for response in router.route_to_local("/api/chat", "POST", data):
                    return JSONResponse(response)
        else:
            # Cloud routing
            async for response in router.route_to_cloud(decision.target, "/api/chat", data, stream):
                return JSONResponse(response)
    except Exception as e:
        logger.error(f"Request failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/stats")
async def stats():
    """Get router statistics"""
    return {
        "stats": router.stats,
        "ollama_available": await router.check_local_available(),
        "strategy": STRATEGY,
    }


if __name__ == "__main__":
    logger.info(f"Starting AI Model Router on {HOST}:{PORT}")
    logger.info(f"Strategy: {STRATEGY}")
    logger.info(f"Local endpoint: {OLLAMA_ENDPOINT}")

    uvicorn.run(
        app,
        host=HOST,
        port=PORT,
        log_level=LOG_LEVEL.lower()
    )
