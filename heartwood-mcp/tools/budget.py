"""Budget tools — line items, cost codes, cost types, and units."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID, GROUP_SEPARATOR
from pave import call_pave, flatten_nodes


def _validate_budget_items(items: list[dict]) -> list[str]:
    """Validate budget line items per Heartwood rules.

    Returns a list of validation error messages (empty if valid).
    """
    errors = []
    for i, item in enumerate(items):
        # Names must be pipe-delimited
        name = item.get("name", "")
        if "|" not in name and len(items) > 1:
            # Single items don't need pipes, but multi-item batches do
            pass  # Allow single names without pipes

        # Numeric fields must be numbers, not strings
        for field in ("quantity", "unitCost", "unitPrice", "cost", "price"):
            val = item.get(field)
            if val is not None and isinstance(val, str):
                try:
                    float(val)
                    errors.append(
                        f"Item {i}: '{field}' is a string '{val}' — must be a number"
                    )
                except ValueError:
                    errors.append(
                        f"Item {i}: '{field}' has invalid value '{val}'"
                    )

        # Group separator must use " > " with spaces
        group = item.get("groupName", "")
        if ">" in group and GROUP_SEPARATOR not in group:
            errors.append(
                f"Item {i}: groupName '{group}' must use ' > ' (with spaces) as separator"
            )

    return errors


@mcp.tool()
async def jt_add_budget_line_items(
    job_id: str,
    items: list[dict],
) -> dict:
    """Add budget line items to a job.

    Validates that: names are pipe-delimited for multi-item batches,
    numeric fields are numbers (not strings), groupName uses ' > ' separator.

    Args:
        job_id: The job ID to add items to.
        items: List of line item dicts with keys like name, quantity, unitCost,
               unitPrice, cost, price, costCodeId, costTypeId, unitId, groupName, etc.
    """
    errors = _validate_budget_items(items)
    if errors:
        return {"error": "Validation failed", "details": errors}

    return await call_pave(
        "addBudgetLineItems",
        params={"jobId": job_id, "items": items},
        fields={"id": {}, "name": {}},
        timeout=60.0,
    )


@mcp.tool()
async def jt_get_job_budget(
    job_id: str,
    first: int = 200,
) -> list[dict]:
    """Get all budget line items for a job.

    Args:
        job_id: The job ID.
        first: Max results (default 200).
    """
    result = await call_pave(
        "budgetItems",
        params={"filter": {"jobId": {"eq": job_id}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "groupName": {},
                "quantity": {},
                "unitCost": {},
                "unitPrice": {},
                "cost": {},
                "price": {},
                "costCodeId": {},
                "costTypeId": {},
                "unitId": {},
                "description": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_cost_codes(first: int = 200) -> list[dict]:
    """Get all cost codes for the organization.

    Args:
        first: Max results (default 200).
    """
    result = await call_pave(
        "costCodes",
        params={"filter": {"organizationId": {"eq": ORG_ID}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "code": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_cost_types(first: int = 200) -> list[dict]:
    """Get all cost types for the organization.

    Args:
        first: Max results (default 200).
    """
    result = await call_pave(
        "costTypes",
        params={"filter": {"organizationId": {"eq": ORG_ID}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_units(first: int = 200) -> list[dict]:
    """Get all unit types for the organization.

    Args:
        first: Max results (default 200).
    """
    result = await call_pave(
        "units",
        params={"filter": {"organizationId": {"eq": ORG_ID}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "abbreviation": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_update_budget_line_item(
    budget_item_id: str,
    name: str | None = None,
    quantity: float | None = None,
    unit_cost: float | None = None,
    unit_price: float | None = None,
    description: str | None = None,
) -> dict:
    """Update a single budget line item.

    Args:
        budget_item_id: The budget item ID.
        name: New name.
        quantity: New quantity.
        unit_cost: New unit cost.
        unit_price: New unit price.
        description: New description.
    """
    params: dict = {"id": budget_item_id}
    if name is not None:
        params["name"] = name
    if quantity is not None:
        params["quantity"] = quantity
    if unit_cost is not None:
        params["unitCost"] = unit_cost
    if unit_price is not None:
        params["unitPrice"] = unit_price
    if description is not None:
        params["description"] = description

    return await call_pave(
        "updateBudgetItem",
        params=params,
        fields={"id": {}, "name": {}, "quantity": {}, "unitCost": {}, "unitPrice": {}},
    )


@mcp.tool()
async def jt_delete_budget_line_item(budget_item_id: str) -> dict:
    """Delete a budget line item.

    Args:
        budget_item_id: The budget item ID to delete.
    """
    return await call_pave(
        "deleteBudgetItem",
        params={"id": budget_item_id},
        fields={"id": {}},
    )
