"""Job tools — create, search, and manage JobTread jobs."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


JOB_FIELDS = {
    "nodes": {
        "id": {},
        "number": {},
        "name": {},
        "status": {},
        "accountId": {},
        "account": {"id": {}, "name": {}},
        "locationId": {},
        "startDate": {},
        "endDate": {},
        "customFields": {"nodes": {"customFieldId": {}, "value": {}}},
    }
}

JOB_DETAIL_FIELDS = {
    "nodes": {
        "id": {},
        "number": {},
        "name": {},
        "status": {},
        "accountId": {},
        "account": {"id": {}, "name": {}},
        "locationId": {},
        "location": {
            "id": {},
            "address": {"street1": {}, "city": {}, "state": {}, "zip": {}},
        },
        "startDate": {},
        "endDate": {},
        "description": {},
        "customFields": {"nodes": {"customFieldId": {}, "value": {}}},
        "createdAt": {},
        "updatedAt": {},
    }
}


@mcp.tool()
async def jt_create_job(
    account_id: str,
    name: str,
    location_id: str | None = None,
    description: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
) -> dict:
    """Create a new job in JobTread.

    Args:
        account_id: The customer account ID.
        name: Job name/title.
        location_id: Optional location ID for the job site.
        description: Optional job description.
        start_date: Optional start date (YYYY-MM-DD).
        end_date: Optional end date (YYYY-MM-DD).
    """
    params: dict = {
        "organizationId": ORG_ID,
        "accountId": account_id,
        "name": name,
    }
    if location_id:
        params["locationId"] = location_id
    if description:
        params["description"] = description
    if start_date:
        params["startDate"] = start_date
    if end_date:
        params["endDate"] = end_date

    return await call_pave(
        "createJob",
        params=params,
        fields={"id": {}, "number": {}, "name": {}, "status": {}},
    )


@mcp.tool()
async def jt_search_jobs(
    search_term: str | None = None,
    account_id: str | None = None,
    status: str | None = None,
    first: int = 50,
) -> list[dict]:
    """Search jobs by name, account, or status.

    Args:
        search_term: Search by job name.
        account_id: Filter by customer account ID.
        status: Filter by status (e.g. "active", "closed", "pending").
        first: Max results (default 50).
    """
    filter_obj: dict = {}
    if search_term:
        filter_obj["name"] = {"match": search_term}
    if account_id:
        filter_obj["accountId"] = {"eq": account_id}
    if status:
        filter_obj["status"] = {"eq": status}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave("jobs", params=params, fields=JOB_FIELDS)
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_job_details(job_id: str) -> dict:
    """Get full details for a specific job.

    Args:
        job_id: The job ID.
    """
    result = await call_pave(
        "jobs",
        params={"filter": {"id": {"eq": job_id}}, "first": 1},
        fields=JOB_DETAIL_FIELDS,
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}


@mcp.tool()
async def jt_get_active_jobs(first: int = 100) -> list[dict]:
    """Get all active jobs for Heartwood Craft.

    Args:
        first: Max results (default 100).
    """
    result = await call_pave(
        "jobs",
        params={"filter": {"status": {"eq": "active"}}, "first": first},
        fields=JOB_FIELDS,
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_set_job_parameters(
    job_id: str,
    name: str | None = None,
    status: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    description: str | None = None,
    custom_field_values: dict[str, str] | None = None,
) -> dict:
    """Update job parameters (name, status, dates, custom fields).

    Args:
        job_id: The job ID to update.
        name: New job name.
        status: New status.
        start_date: New start date (YYYY-MM-DD).
        end_date: New end date (YYYY-MM-DD).
        description: New description.
        custom_field_values: Dict of {customFieldId: value} to set.
    """
    params: dict = {"id": job_id}
    if name is not None:
        params["name"] = name
    if status is not None:
        params["status"] = status
    if start_date is not None:
        params["startDate"] = start_date
    if end_date is not None:
        params["endDate"] = end_date
    if description is not None:
        params["description"] = description
    if custom_field_values:
        params["customFieldValues"] = [
            {"customFieldId": k, "value": v} for k, v in custom_field_values.items()
        ]

    return await call_pave(
        "updateJob",
        params=params,
        fields={"id": {}, "name": {}, "status": {}},
    )
