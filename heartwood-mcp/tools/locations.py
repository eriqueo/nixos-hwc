"""Location tools — create and query JobTread locations."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_location(
    account_id: str,
    street1: str,
    city: str,
    state: str,
    zip_code: str,
    street2: str | None = None,
) -> dict:
    """Create a location (address) linked to an account.

    Args:
        account_id: The parent account ID.
        street1: Street address line 1.
        city: City.
        state: State abbreviation.
        zip_code: ZIP/postal code.
        street2: Street address line 2 (optional).
    """
    address: dict = {
        "street1": street1,
        "city": city,
        "state": state,
        "zip": zip_code,
    }
    if street2:
        address["street2"] = street2

    return await call_pave(
        "createLocation",
        params={
            "organizationId": ORG_ID,
            "accountId": account_id,
            "address": address,
        },
        fields={
            "id": {},
            "address": {"street1": {}, "street2": {}, "city": {}, "state": {}, "zip": {}},
        },
    )


@mcp.tool()
async def jt_get_locations(
    account_id: str | None = None,
    first: int = 100,
) -> list[dict]:
    """List locations, optionally filtered by account.

    Args:
        account_id: Filter by parent account.
        first: Max results.
    """
    filter_obj: dict = {}
    if account_id:
        filter_obj["accountId"] = {"eq": account_id}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "locations",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "accountId": {},
                "address": {"street1": {}, "street2": {}, "city": {}, "state": {}, "zip": {}},
            }
        },
    )
    return flatten_nodes(result)
