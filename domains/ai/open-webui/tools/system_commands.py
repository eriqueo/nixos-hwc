"""
title: HWC System Commands
author: HWC AI Team
author_url: https://github.com/yourusername/nixos-hwc
git_url: https://github.com/yourusername/nixos-hwc
description: Execute system commands via secure AI agent (podman, systemctl, journalctl)
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
        """Admin-level configuration for system commands"""
        agent_url: str = Field(
            default="http://127.0.0.1:6020",
            description="HWC AI Agent URL"
        )

    def __init__(self):
        self.valves = self.Valves()

    async def list_containers(
        self,
        __event_emitter__: Callable[[dict], Any] = None
    ) -> str:
        """
        List all running containers on the HWC server.

        :return: List of container names and statuses
        """
        emitter = EventEmitter(__event_emitter__)
        await emitter.progress_update("Fetching container list...")

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self.valves.agent_url}/run",
                    json={"cmd": "podman ps --format={{.Names}}"}
                )
                result = response.json()

                if result.get("success"):
                    await emitter.success_update("Retrieved container list")
                    return f"Running containers:\n{result['output']}"
                else:
                    await emitter.error_update("Failed to list containers")
                    return f"Error: {result.get('error', 'Unknown error')}"
        except Exception as e:
            await emitter.error_update(f"Connection error: {str(e)}")
            return f"Failed to connect to agent: {str(e)}"

    async def check_service_status(
        self,
        service_name: str,
        __event_emitter__: Callable[[dict], Any] = None
    ) -> str:
        """
        Check the status of a systemd service.

        :param service_name: Name of the systemd service to check (e.g., 'ollama', 'caddy')
        :return: Service status information
        """
        emitter = EventEmitter(__event_emitter__)
        await emitter.progress_update(f"Checking {service_name} service...")

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self.valves.agent_url}/run",
                    json={"cmd": f"systemctl status {service_name}"}
                )
                result = response.json()

                if result.get("success") or result.get("returncode") == 3:  # 3 = inactive but not error
                    await emitter.success_update(f"Retrieved {service_name} status")
                    return f"Service {service_name} status:\n{result['output']}"
                else:
                    await emitter.error_update(f"Failed to check {service_name}")
                    return f"Error: {result.get('error', 'Service not found')}"
        except Exception as e:
            await emitter.error_update(f"Connection error: {str(e)}")
            return f"Failed to connect to agent: {str(e)}"

    async def view_recent_logs(
        self,
        lines: int = 50,
        __event_emitter__: Callable[[dict], Any] = None
    ) -> str:
        """
        View recent system logs from journalctl.

        :param lines: Number of log lines to retrieve (default: 50)
        :return: Recent system log entries
        """
        emitter = EventEmitter(__event_emitter__)
        await emitter.progress_update(f"Fetching last {lines} log lines...")

        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                response = await client.post(
                    f"{self.valves.agent_url}/run",
                    json={"cmd": f"journalctl -n {lines}"}
                )
                result = response.json()

                if result.get("success"):
                    await emitter.success_update("Retrieved system logs")
                    return f"Recent system logs ({lines} lines):\n{result['output']}"
                else:
                    await emitter.error_update("Failed to retrieve logs")
                    return f"Error: {result.get('error', 'Unknown error')}"
        except Exception as e:
            await emitter.error_update(f"Connection error: {str(e)}")
            return f"Failed to connect to agent: {str(e)}"
