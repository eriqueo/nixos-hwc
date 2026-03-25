"""Payment tools — create and query payments."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_payment(
    document_id: str,
    amount: float,
    payment_method: str | None = None,
    reference: str | None = None,
    date: str | None = None,
) -> dict:
    """Record a payment against a document (invoice).

    Args:
        document_id: The document (invoice) ID.
        amount: Payment amount.
        payment_method: Payment method (e.g. "check", "credit_card", "ach").
        reference: Reference number (check number, transaction ID, etc.).
        date: Payment date (YYYY-MM-DD). Defaults to today.
    """
    params: dict = {
        "organizationId": ORG_ID,
        "documentId": document_id,
        "amount": amount,
    }
    if payment_method:
        params["paymentMethod"] = payment_method
    if reference:
        params["reference"] = reference
    if date:
        params["date"] = date

    return await call_pave(
        "createPayment",
        params=params,
        fields={"id": {}, "amount": {}, "date": {}},
    )


@mcp.tool()
async def jt_get_payments(
    document_id: str | None = None,
    job_id: str | None = None,
    first: int = 50,
) -> list[dict]:
    """List payments, optionally filtered by document or job.

    Args:
        document_id: Filter by document (invoice).
        job_id: Filter by job.
        first: Max results.
    """
    filter_obj: dict = {}
    if document_id:
        filter_obj["documentId"] = {"eq": document_id}
    if job_id:
        filter_obj["jobId"] = {"eq": job_id}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "payments",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "amount": {},
                "date": {},
                "paymentMethod": {},
                "reference": {},
                "documentId": {},
            }
        },
    )
    return flatten_nodes(result)
