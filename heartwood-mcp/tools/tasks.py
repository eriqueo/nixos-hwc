"""Task tools — create, update, and query JobTread tasks."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


TASK_FIELDS = {
    "nodes": {
        "id": {},
        "name": {},
        "status": {},
        "progress": {},
        "jobId": {},
        "assigneeId": {},
        "startDate": {},
        "endDate": {},
        "description": {},
    }
}


@mcp.tool()
async def jt_create_task(
    job_id: str,
    name: str,
    assignee_id: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    description: str | None = None,
) -> dict:
    """Create a task on a job.

    Args:
        job_id: The job ID.
        name: Task name.
        assignee_id: User ID to assign the task to.
        start_date: Start date (YYYY-MM-DD).
        end_date: End date (YYYY-MM-DD).
        description: Task description.
    """
    params: dict = {
        "organizationId": ORG_ID,
        "jobId": job_id,
        "name": name,
    }
    if assignee_id:
        params["assigneeId"] = assignee_id
    if start_date:
        params["startDate"] = start_date
    if end_date:
        params["endDate"] = end_date
    if description:
        params["description"] = description

    return await call_pave(
        "createTask",
        params=params,
        fields={"id": {}, "name": {}, "status": {}},
    )


@mcp.tool()
async def jt_update_task_progress(
    task_id: str,
    progress: int,
    status: str | None = None,
) -> dict:
    """Update a task's progress percentage and optionally its status.

    Args:
        task_id: The task ID.
        progress: Progress percentage (0-100).
        status: New status (e.g. "pending", "in_progress", "completed").
    """
    params: dict = {"id": task_id, "progress": progress}
    if status is not None:
        params["status"] = status

    return await call_pave(
        "updateTask",
        params=params,
        fields={"id": {}, "name": {}, "status": {}, "progress": {}},
    )


@mcp.tool()
async def jt_get_tasks(
    job_id: str | None = None,
    status: str | None = None,
    assignee_id: str | None = None,
    first: int = 100,
) -> list[dict]:
    """List tasks, optionally filtered by job, status, or assignee.

    Args:
        job_id: Filter by job.
        status: Filter by status.
        assignee_id: Filter by assigned user.
        first: Max results.
    """
    filter_obj: dict = {}
    if job_id:
        filter_obj["jobId"] = {"eq": job_id}
    if status:
        filter_obj["status"] = {"eq": status}
    if assignee_id:
        filter_obj["assigneeId"] = {"eq": assignee_id}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave("tasks", params=params, fields=TASK_FIELDS)
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_task_details(task_id: str) -> dict:
    """Get full details for a specific task.

    Args:
        task_id: The task ID.
    """
    result = await call_pave(
        "tasks",
        params={"filter": {"id": {"eq": task_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "status": {},
                "progress": {},
                "jobId": {},
                "job": {"id": {}, "name": {}, "number": {}},
                "assigneeId": {},
                "assignee": {"id": {}, "firstName": {}, "lastName": {}},
                "startDate": {},
                "endDate": {},
                "description": {},
                "createdAt": {},
                "updatedAt": {},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}


@mcp.tool()
async def jt_get_task_templates(first: int = 50) -> list[dict]:
    """Get available task templates for the organization.

    Args:
        first: Max results.
    """
    result = await call_pave(
        "taskTemplates",
        params={"filter": {"organizationId": {"eq": ORG_ID}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "description": {},
            }
        },
    )
    return flatten_nodes(result)
