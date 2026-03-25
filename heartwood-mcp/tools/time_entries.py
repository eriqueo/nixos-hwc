"""Time entry tools — log and query time entries."""

from __future__ import annotations

from datetime import datetime

from app import mcp
from constants import ORG_ID, DEFAULT_TIMEZONE
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_time_entry(
    job_id: str,
    user_id: str,
    hours: float,
    date: str | None = None,
    description: str | None = None,
    cost_code_id: str | None = None,
    timezone: str = DEFAULT_TIMEZONE,
) -> dict:
    """Log a time entry on a job.

    Args:
        job_id: The job ID.
        user_id: The user who performed the work.
        hours: Number of hours worked.
        date: Date of the work (YYYY-MM-DD). Defaults to today.
        description: Description of work performed.
        cost_code_id: Optional cost code ID for categorization.
        timezone: Timezone for the entry (defaults to America/Denver).
    """
    params: dict = {
        "organizationId": ORG_ID,
        "jobId": job_id,
        "userId": user_id,
        "hours": hours,
        "timezone": timezone,
    }
    if date:
        params["date"] = date
    else:
        params["date"] = datetime.now().strftime("%Y-%m-%d")
    if description:
        params["description"] = description
    if cost_code_id:
        params["costCodeId"] = cost_code_id

    return await call_pave(
        "createTimeEntry",
        params=params,
        fields={"id": {}, "hours": {}, "date": {}},
    )


@mcp.tool()
async def jt_get_time_entries(
    job_id: str | None = None,
    user_id: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    first: int = 100,
) -> list[dict]:
    """List time entries, optionally filtered by job, user, or date range.

    Args:
        job_id: Filter by job.
        user_id: Filter by user.
        date_from: Start date (YYYY-MM-DD) — entries on or after.
        date_to: End date (YYYY-MM-DD) — entries on or before.
        first: Max results.
    """
    filter_obj: dict = {}
    if job_id:
        filter_obj["jobId"] = {"eq": job_id}
    if user_id:
        filter_obj["userId"] = {"eq": user_id}
    if date_from:
        filter_obj["date"] = {"gte": date_from}
    if date_to:
        if "date" in filter_obj:
            filter_obj["date"]["lte"] = date_to
        else:
            filter_obj["date"] = {"lte": date_to}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "timeEntries",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "hours": {},
                "date": {},
                "description": {},
                "userId": {},
                "jobId": {},
                "costCodeId": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_time_entry_details(time_entry_id: str) -> dict:
    """Get full details for a specific time entry.

    Args:
        time_entry_id: The time entry ID.
    """
    result = await call_pave(
        "timeEntries",
        params={"filter": {"id": {"eq": time_entry_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "hours": {},
                "date": {},
                "description": {},
                "userId": {},
                "user": {"id": {}, "firstName": {}, "lastName": {}},
                "jobId": {},
                "job": {"id": {}, "name": {}, "number": {}},
                "costCodeId": {},
                "createdAt": {},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}


@mcp.tool()
async def jt_update_time_entry(
    time_entry_id: str,
    hours: float | None = None,
    date: str | None = None,
    description: str | None = None,
) -> dict:
    """Update a time entry.

    Args:
        time_entry_id: The time entry ID.
        hours: New hours value.
        date: New date (YYYY-MM-DD).
        description: New description.
    """
    params: dict = {"id": time_entry_id}
    if hours is not None:
        params["hours"] = hours
    if date is not None:
        params["date"] = date
    if description is not None:
        params["description"] = description

    return await call_pave(
        "updateTimeEntry",
        params=params,
        fields={"id": {}, "hours": {}, "date": {}, "description": {}},
    )


@mcp.tool()
async def jt_delete_time_entry(time_entry_id: str) -> dict:
    """Delete a time entry.

    Args:
        time_entry_id: The time entry ID to delete.
    """
    return await call_pave(
        "deleteTimeEntry",
        params={"id": time_entry_id},
        fields={"id": {}},
    )


@mcp.tool()
async def jt_get_time_summary(
    job_id: str | None = None,
    user_id: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
) -> dict:
    """Get a summary of time entries (total hours) with optional filters.

    Returns total hours and entry count rather than individual entries.

    Args:
        job_id: Filter by job.
        user_id: Filter by user.
        date_from: Start date (YYYY-MM-DD).
        date_to: End date (YYYY-MM-DD).
    """
    entries = await jt_get_time_entries(
        job_id=job_id,
        user_id=user_id,
        date_from=date_from,
        date_to=date_to,
        first=500,
    )
    total_hours = sum(e.get("hours", 0) for e in entries)
    return {
        "totalHours": total_hours,
        "entryCount": len(entries),
        "entries": entries,
    }
