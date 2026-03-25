"""Custom field tools — query custom fields and search entities by custom field values."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_get_custom_fields(
    entity_type: str | None = None,
    first: int = 100,
) -> list[dict]:
    """Get custom field definitions for the organization.

    Args:
        entity_type: Filter by entity type (e.g. "job", "account").
        first: Max results.
    """
    filter_obj: dict = {"organizationId": {"eq": ORG_ID}}
    if entity_type:
        filter_obj["entityType"] = {"eq": entity_type}

    result = await call_pave(
        "customFields",
        params={"filter": filter_obj, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "entityType": {},
                "fieldType": {},
                "options": {},
                "required": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_search_by_custom_field(
    entity_type: str,
    custom_field_id: str,
    value: str,
    first: int = 50,
) -> list[dict]:
    """Search entities by a custom field value.

    Queries the appropriate entity collection and filters by custom field.
    Supports jobs and accounts.

    Args:
        entity_type: "job" or "account".
        custom_field_id: The custom field definition ID.
        value: The value to search for.
        first: Max results.
    """
    if entity_type == "job":
        result = await call_pave(
            "jobs",
            params={"first": first},
            fields={
                "nodes": {
                    "id": {},
                    "number": {},
                    "name": {},
                    "status": {},
                    "customFields": {"nodes": {"customFieldId": {}, "value": {}}},
                }
            },
        )
        nodes = flatten_nodes(result)
        # Client-side filter by custom field value
        return [
            n for n in nodes
            if any(
                cf.get("customFieldId") == custom_field_id and cf.get("value") == value
                for cf in (n.get("customFields", {}).get("nodes", []) if isinstance(n.get("customFields"), dict) else [])
            )
        ]
    elif entity_type == "account":
        result = await call_pave(
            "accounts",
            params={"first": first},
            fields={
                "nodes": {
                    "id": {},
                    "name": {},
                    "type": {},
                    "customFields": {"nodes": {"customFieldId": {}, "value": {}}},
                }
            },
        )
        nodes = flatten_nodes(result)
        return [
            n for n in nodes
            if any(
                cf.get("customFieldId") == custom_field_id and cf.get("value") == value
                for cf in (n.get("customFields", {}).get("nodes", []) if isinstance(n.get("customFields"), dict) else [])
            )
        ]
    else:
        return [{"error": f"Unsupported entity_type: {entity_type}. Use 'job' or 'account'."}]
