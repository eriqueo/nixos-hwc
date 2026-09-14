#!/usr/bin/env python3
"""Call one HWC MCP gateway tool from a terminal script.

The client performs one initialize/call/close lifecycle and never retries a tool
call.  That is deliberate: callers may invoke externally visible writes whose
result is ambiguous after a transport failure.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from typing import Any


JSONRPC = "2.0"
PROTOCOL = "2025-06-18"
SESSION_HEADER = "Mcp-Session-Id"


class CallError(RuntimeError):
    pass


def decode_response(body: bytes, content_type: str) -> dict[str, Any]:
    text = body.decode("utf-8", errors="replace")
    if "text/event-stream" in content_type:
        for line in text.splitlines():
            if line.startswith("data:"):
                value = line[5:].strip()
                if value and value != "[DONE]":
                    return json.loads(value)
        raise CallError("gateway returned an empty event-stream response")
    value = json.loads(text) if text else {}
    if not isinstance(value, dict):
        raise CallError("gateway response was not a JSON object")
    return value


def request(
    endpoint: str,
    payload: dict[str, Any] | None,
    *,
    session_id: str | None = None,
    method: str = "POST",
    timeout: float = 10.0,
) -> tuple[dict[str, Any], str | None]:
    headers = {
        "Accept": "application/json, text/event-stream",
        "Content-Type": "application/json",
        "MCP-Protocol-Version": PROTOCOL,
    }
    if session_id:
        headers[SESSION_HEADER] = session_id
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(endpoint, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            body = response.read()
            envelope = decode_response(body, response.headers.get("Content-Type", "")) if body else {}
            return envelope, response.headers.get(SESSION_HEADER)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise CallError(f"gateway returned HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise CallError(f"could not reach gateway: {exc.reason}") from exc


def unwrap_tool_result(envelope: dict[str, Any]) -> Any:
    if "error" in envelope:
        raise CallError(f"gateway JSON-RPC error: {envelope['error']}")
    result = envelope.get("result")
    if not isinstance(result, dict):
        raise CallError("gateway returned no tool result")
    if result.get("isError"):
        raise CallError(_content_text(result) or "tool returned an error")
    text = _content_text(result)
    if text:
        try:
            value = json.loads(text)
        except json.JSONDecodeError:
            return text
        if isinstance(value, dict) and value.get("status") == "error":
            raise CallError(value.get("message") or str(value))
        return value
    return result.get("structuredContent", result)


def _content_text(result: dict[str, Any]) -> str:
    for block in result.get("content") or []:
        if isinstance(block, dict) and block.get("type") == "text":
            return str(block.get("text", ""))
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Call one HWC MCP gateway tool")
    parser.add_argument("tool")
    parser.add_argument("arguments", nargs="?", default="{}", help="JSON object")
    parser.add_argument("--endpoint", default="http://127.0.0.1:6200/mcp")
    parser.add_argument("--write", action="store_true", help="emit write-safe failure guidance")
    args = parser.parse_args()

    try:
        arguments = json.loads(args.arguments)
        if not isinstance(arguments, dict):
            raise CallError("arguments must decode to a JSON object")

        init, session_id = request(
            args.endpoint,
            {
                "jsonrpc": JSONRPC,
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": PROTOCOL,
                    "capabilities": {},
                    "clientInfo": {"name": "hwc-mcp-call", "version": "1"},
                },
            },
        )
        if "error" in init:
            raise CallError(f"gateway initialize failed: {init['error']}")
        if not session_id:
            raise CallError("gateway did not return a session id")

        try:
            request(
                args.endpoint,
                {"jsonrpc": JSONRPC, "method": "notifications/initialized"},
                session_id=session_id,
            )
            envelope, _ = request(
                args.endpoint,
                {
                    "jsonrpc": JSONRPC,
                    "id": 2,
                    "method": "tools/call",
                    "params": {"name": args.tool, "arguments": arguments},
                },
                session_id=session_id,
            )
            value = unwrap_tool_result(envelope)
        finally:
            try:
                request(args.endpoint, None, session_id=session_id, method="DELETE", timeout=2.0)
            except CallError:
                pass

        print(json.dumps(value, ensure_ascii=False))
        return 0
    except (CallError, json.JSONDecodeError) as exc:
        print(f"hwc-mcp-call: {exc}", file=sys.stderr)
        if args.write:
            print("The write may be ambiguous. Do not retry until you inspect the destination.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
