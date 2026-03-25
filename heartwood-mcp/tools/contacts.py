"""Contact tools — create and query JobTread contacts."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_contact(
    account_id: str,
    first_name: str,
    last_name: str,
    email: str | None = None,
    phone: str | None = None,
) -> dict:
    """Create a contact linked to an account.

    Args:
        account_id: The parent account ID.
        first_name: Contact first name.
        last_name: Contact last name.
        email: Email address.
        phone: Phone number.
    """
    params: dict = {
        "organizationId": ORG_ID,
        "accountId": account_id,
        "firstName": first_name,
        "lastName": last_name,
    }
    if email:
        params["email"] = email
    if phone:
        params["phone"] = phone

    return await call_pave(
        "createContact",
        params=params,
        fields={"id": {}, "firstName": {}, "lastName": {}, "email": {}, "phone": {}},
    )


@mcp.tool()
async def jt_get_contacts(
    account_id: str | None = None,
    search_term: str | None = None,
    first: int = 100,
) -> list[dict]:
    """List contacts, optionally filtered by account or search term.

    Args:
        account_id: Filter by parent account.
        search_term: Search contacts by name.
        first: Max results.
    """
    filter_obj: dict = {}
    if account_id:
        filter_obj["accountId"] = {"eq": account_id}
    if search_term:
        filter_obj["name"] = {"match": search_term}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "contacts",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "firstName": {},
                "lastName": {},
                "email": {},
                "phone": {},
                "accountId": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_contact_details(contact_id: str) -> dict:
    """Get full details for a specific contact.

    Args:
        contact_id: The contact ID.
    """
    result = await call_pave(
        "contacts",
        params={"filter": {"id": {"eq": contact_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "firstName": {},
                "lastName": {},
                "email": {},
                "phone": {},
                "accountId": {},
                "account": {"id": {}, "name": {}},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}
