#!/usr/bin/env python3
"""
HWC AI Agent - Secure HTTP API for whitelisted command execution
Provides a safe, auditable interface for Open WebUI to execute system commands
"""
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
import subprocess
import shlex
import time
import json
import logging
import argparse
from typing import List

app = FastAPI(title="HWC AI Agent", version="1.0.0")

# Configuration (will be overridden by command-line args)
ALLOWED = [
    "podman ps",
    "podman logs",
    "systemctl status",
    "journalctl -n",
    "ls",
    "cat"
]
AUDIT_LOG = "/var/log/hwc-ai/agent-audit.log"

# Setup logging
logging.basicConfig(
    filename=AUDIT_LOG,
    level=logging.INFO,
    format="%(asctime)s %(message)s"
)

class Cmd(BaseModel):
    cmd: str

def is_allowed(cmd: str) -> bool:
    """Check if command is in the allowlist"""
    cmd_stripped = cmd.strip()
    for allowed in ALLOWED:
        if cmd_stripped.startswith(allowed):
            return True
    return False

def has_dangerous_operators(cmd: str) -> bool:
    """Check for dangerous shell operators"""
    dangerous = ['--rm', '--force', ';', '&&', '`', '$(', '|', '>', '<']
    for op in dangerous:
        if op in cmd:
            return True
    return False

@app.get("/")
async def root():
    """Health check endpoint"""
    return {"status": "ok", "service": "hwc-ai-agent"}

@app.get("/discovery")
async def discovery():
    """MCP and AI services discovery endpoint"""
    return {
        "version": "1.0",
        "mcp_servers": [
            {
                "name": "nixos-filesystem",
                "description": "Filesystem access to ~/.nixos and MCP drafts",
                "type": "filesystem",
                "stdio_service": "mcp-filesystem-nixos.service",
                "http_proxy": {
                    "enabled": True,
                    "url": "http://127.0.0.1:6001/sse",
                    "public_url": "https://hwc.ocelot-wahoo.ts.net/mcp",
                    "protocol": "SSE"
                },
                "allowed_directories": [
                    "/home/eric/.nixos",
                    "/home/eric/.nixos-mcp-drafts"
                ],
                "capabilities": ["read_file", "write_file", "list_directory", "create_directory"]
            }
        ],
        "ai_services": {
            "ollama": {
                "enabled": True,
                "url": "http://127.0.0.1:11434",
                "models": ["qwen2.5-coder:3b", "phi3:3.8b", "llama3.2:3b"]
            },
            "router": {
                "enabled": True,
                "url": "http://127.0.0.1:11435",
                "strategy": "local-first",
                "description": "Intelligent routing between local Ollama and cloud APIs"
            },
            "open_webui": {
                "enabled": True,
                "url": "http://127.0.0.1:3001",
                "public_url": "https://hwc.ocelot-wahoo.ts.net:3443"
            },
            "local_workflows": {
                "file_cleanup": {
                    "enabled": True,
                    "schedule": "every 30 minutes",
                    "model": "qwen2.5-coder:3b"
                },
                "journaling": {
                    "enabled": True,
                    "schedule": "daily at 02:00",
                    "model": "llama3.2:3b"
                },
                "auto_doc": {
                    "enabled": True,
                    "model": "qwen2.5-coder:3b"
                },
                "chat_cli": {
                    "enabled": True,
                    "model": "llama3:8b"
                }
            }
        },
        "agent": {
            "url": "http://127.0.0.1:6020",
            "capabilities": ["execute_commands", "mcp_discovery"],
            "allowed_commands": ALLOWED
        }
    }

@app.post("/run")
async def run_command(c: Cmd, req: Request):
    """Execute a whitelisted command and return output"""
    # Validate command is allowed
    if not is_allowed(c.cmd):
        logging.warning(json.dumps({
            "remote": req.client.host,
            "cmd": c.cmd,
            "status": "rejected",
            "reason": "not_allowed"
        }))
        raise HTTPException(status_code=403, detail="Command not allowed")
    
    # Check for dangerous operators
    if has_dangerous_operators(c.cmd):
        logging.warning(json.dumps({
            "remote": req.client.host,
            "cmd": c.cmd,
            "status": "rejected",
            "reason": "dangerous_operator"
        }))
        raise HTTPException(status_code=403, detail="Dangerous operator blocked")
    
    # Execute command
    try:
        proc = subprocess.run(
            shlex.split(c.cmd),
            capture_output=True,
            text=True,
            timeout=30
        )
        
        # Truncate output to prevent excessive data
        out = proc.stdout[:5000]
        err = proc.stderr[:1000]
        
        # Log execution
        logging.info(json.dumps({
            "remote": req.client.host,
            "cmd": c.cmd,
            "returncode": proc.returncode,
            "status": "executed"
        }))
        
        return {
            "success": proc.returncode == 0,
            "output": out,
            "error": err,
            "returncode": proc.returncode
        }
    
    except subprocess.TimeoutExpired:
        logging.error(json.dumps({
            "remote": req.client.host,
            "cmd": c.cmd,
            "error": "timeout"
        }))
        raise HTTPException(status_code=500, detail="Command timeout")
    
    except Exception as e:
        logging.error(json.dumps({
            "remote": req.client.host,
            "cmd": c.cmd,
            "error": str(e)
        }))
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    parser = argparse.ArgumentParser(description="HWC AI Agent")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind to")
    parser.add_argument("--port", type=int, default=6020, help="Port to bind to")
    args = parser.parse_args()
    
    uvicorn.run(app, host=args.host, port=args.port)
