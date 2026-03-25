"""Organization tools — users, org listing, org switching."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_get_users(first: int = 100) -> list[dict]:
    """Get all users in the Heartwood Craft organization.

    Args:
        first: Max results.
    """
    result = await call_pave(
        "users",
        params={"filter": {"organizationId": {"eq": ORG_ID}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "firstName": {},
                "lastName": {},
                "email": {},
                "role": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_list_organizations() -> list[dict]:
    """List all organizations accessible with the current grant key."""
    result = await call_pave(
        "organizations",
        params={"first": 50},
        fields={
            "nodes": {
                "id": {},
                "name": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_switch_organization(organization_id: str) -> dict:
    """Get details for a specific organization (for context switching).

    Note: The MCP server always operates within Heartwood Craft by default.
    Use this to inspect another org if your grant key has access.

    Args:
        organization_id: The organization ID to inspect.
    """
    result = await call_pave(
        "organizations",
        params={"filter": {"id": {"eq": organization_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "name": {},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}
