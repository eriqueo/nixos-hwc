"""
Workflow execution logic for Local Workflows API
"""
import os
import json
import httpx
import asyncio
from datetime import datetime
from pathlib import Path
from typing import AsyncIterator, Dict, List, Any
import models
from models import *
import prompts
from prompts import *


class WorkflowExecutor:
    """Executes AI workflows using Ollama"""

    def __init__(self, ollama_url: str = "http://127.0.0.1:11434"):
        self.ollama_url = ollama_url
        self.client = httpx.AsyncClient(timeout=300.0)  # 5 min timeout for long operations

    async def chat(self, request: ChatRequest) -> AsyncIterator[str]:
        """Execute chat workflow with streaming"""
        system_prompt = request.system_prompt or SYSTEM_PROMPTS["chat"]

        # Build Ollama request
        ollama_request = {
            "model": request.model,
            "prompt": request.message,
            "system": system_prompt,
            "stream": request.stream
        }

        # Add context if provided
        if request.context:
            ollama_request["prompt"] = f"Context:\n{request.context}\n\nQuestion: {request.message}"

        # Stream response from Ollama
        async with self.client.stream(
            "POST",
            f"{self.ollama_url}/api/generate",
            json=ollama_request
        ) as response:
            async for line in response.aiter_lines():
                if line:
                    try:
                        data = json.loads(line)
                        if "response" in data:
                            yield data["response"]
                        if data.get("done", False):
                            break
                    except json.JSONDecodeError:
                        continue

    async def cleanup(self, request: CleanupRequest) -> CleanupResponse:
        """Execute file cleanup workflow"""
        directory = Path(request.directory)

        if not directory.exists():
            raise ValueError(f"Directory not found: {directory}")

        # List files in directory
        files = [f.name for f in directory.iterdir() if f.is_file()]

        # Build prompt
        prompt = build_cleanup_prompt(str(directory), files)

        # Get recommendations from Ollama
        ollama_request = {
            "model": "qwen2.5-coder:3b",
            "prompt": prompt,
            "stream": False
        }

        response = await self.client.post(
            f"{self.ollama_url}/api/generate",
            json=ollama_request
        )
        result = response.json()

        # Parse response and extract actions
        actions = self._parse_cleanup_response(result.get("response", ""), directory)

        # Execute actions if not dry run
        if not request.dry_run:
            for action in actions:
                if action.action == "move" and action.destination:
                    self._execute_move(action.file, action.destination)

        return CleanupResponse(
            directory=str(directory),
            files_analyzed=len(files),
            actions=actions,
            dry_run=request.dry_run
        )

    def _parse_cleanup_response(self, response: str, directory: Path) -> List[CleanupAction]:
        """Parse Ollama response to extract cleanup actions"""
        actions = []
        current_file = None
        current_action = {}

        for line in response.split("\n"):
            line = line.strip()
            if line.startswith("File:"):
                if current_file and current_action:
                    actions.append(CleanupAction(**current_action))
                current_file = line.replace("File:", "").strip()
                current_action = {"file": str(directory / current_file)}
            elif line.startswith("Action:"):
                current_action["action"] = line.replace("Action:", "").strip()
            elif line.startswith("Destination:"):
                current_action["destination"] = line.replace("Destination:", "").strip()
            elif line.startswith("Reason:"):
                current_action["reason"] = line.replace("Reason:", "").strip()

        # Add last action
        if current_file and current_action:
            actions.append(CleanupAction(**current_action))

        return actions

    def _execute_move(self, source: str, destination: str):
        """Execute file move operation"""
        import shutil
        src = Path(source)
        dst = Path(destination)

        # Create destination directory if needed
        dst.parent.mkdir(parents=True, exist_ok=True)

        # Move file
        shutil.move(str(src), str(dst))

    async def journal(self, request: JournalRequest) -> JournalResponse:
        """Execute journaling workflow"""
        # Gather logs and metrics
        logs = await self._gather_logs(request.sources, request.time_range)
        metrics = await self._gather_metrics() if request.include_metrics else {}

        # Build prompt
        prompt = build_journal_prompt(logs, metrics)

        # Generate journal with Ollama
        ollama_request = {
            "model": "llama3.2:3b",
            "prompt": prompt,
            "stream": False
        }

        response = await self.client.post(
            f"{self.ollama_url}/api/generate",
            json=ollama_request
        )
        result = response.json()

        content = result.get("response", "")
        timestamp = datetime.now().isoformat()

        # Save to file if configured
        output_path = None
        journal_dir = Path(os.getenv("JOURNAL_DIR", "~/Documents/HWC-AI-Journal")).expanduser()
        if journal_dir.exists():
            filename = f"journal-{datetime.now().strftime('%Y-%m-%d')}.md"
            output_path = journal_dir / filename
            output_path.write_text(f"# Journal - {datetime.now().strftime('%Y-%m-%d')}\n\n{content}")

        return JournalResponse(
            content=content,
            output_path=str(output_path) if output_path else None,
            timestamp=timestamp
        )

    async def _gather_logs(self, sources: List[str], time_range: str) -> Dict[str, str]:
        """Gather logs from specified sources"""
        logs = {}

        if "systemd-journal" in sources:
            # Get recent systemd logs
            proc = await asyncio.create_subprocess_exec(
                "journalctl", "-n", "100", "--no-pager",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            stdout, _ = await proc.communicate()
            logs["summary"] = stdout.decode()[:2000]  # Truncate

        if "container-logs" in sources:
            # Get container status
            proc = await asyncio.create_subprocess_exec(
                "podman", "ps", "--format", "{{.Names}}",
                stdout=asyncio.subprocess.PIPE
            )
            stdout, _ = await proc.communicate()
            logs["containers"] = stdout.decode()

        return logs

    async def _gather_metrics(self) -> Dict[str, str]:
        """Gather system metrics"""
        metrics = {}

        # CPU usage
        try:
            with open("/proc/loadavg") as f:
                load = f.read().split()[0]
                metrics["cpu"] = f"Load: {load}"
        except:
            metrics["cpu"] = "N/A"

        # Memory usage
        try:
            with open("/proc/meminfo") as f:
                lines = f.readlines()
                total = int([l for l in lines if "MemTotal" in l][0].split()[1])
                available = int([l for l in lines if "MemAvailable" in l][0].split()[1])
                used_pct = (1 - available / total) * 100
                metrics["memory"] = f"{used_pct:.1f}% used"
        except:
            metrics["memory"] = "N/A"

        # Disk usage
        import shutil
        try:
            usage = shutil.disk_usage("/")
            used_pct = (usage.used / usage.total) * 100
            metrics["disk"] = f"{used_pct:.1f}% used"
        except:
            metrics["disk"] = "N/A"

        return metrics

    async def autodoc(self, request: AutodocRequest) -> AutodocResponse:
        """Execute autodoc workflow"""
        file_path = Path(request.file_path)

        if not file_path.exists():
            raise ValueError(f"File not found: {file_path}")

        # Read file content
        content = file_path.read_text()

        # Build prompt
        prompt = build_autodoc_prompt(str(file_path), content, request.style)

        # Generate documentation with Ollama
        ollama_request = {
            "model": "qwen2.5-coder:3b",
            "prompt": prompt,
            "stream": False
        }

        response = await self.client.post(
            f"{self.ollama_url}/api/generate",
            json=ollama_request
        )
        result = response.json()

        documentation = result.get("response", "")

        # Extract sections
        sections = []
        for line in documentation.split("\n"):
            if line.startswith("#"):
                sections.append(line.strip("# ").strip())

        return AutodocResponse(
            documentation=documentation,
            file_path=str(file_path),
            sections=sections
        )

    async def close(self):
        """Close HTTP client"""
        await self.client.aclose()
