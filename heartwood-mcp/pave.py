"""PAVE API client for JobTread.

Wraps every operation in the PAVE envelope, handles auth, error checking,
and response flattening.
"""

import os
import sys
import time
from typing import Any

import httpx

PAVE_URL = "https://api.jobtread.com/pave"
VIA_USER_ID = "22Nm3uFeRB7s"  # Eric's user ID
REQUEST_TIMEOUT = 30.0


def _get_grant_key() -> str:
    key = os.environ.get("JT_GRANT_KEY")
    if not key:
        raise RuntimeError("JT_GRANT_KEY environment variable is not set")
    return key


async def call_pave(
    operation: str,
    params: dict[str, Any] | None = None,
    fields: dict[str, Any] | None = None,
    *,
    timeout: float = REQUEST_TIMEOUT,
) -> Any:
    """Execute a PAVE query against the JobTread API.

    Args:
        operation: The PAVE operation name (e.g. "accounts", "createJob").
        params: The ``$`` parameters for the operation (filter, first, input fields, etc.).
        fields: The field selection dict. Each key is a field name, value is ``{}``
                 for scalars or a nested dict for relations.
        timeout: HTTP request timeout in seconds.

    Returns:
        The operation result extracted from the PAVE response envelope.

    Raises:
        RuntimeError: On PAVE-level errors (HTTP 200 with errors array) or HTTP errors.
    """
    start = time.monotonic()
    grant_key = _get_grant_key()

    # Build the operation body
    op_body: dict[str, Any] = {}
    if params:
        op_body["$"] = params
    if fields:
        op_body.update(fields)

    # Build the full PAVE envelope
    query: dict[str, Any] = {
        "$": {
            "grantKey": grant_key,
            "notify": False,
            "viaUserId": VIA_USER_ID,
        },
        operation: op_body,
    }

    payload = {"query": query}

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                PAVE_URL,
                json=payload,
                timeout=timeout,
            )
            resp.raise_for_status()
        except httpx.HTTPStatusError as exc:
            duration = time.monotonic() - start
            _log(operation, params, False, duration, str(exc))
            raise RuntimeError(f"PAVE HTTP error: {exc.response.status_code} - {exc.response.text}") from exc
        except httpx.RequestError as exc:
            duration = time.monotonic() - start
            _log(operation, params, False, duration, str(exc))
            raise RuntimeError(f"PAVE request failed: {exc}") from exc

    duration = time.monotonic() - start
    data = resp.json()

    # Check for PAVE's 200-with-errors pattern
    if "errors" in data and data["errors"]:
        errors = data["errors"]
        msg = "; ".join(e.get("message", str(e)) for e in errors)
        _log(operation, params, False, duration, msg)
        raise RuntimeError(f"PAVE error: {msg}")

    # Extract the operation result
    result = data.get(operation)
    _log(operation, params, True, duration)
    return result


async def call_pave_multi(operations: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Execute multiple PAVE operations in a single request.

    Args:
        operations: Dict mapping operation names to their body dicts
                    (each body should have optional ``$`` and field selections).

    Returns:
        Dict mapping operation names to their results.
    """
    start = time.monotonic()
    grant_key = _get_grant_key()

    query: dict[str, Any] = {
        "$": {
            "grantKey": grant_key,
            "notify": False,
            "viaUserId": VIA_USER_ID,
        },
    }
    query.update(operations)

    payload = {"query": query}

    async with httpx.AsyncClient() as client:
        resp = await client.post(PAVE_URL, json=payload, timeout=REQUEST_TIMEOUT)
        resp.raise_for_status()

    duration = time.monotonic() - start
    data = resp.json()

    if "errors" in data and data["errors"]:
        errors = data["errors"]
        msg = "; ".join(e.get("message", str(e)) for e in errors)
        _log("multi", None, False, duration, msg)
        raise RuntimeError(f"PAVE error: {msg}")

    _log("multi", list(operations.keys()), True, duration)
    return {op: data.get(op) for op in operations}


def flatten_nodes(result: dict | None) -> list[dict]:
    """Extract the ``nodes`` list from a PAVE collection result."""
    if not result:
        return []
    nodes = result.get("nodes", [])
    return nodes if isinstance(nodes, list) else []


def _log(
    operation: str,
    params: Any,
    success: bool,
    duration: float,
    error: str | None = None,
) -> None:
    """Log PAVE calls to stderr."""
    status = "OK" if success else "ERROR"
    msg = f"[PAVE] {status} {operation} ({duration:.2f}s)"
    if error:
        msg += f" - {error}"
    print(msg, file=sys.stderr)
