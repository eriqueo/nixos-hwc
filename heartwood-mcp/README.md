# Heartwood MCP — JobTread PAVE API Server

MCP server wrapping the JobTread PAVE API for Heartwood Craft LLC. Replaces the $50/month datax connector with a self-hosted, Heartwood-specific version.

## Purpose

Expose 64 typed tools over MCP (stdio or SSE) that let Claude interact with JobTread — accounts, jobs, budgets, documents, tasks, time entries, daily logs, files, and more.

## Boundaries

- Read/write operations against the Heartwood Craft organization only (org ID `22Nm3uFevXMb`)
- All mutations run as Eric (via `viaUserId`) with notifications disabled
- Grant key is **never** hardcoded — always read from `JT_GRANT_KEY` env var

## Setup

```bash
# Install dependencies
pip install "mcp[cli]" httpx

# Set the grant key
export JT_GRANT_KEY="your-grant-key-here"

# Run in stdio mode (for Claude Code)
python server.py

# Run in SSE mode (for remote access)
python server.py --sse  # serves on port 8200
```

## Testing

```bash
# MCP Inspector
npx @modelcontextprotocol/inspector python server.py

# Quick smoke tests (in order):
# 1. Simple read, no params — verifies auth
jt_get_cost_codes

# 2. Search with params
jt_search_jobs(search_term="Margulies")

# 3. Write test
jt_create_daily_log(job_id="<test-job-id>")
```

## Structure

```
heartwood-mcp/
├── server.py          # Entry point — registers tools, runs transport
├── app.py             # FastMCP instance (imported by tool modules)
├── pave.py            # PAVE HTTP client, envelope builder, error handling
├── constants.py       # Heartwood IDs (org, user, custom fields, timezone)
├── pyproject.toml     # Dependencies
├── README.md
└── tools/
    ├── __init__.py
    ├── accounts.py    # create, update, get, get_details (4)
    ├── contacts.py    # create, get, get_details (3)
    ├── locations.py   # create, get (2)
    ├── jobs.py        # create, search, get_details, get_active, set_parameters (5)
    ├── budget.py      # add_line_items, get_budget, update/delete item, cost codes/types, units (7)
    ├── documents.py   # create, update, get, get_line_items, get_templates (5)
    ├── payments.py    # create, get (2)
    ├── tasks.py       # create, update_progress, get, get_details, get_templates (5)
    ├── time_entries.py # create, get, get_details, update, delete, get_summary (6)
    ├── daily_logs.py  # create, get, get_details, update, get_summary (5)
    ├── files.py       # upload, update, copy, read, attach, get, get_tags, get_folders, create_folder (9)
    ├── comments.py    # create, get, get_details (3)
    ├── dashboards.py  # create, update, get (3)
    ├── custom_fields.py # get, search_by (2)
    └── org.py         # get_users, list_orgs, switch_org (3)
```

**Total: 64 tools**

## Heartwood-Specific Enhancements

- **Account creation**: Automatically calls `updateAccount` after `createAccount` to set custom fields (PAVE doesn't accept them on creation)
- **Budget validation**: Checks that numeric fields are numbers (not strings), groupName uses ` > ` separator with spaces
- **Time entries**: Default timezone `America/Denver` (Bozeman, MT)
- **Organization**: Hardcoded to Heartwood Craft org `22Nm3uFevXMb` for all operations

## Changelog

- 2026-03-25: Initial implementation — 64 tools across 15 modules, stdio + SSE transport
