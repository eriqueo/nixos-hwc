"""Daily log tools — create and query daily logs."""

from __future__ import annotations

from datetime import datetime

from app import mcp
from constants import ORG_ID, DEFAULT_TIMEZONE
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_daily_log(
    job_id: str,
    date: str | None = None,
    notes: str | None = None,
    weather: str | None = None,
    timezone: str = DEFAULT_TIMEZONE,
) -> dict:
    """Create a daily log entry for a job.

    Args:
        job_id: The job ID.
        date: Log date (YYYY-MM-DD). Defaults to today.
        notes: Daily log notes/description.
        weather: Weather conditions.
        timezone: Timezone (defaults to America/Denver).
    """
    params: dict = {
        "organizationId": ORG_ID,
        "jobId": job_id,
        "timezone": timezone,
    }
    if date:
        params["date"] = date
    else:
        params["date"] = datetime.now().strftime("%Y-%m-%d")
    if notes:
        params["notes"] = notes
    if weather:
        params["weather"] = weather

    return await call_pave(
        "createDailyLog",
        params=params,
        fields={"id": {}, "date": {}, "notes": {}},
    )


@mcp.tool()
async def jt_get_daily_logs(
    job_id: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    first: int = 50,
) -> list[dict]:
    """List daily logs, optionally filtered by job or date range.

    Args:
        job_id: Filter by job.
        date_from: Start date (YYYY-MM-DD).
        date_to: End date (YYYY-MM-DD).
        first: Max results.
    """
    filter_obj: dict = {}
    if job_id:
        filter_obj["jobId"] = {"eq": job_id}
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
        "dailyLogs",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "date": {},
                "notes": {},
                "weather": {},
                "jobId": {},
                "createdAt": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_update_daily_log(
    daily_log_id: str,
    notes: str | None = None,
    weather: str | None = None,
) -> dict:
    """Update a daily log entry.

    Args:
        daily_log_id: The daily log ID.
        notes: Updated notes.
        weather: Updated weather conditions.
    """
    params: dict = {"id": daily_log_id}
    if notes is not None:
        params["notes"] = notes
    if weather is not None:
        params["weather"] = weather

    return await call_pave(
        "updateDailyLog",
        params=params,
        fields={"id": {}, "date": {}, "notes": {}, "weather": {}},
    )


@mcp.tool()
async def jt_get_daily_log_details(daily_log_id: str) -> dict:
    """Get full details for a specific daily log.

    Args:
        daily_log_id: The daily log ID.
    """
    result = await call_pave(
        "dailyLogs",
        params={"filter": {"id": {"eq": daily_log_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "date": {},
                "notes": {},
                "weather": {},
                "jobId": {},
                "job": {"id": {}, "name": {}, "number": {}},
                "createdAt": {},
                "updatedAt": {},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}


@mcp.tool()
async def jt_get_daily_logs_summary(
    job_id: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
) -> dict:
    """Get a summary of daily logs with count and date range.

    Args:
        job_id: Filter by job.
        date_from: Start date (YYYY-MM-DD).
        date_to: End date (YYYY-MM-DD).
    """
    logs = await jt_get_daily_logs(
        job_id=job_id,
        date_from=date_from,
        date_to=date_to,
        first=500,
    )
    dates = [log.get("date") for log in logs if log.get("date")]
    return {
        "count": len(logs),
        "earliestDate": min(dates) if dates else None,
        "latestDate": max(dates) if dates else None,
        "logs": logs,
    }
