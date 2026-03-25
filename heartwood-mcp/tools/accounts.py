"""Account tools — create, update, and query JobTread accounts."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_account(
    name: str,
    account_type: str = "customer",
    custom_field_values: dict[str, str] | None = None,
) -> dict:
    """Create a new account (customer or vendor) in JobTread.

    PAVE gotcha: createAccount does not accept custom fields, so if
    custom_field_values is provided, a follow-up updateAccount call is made.

    Args:
        name: Account name.
        account_type: "customer" or "vendor".
        custom_field_values: Optional dict of {customFieldId: value} to set after creation.
    """
    result = await call_pave(
        "createAccount",
        params={
            "organizationId": ORG_ID,
            "name": name,
            "type": account_type,
        },
        fields={"id": {}, "name": {}, "type": {}},
    )

    if custom_field_values and result and result.get("id"):
        account_id = result["id"]
        cf_list = [{"customFieldId": k, "value": v} for k, v in custom_field_values.items()]
        await call_pave(
            "updateAccount",
            params={
                "id": account_id,
                "customFieldValues": cf_list,
            },
            fields={"id": {}, "name": {}},
        )
        result["customFieldValues"] = custom_field_values

    return result


@mcp.tool()
async def jt_update_account(
    account_id: str,
    name: str | None = None,
    custom_field_values: dict[str, str] | None = None,
) -> dict:
    """Update an existing account's name or custom fields.

    Args:
        account_id: The account ID to update.
        name: New name (optional).
        custom_field_values: Dict of {customFieldId: value} to set.
    """
    params: dict = {"id": account_id}
    if name is not None:
        params["name"] = name
    if custom_field_values:
        params["customFieldValues"] = [
            {"customFieldId": k, "value": v} for k, v in custom_field_values.items()
        ]

    return await call_pave(
        "updateAccount",
        params=params,
        fields={"id": {}, "name": {}, "type": {}},
    )


@mcp.tool()
async def jt_get_accounts(
    account_type: str | None = None,
    search_term: str | None = None,
    first: int = 100,
) -> list[dict]:
    """List accounts, optionally filtered by type or search term.

    Args:
        account_type: Filter by "customer" or "vendor".
        search_term: Search by name.
        first: Max results (default 100).
    """
    filter_obj: dict = {}
    if account_type:
        filter_obj["type"] = {"eq": account_type}
    if search_term:
        filter_obj["name"] = {"match": search_term}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "accounts",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "type": {},
                "primaryLocationId": {},
                "locations": {
                    "nodes": {
                        "id": {},
                        "address": {"street1": {}, "city": {}, "state": {}, "zip": {}},
                    }
                },
                "customFields": {"nodes": {"customFieldId": {}, "value": {}}},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_account_details(account_id: str) -> dict:
    """Get full details for a specific account including locations and contacts.

    Args:
        account_id: The account ID.
    """
    result = await call_pave(
        "accounts",
        params={"filter": {"id": {"eq": account_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "type": {},
                "primaryLocationId": {},
                "locations": {
                    "nodes": {
                        "id": {},
                        "address": {"street1": {}, "street2": {}, "city": {}, "state": {}, "zip": {}},
                    }
                },
                "contacts": {
                    "nodes": {
                        "id": {},
                        "firstName": {},
                        "lastName": {},
                        "email": {},
                        "phone": {},
                    }
                },
                "customFields": {"nodes": {"customFieldId": {}, "value": {}}},
                "createdAt": {},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}
