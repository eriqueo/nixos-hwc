"""Document tools — invoices, estimates, purchase orders, etc."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_create_document(
    job_id: str,
    document_type: str,
    account_id: str,
    template_id: str | None = None,
    name: str | None = None,
) -> dict:
    """Create a document (invoice, estimate, purchase order, etc.) on a job.

    Args:
        job_id: The job ID.
        document_type: Type of document: "invoice", "estimate", "purchaseOrder", "changeOrder".
        account_id: The account (customer/vendor) this document is for.
        template_id: Optional template ID to use.
        name: Optional document name/title.
    """
    params: dict = {
        "organizationId": ORG_ID,
        "jobId": job_id,
        "type": document_type,
        "accountId": account_id,
    }
    if template_id:
        params["templateId"] = template_id
    if name:
        params["name"] = name

    return await call_pave(
        "createDocument",
        params=params,
        fields={"id": {}, "number": {}, "name": {}, "type": {}, "status": {}},
    )


@mcp.tool()
async def jt_update_document(
    document_id: str,
    status: str | None = None,
    name: str | None = None,
) -> dict:
    """Update a document's status or name.

    Args:
        document_id: The document ID.
        status: New status (e.g. "draft", "sent", "approved", "void").
        name: New name.
    """
    params: dict = {"id": document_id}
    if status is not None:
        params["status"] = status
    if name is not None:
        params["name"] = name

    return await call_pave(
        "updateDocument",
        params=params,
        fields={"id": {}, "name": {}, "status": {}},
    )


@mcp.tool()
async def jt_get_documents(
    job_id: str | None = None,
    document_type: str | None = None,
    status: str | None = None,
    first: int = 50,
) -> list[dict]:
    """List documents, optionally filtered by job, type, or status.

    Args:
        job_id: Filter by job.
        document_type: Filter by type ("invoice", "estimate", etc.).
        status: Filter by status.
        first: Max results.
    """
    filter_obj: dict = {}
    if job_id:
        filter_obj["jobId"] = {"eq": job_id}
    if document_type:
        filter_obj["type"] = {"eq": document_type}
    if status:
        filter_obj["status"] = {"eq": status}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "documents",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "number": {},
                "name": {},
                "type": {},
                "status": {},
                "jobId": {},
                "accountId": {},
                "total": {},
                "createdAt": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_document_line_items(
    document_id: str,
    first: int = 200,
) -> list[dict]:
    """Get line items for a specific document.

    Args:
        document_id: The document ID.
        first: Max results.
    """
    result = await call_pave(
        "documentLineItems",
        params={"filter": {"documentId": {"eq": document_id}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "description": {},
                "quantity": {},
                "unitPrice": {},
                "amount": {},
                "groupName": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_document_templates(
    document_type: str | None = None,
    first: int = 50,
) -> list[dict]:
    """Get available document templates.

    Args:
        document_type: Filter by type ("invoice", "estimate", etc.).
        first: Max results.
    """
    filter_obj: dict = {"organizationId": {"eq": ORG_ID}}
    if document_type:
        filter_obj["type"] = {"eq": document_type}

    result = await call_pave(
        "documentTemplates",
        params={"filter": filter_obj, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "type": {},
            }
        },
    )
    return flatten_nodes(result)
