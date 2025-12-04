"""
title: HWC AI Workflows
author: HWC AI Team
author_url: https://github.com/yourusername/nixos-hwc
git_url: https://github.com/yourusername/nixos-hwc
description: AI-powered workflows for file cleanup, journaling, and documentation
required_open_webui_version: 0.6.3
requirements: httpx
version: 1.0.0
license: MIT
"""

from typing import Any, Callable
from pydantic import BaseModel, Field
import httpx
import json


class EventEmitter:
    def __init__(self, event_emitter: Callable[[dict], Any] = None):
        self.event_emitter = event_emitter

    async def progress_update(self, description: str):
        await self.emit(description)

    async def error_update(self, description: str):
        await self.emit(description, "error", True)

    async def success_update(self, description: str):
        await self.emit(description, "success", True)

    async def emit(self, description: str = "Unknown State",
                   status: str = "in_progress", done: bool = False):
        if self.event_emitter:
            await self.event_emitter({
                "type": "status",
                "data": {
                    "status": status,
                    "description": description,
                    "done": done,
                }
            })


class Tools:
    class Valves(BaseModel):
        """Admin-level configuration for AI workflows"""
        workflows_url: str = Field(
            default="http://127.0.0.1:6021",
            description="HWC Workflows API URL"
        )

    def __init__(self):
        self.valves = self.Valves()

    async def organize_downloads(
        self,
        directory: str = "/home/eric/Downloads",
        dry_run: bool = True,
        __event_emitter__: Callable[[dict], Any] = None
    ) -> str:
        """
        Use AI to analyze and organize files in a directory.

        :param directory: Directory to organize (default: Downloads)
        :param dry_run: If True, only analyze without moving files
        :return: List of recommended file organization actions
        """
        emitter = EventEmitter(__event_emitter__)
        await emitter.progress_update(f"Analyzing files in {directory}...")

        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.valves.workflows_url}/api/workflows/cleanup",
                    json={"directory": directory, "dry_run": dry_run}
                )
                result = response.json()

                files_analyzed = result.get("files_analyzed", 0)
                actions = result.get("actions", [])

                await emitter.success_update(f"Analyzed {files_analyzed} files")

                # Format results
                output = f"## File Organization Analysis\n\n"
                output += f"**Directory**: {directory}\n"
                output += f"**Files analyzed**: {files_analyzed}\n"
                output += f"**Mode**: {'Preview only' if dry_run else 'Files moved'}\n\n"

                if actions:
                    output += "### Recommended Actions:\n\n"
                    for action in actions[:20]:  # Limit to 20 actions
                        output += f"**File**: `{action['file']}`\n"
                        output += f"- Action: {action['action']}\n"
                        if action.get('destination'):
                            output += f"- Destination: {action['destination']}\n"
                        output += f"- Reason: {action['reason']}\n\n"

                    if len(actions) > 20:
                        output += f"... and {len(actions) - 20} more actions\n"
                else:
                    output += "No actions recommended. Directory is organized!\n"

                return output
        except Exception as e:
            await emitter.error_update(f"Workflow failed: {str(e)}")
            return f"Failed to run cleanup workflow: {str(e)}"

    async def generate_journal_entry(
        self,
        sources: list = None,
        __event_emitter__: Callable[[dict], Any] = None
    ) -> str:
        """
        Generate a daily journal entry from system logs and metrics.

        :param sources: List of sources to include (default: ['systemd-journal', 'container-logs'])
        :return: Generated journal entry in markdown format
        """
        emitter = EventEmitter(__event_emitter__)
        await emitter.progress_update("Gathering system logs and metrics...")

        if sources is None:
            sources = ["systemd-journal", "container-logs"]

        try:
            async with httpx.AsyncClient(timeout=120.0) as client:
                response = await client.post(
                    f"{self.valves.workflows_url}/api/workflows/journal",
                    json={
                        "sources": sources,
                        "time_range": "24h",
                        "include_metrics": True
                    }
                )
                result = response.json()

                await emitter.success_update("Journal entry generated")

                content = result.get("content", "")
                output_path = result.get("output_path")

                output = "## Daily Journal Entry\n\n"
                output += content
                if output_path:
                    output += f"\n\n*Saved to: {output_path}*"

                return output
        except Exception as e:
            await emitter.error_update(f"Journal generation failed: {str(e)}")
            return f"Failed to generate journal: {str(e)}"

    async def document_code(
        self,
        file_path: str,
        style: str = "technical",
        __event_emitter__: Callable[[dict], Any] = None
    ) -> str:
        """
        Generate documentation for a code file using AI.

        :param file_path: Path to the code file to document
        :param style: Documentation style ('technical' or 'user-friendly')
        :return: Generated documentation in markdown format
        """
        emitter = EventEmitter(__event_emitter__)
        await emitter.progress_update(f"Analyzing {file_path}...")

        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                response = await client.post(
                    f"{self.valves.workflows_url}/api/workflows/autodoc",
                    json={
                        "file_path": file_path,
                        "style": style,
                        "include_examples": True
                    }
                )
                result = response.json()

                await emitter.success_update("Documentation generated")

                documentation = result.get("documentation", "")
                sections = result.get("sections", [])

                output = f"## Documentation for `{file_path}`\n\n"
                output += f"**Style**: {style}\n"
                if sections:
                    output += f"**Sections**: {', '.join(sections)}\n\n"
                output += documentation

                return output
        except Exception as e:
            await emitter.error_update(f"Documentation failed: {str(e)}")
            return f"Failed to generate documentation: {str(e)}"

    async def chat_with_context(
        self,
        message: str,
        context: str = None,
        model: str = "qwen2.5-coder:3b",
        __event_emitter__: Callable[[dict], Any] = None
    ) -> str:
        """
        Chat with a local AI model, optionally with additional context.

        :param message: Your message/question
        :param context: Optional context (file content, logs, etc.)
        :param model: Model to use (default: qwen2.5-coder:3b)
        :return: AI response
        """
        emitter = EventEmitter(__event_emitter__)
        await emitter.progress_update(f"Thinking with {model}...")

        try:
            async with httpx.AsyncClient(timeout=180.0) as client:
                response = await client.post(
                    f"{self.valves.workflows_url}/api/workflows/chat",
                    json={
                        "message": message,
                        "context": context,
                        "model": model,
                        "stream": False
                    }
                )
                result = response.json()

                await emitter.success_update("Response generated")

                return result.get("response", "No response generated")
        except Exception as e:
            await emitter.error_update(f"Chat failed: {str(e)}")
            return f"Failed to chat: {str(e)}"
