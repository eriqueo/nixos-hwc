"""Dashboard tools — create, update, and query dashboards."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_dashboard(
    name: str,
    dashboard_type: str | None = None,
    config: dict | None = None,
) -> dict:
    """Create a dashboard.

    Args:
        name: Dashboard name.
        dashboard_type: Optional dashboard type/category.
        config: Optional configuration dict for the dashboard layout.
    """
    params: dict = {
        "organizationId": ORG_ID,
        "name": name,
    }
    if dashboard_type:
        params["type"] = dashboard_type
    if config:
        params["config"] = config

    return await call_pave(
        "createDashboard",
        params=params,
        fields={"id": {}, "name": {}},
    )


@mcp.tool()
async def jt_update_dashboard(
    dashboard_id: str,
    name: str | None = None,
    config: dict | None = None,
) -> dict:
    """Update a dashboard's name or configuration.

    Args:
        dashboard_id: The dashboard ID.
        name: New name.
        config: New configuration dict.
    """
    params: dict = {"id": dashboard_id}
    if name is not None:
        params["name"] = name
    if config is not None:
        params["config"] = config

    return await call_pave(
        "updateDashboard",
        params=params,
        fields={"id": {}, "name": {}},
    )


@mcp.tool()
async def jt_get_dashboards(first: int = 50) -> list[dict]:
    """List all dashboards for the organization.

    Args:
        first: Max results.
    """
    result = await call_pave(
        "dashboards",
        params={"filter": {"organizationId": {"eq": ORG_ID}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "type": {},
                "createdAt": {},
            }
        },
    )
    return flatten_nodes(result)
