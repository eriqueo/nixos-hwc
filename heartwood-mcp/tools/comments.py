"""Comment tools — create and query comments on jobs/tasks."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_comment(
    entity_type: str,
    entity_id: str,
    body: str,
) -> dict:
    """Create a comment on a job, task, or other entity.

    Args:
        entity_type: Type of entity to comment on (e.g. "job", "task", "dailyLog").
        entity_id: The entity ID.
        body: Comment text.
    """
    return await call_pave(
        "createComment",
        params={
            "organizationId": ORG_ID,
            "entityType": entity_type,
            "entityId": entity_id,
            "body": body,
        },
        fields={"id": {}, "body": {}, "createdAt": {}},
    )


@mcp.tool()
async def jt_get_comments(
    entity_type: str | None = None,
    entity_id: str | None = None,
    first: int = 50,
) -> list[dict]:
    """List comments, optionally filtered by entity.

    Args:
        entity_type: Filter by entity type.
        entity_id: Filter by entity ID.
        first: Max results.
    """
    filter_obj: dict = {}
    if entity_type:
        filter_obj["entityType"] = {"eq": entity_type}
    if entity_id:
        filter_obj["entityId"] = {"eq": entity_id}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "comments",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "body": {},
                "entityType": {},
                "entityId": {},
                "userId": {},
                "createdAt": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_comment_details(comment_id: str) -> dict:
    """Get full details for a specific comment.

    Args:
        comment_id: The comment ID.
    """
    result = await call_pave(
        "comments",
        params={"filter": {"id": {"eq": comment_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "body": {},
                "entityType": {},
                "entityId": {},
                "userId": {},
                "user": {"id": {}, "firstName": {}, "lastName": {}},
                "createdAt": {},
                "updatedAt": {},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}
