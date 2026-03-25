"""File tools — upload, manage, and attach files."""

from __future__ import annotations

from app import mcp
from constants import ORG_ID
from pave import call_pave, flatten_nodes


@mcp.tool()
async def jt_upload_file(
    job_id: str,
    name: str,
    url: str,
    content_type: str | None = None,
    folder_id: str | None = None,
) -> dict:
    """Upload/register a file on a job by URL.

    Args:
        job_id: The job ID.
        name: File name.
        url: URL of the file to attach.
        content_type: MIME type of the file.
        folder_id: Optional folder ID to place the file in.
    """
    params: dict = {
        "organizationId": ORG_ID,
        "jobId": job_id,
        "name": name,
        "url": url,
    }
    if content_type:
        params["contentType"] = content_type
    if folder_id:
        params["folderId"] = folder_id

    return await call_pave(
        "createFile",
        params=params,
        fields={"id": {}, "name": {}, "url": {}},
    )


@mcp.tool()
async def jt_update_file(
    file_id: str,
    name: str | None = None,
    folder_id: str | None = None,
    tags: list[str] | None = None,
) -> dict:
    """Update a file's name, folder, or tags.

    Args:
        file_id: The file ID.
        name: New file name.
        folder_id: Move to this folder.
        tags: List of tag names to set.
    """
    params: dict = {"id": file_id}
    if name is not None:
        params["name"] = name
    if folder_id is not None:
        params["folderId"] = folder_id
    if tags is not None:
        params["tags"] = tags

    return await call_pave(
        "updateFile",
        params=params,
        fields={"id": {}, "name": {}},
    )


@mcp.tool()
async def jt_copy_file(
    file_id: str,
    target_job_id: str,
    target_folder_id: str | None = None,
) -> dict:
    """Copy a file to another job.

    Args:
        file_id: The source file ID.
        target_job_id: The destination job ID.
        target_folder_id: Optional destination folder ID.
    """
    params: dict = {
        "fileId": file_id,
        "jobId": target_job_id,
    }
    if target_folder_id:
        params["folderId"] = target_folder_id

    return await call_pave(
        "copyFile",
        params=params,
        fields={"id": {}, "name": {}, "url": {}},
    )


@mcp.tool()
async def jt_read_file(file_id: str) -> dict:
    """Get details and URL for a specific file.

    Args:
        file_id: The file ID.
    """
    result = await call_pave(
        "files",
        params={"filter": {"id": {"eq": file_id}}, "first": 1},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "url": {},
                "contentType": {},
                "size": {},
                "jobId": {},
                "folderId": {},
                "tags": {"nodes": {"id": {}, "name": {}}},
                "createdAt": {},
            }
        },
    )
    nodes = flatten_nodes(result)
    return nodes[0] if nodes else {}


@mcp.tool()
async def jt_attach_file_to_budget_item(
    file_id: str,
    budget_item_id: str,
) -> dict:
    """Attach a file to a budget line item.

    Args:
        file_id: The file ID to attach.
        budget_item_id: The budget item ID.
    """
    return await call_pave(
        "attachFile",
        params={
            "fileId": file_id,
            "entityType": "budgetItem",
            "entityId": budget_item_id,
        },
        fields={"id": {}},
    )


@mcp.tool()
async def jt_get_files(
    job_id: str | None = None,
    folder_id: str | None = None,
    first: int = 100,
) -> list[dict]:
    """List files, optionally filtered by job or folder.

    Args:
        job_id: Filter by job.
        folder_id: Filter by folder.
        first: Max results.
    """
    filter_obj: dict = {}
    if job_id:
        filter_obj["jobId"] = {"eq": job_id}
    if folder_id:
        filter_obj["folderId"] = {"eq": folder_id}

    params: dict = {"first": first}
    if filter_obj:
        params["filter"] = filter_obj

    result = await call_pave(
        "files",
        params=params,
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "url": {},
                "contentType": {},
                "size": {},
                "jobId": {},
                "folderId": {},
                "createdAt": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_get_file_tags(first: int = 100) -> list[dict]:
    """Get all available file tags for the organization.

    Args:
        first: Max results.
    """
    result = await call_pave(
        "fileTags",
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
async def jt_get_job_folders(
    job_id: str,
    first: int = 50,
) -> list[dict]:
    """Get folders for a job's file system.

    Args:
        job_id: The job ID.
        first: Max results.
    """
    result = await call_pave(
        "folders",
        params={"filter": {"jobId": {"eq": job_id}}, "first": first},
        fields={
            "nodes": {
                "id": {},
                "name": {},
                "parentId": {},
                "jobId": {},
            }
        },
    )
    return flatten_nodes(result)


@mcp.tool()
async def jt_create_folder(
    job_id: str,
    name: str,
    parent_id: str | None = None,
) -> dict:
    """Create a folder in a job's file system.

    Args:
        job_id: The job ID.
        name: Folder name.
        parent_id: Optional parent folder ID for nesting.
    """
    params: dict = {
        "organizationId": ORG_ID,
        "jobId": job_id,
        "name": name,
    }
    if parent_id:
        params["parentId"] = parent_id

    return await call_pave(
        "createFolder",
        params=params,
        fields={"id": {}, "name": {}, "jobId": {}},
    )