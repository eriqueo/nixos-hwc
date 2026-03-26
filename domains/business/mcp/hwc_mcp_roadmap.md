# System 7: Heartwood MCP Server

## Unified Interface to All Business Systems

**Status:** Phase 1 DEPLOYED and operational (63 JT tools, port 6100, since 2026-03-25)
**Replaces:** datax JT MCP connector ($50/month) + ad-hoc PAVE construction in n8n workflows
**Last updated:** March 26, 2026

-----

## The Problem

Every n8n workflow, Claude Code session, and Claude chat that needs to interact with JobTread must independently construct PAVE API calls — a proprietary query language with inconsistent patterns (field names vs IDs, nested response paths, silent failures on HTTP 200). Two separate Claude Code sessions have struggled with this. Meanwhile, other homeserver services (Paperless-ngx, Firefly III, Postgres) each have their own REST APIs with their own quirks.

The result: tribal knowledge spread across workflow JSON files, unreliable integrations, and every new workflow reinventing the same translation layer.

## The Solution

A single MCP (Model Context Protocol) server running on the homeserver that exposes every business system operation as a typed, documented tool. Any consumer — Claude (chat, Code, API), n8n workflows, future apps — talks to one interface. The MCP server handles all API translation, authentication, error handling, and logging internally.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                    MCP CLIENTS                        │
│                                                      │
│  Claude Chat    Claude Code    n8n Workflows    Apps  │
│  (this conv)    (CLI)          (via webhook)    (PWA) │
└──────────┬──────────┬──────────┬──────────┬──────────┘
           │          │          │          │
           ▼          ▼          ▼          ▼
┌──────────────────────────────────────────────────────┐
│              HEARTWOOD MCP SERVER                     │
│              (NixOS homeserver)                       │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │ TIER 1: Atomic Operations (API wrappers)        │ │
│  │                                                 │ │
│  │ JT (63 tools)  │ Paperless │ Firefly │ Slack   │ │
│  │ via PAVE       │ via REST  │ via REST│ via API │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │ TIER 2: Compound Operations (n8n-backed)        │ │
│  │                                                 │ │
│  │ hwc_create_full_customer                        │ │
│  │ hwc_push_estimate                               │ │
│  │ hwc_create_vendor_bill                          │ │
│  │ hwc_process_voice_note                          │ │
│  │ hwc_process_receipt                             │ │
│  │ hwc_run_follow_up_check                         │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │ TIER 3: Query & Intelligence Tools              │ │
│  │                                                 │ │
│  │ Postgres views │ Server commands │ File system  │ │
│  │ Pipeline data  │ Bash/Python     │ Consume dirs │ │
│  └─────────────────────────────────────────────────┘ │
│                                                      │
│  ┌─────────────────────────────────────────────────┐ │
│  │ SHARED INFRASTRUCTURE                           │ │
│  │                                                 │ │
│  │ Auth (grant keys, API tokens)                   │ │
│  │ Error handling (PAVE 200-with-errors, retries)  │ │
│  │ Logging (→ Postgres workflow_log)               │ │
│  │ Response flattening (nested → clean)            │ │
│  └─────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

## Three Tiers of Tools

### Tier 1 — Atomic Operations (Direct API Wrappers)

One tool = one API call. These replicate what the datax MCP server does today, plus add Paperless, Firefly, and other services.

**Characteristics:**

- Typed parameters with validation
- Auth injected internally (grant keys, API tokens — never exposed to caller)
- Error detection and clean error messages
- Response flattened to useful fields (no nested PAVE paths)
- Logged to Postgres `workflow_log`

### Tier 2 — Compound Operations (n8n-Backed)

One tool = an n8n workflow that orchestrates multiple Tier 1 calls plus logging, notifications, and cross-system sync.

**Characteristics:**

- MCP tool triggers n8n webhook → n8n executes workflow → returns structured result
- Uses n8n's "Respond to Webhook" node for synchronous responses
- Encapsulates multi-step business logic (e.g., "create customer" = 5 JT calls + Slack + Postgres)
- Caller doesn't know or care about the internal orchestration
- Can leverage anything n8n can do: bash commands, Python scripts, Claude API calls, file operations

### Tier 3 — Query & Intelligence Tools

Read-only tools that query the analytical layer and server capabilities.

**Characteristics:**

- Direct Postgres queries against views and tables
- Server status and capability queries
- File system operations (read consume folders, check exports)
- No side effects — safe to call anytime

-----

## Tier 1: JT Tool Inventory (63 Operations)

Derived from the datax MCP server tool definitions. Each tool maps to one PAVE API call as documented in `jobtread_api_reference.md`.

### Accounts & Contacts

|Tool                    |Params                        |Notes                                   |
|------------------------|------------------------------|----------------------------------------|
|`jt_create_account`     |name, type(customer/vendor)   |Org ID injected automatically           |
|`jt_update_account`     |id, name?, customFieldValues? |Handles the ID-based custom field format|
|`jt_get_accounts`       |searchTerm, type?             |Partial name match                      |
|`jt_create_contact`     |accountId, name, customFields?|Field names (case-insensitive), not IDs |
|`jt_get_contacts`       |accountId?                    |                                        |
|`jt_get_contact_details`|contactId                     |All custom fields + methods             |

### Locations

|Tool                |Params                              |Notes                         |
|--------------------|------------------------------------|------------------------------|
|`jt_create_location`|accountId, address, name, contactId?|Required before creating a job|
|`jt_get_locations`  |accountId?                          |                              |

### Jobs

|Tool                   |Params                                                      |Notes                                                     |
|-----------------------|------------------------------------------------------------|----------------------------------------------------------|
|`jt_create_job`        |locationId, name, customFields?, description?, number?      |Field names (not IDs) for custom fields                   |
|`jt_search_jobs`       |searchTerm, searchBy?(name/number), status?(open/closed/all)|                                                          |
|`jt_get_job_details`   |jobId                                                       |Full record: location, account, custom fields, files, docs|
|`jt_get_active_jobs`   |(none)                                                      |Jobs with approved customer orders                        |
|`jt_set_job_parameters`|jobId, parameters[]                                         |For formula-driven budgets                                |

### Budget & Cost Items

|Tool                                |Params                                                      |Notes                                                                                          |
|------------------------------------|------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
|`jt_add_budget_line_items`          |jobId, lineItems[]                                          |**Critical: estimator push.** Enforces pipe-delimited names, numeric types, `>` group separator|
|`jt_get_job_budget`                 |jobId                                                       |Groups + items with costs, prices, margins                                                     |
|`jt_get_cost_items`                 |searchName?, costCodeId?, costTypeId?                       |Org catalog, not job budget                                                                    |
|`jt_create_cost_item`               |name, costCodeId, costTypeId, unitId?, unitCost?, unitPrice?|Adds to org catalog                                                                            |
|`jt_get_cost_codes`                 |(none)                                                      |Returns all 26 codes with IDs                                                                  |
|`jt_get_cost_types`                 |(none)                                                      |Returns all 6 types with IDs                                                                   |
|`jt_get_units`                      |(none)                                                      |Returns all 11 units with IDs                                                                  |
|`jt_get_cost_group_templates`       |(none)                                                      |Budget templates                                                                               |
|`jt_get_cost_group_template_details`|costGroupId                                                 |Items inside a template                                                                        |

### Documents

|Tool                        |Params                                                                                                                                                                             |Notes                                                                     |
|----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|
|`jt_create_document`        |jobId, type, accountId?, documentTemplateId?, costCodeIds?, costGroupNames?, costItemIds?, costItemOverrides?, date?, name?, subject?, description?, footer?, externalId?, taxRate?|Types: customerOrder, customerInvoice, vendorOrder, vendorBill, bidRequest|
|`jt_update_document`        |documentId, status?, description?, costItemUpdates?, pushToQbo?                                                                                                                    |                                                                          |
|`jt_get_documents`          |jobId?, type?                                                                                                                                                                      |                                                                          |
|`jt_get_document_line_items`|documentId                                                                                                                                                                         |Groups + items for that doc                                               |
|`jt_get_document_templates` |type                                                                                                                                                                               |Get template ID before creating doc                                       |

### Payments

|Tool               |Params                                              |Notes                                  |
|-------------------|----------------------------------------------------|---------------------------------------|
|`jt_create_payment`|amount, date, documentId, description?, paymentType?|Auto-detects credit/debit from doc type|
|`jt_get_payments`  |jobId?, documentId?, accountId?                     |                                       |

### Tasks

|Tool                          |Params                                                                                                   |Notes                            |
|------------------------------|---------------------------------------------------------------------------------------------------------|---------------------------------|
|`jt_create_task`              |name, targetType, targetId?, description?, assignees?, startDate?, endDate?, isToDo?, isGroup?, progress?|                                 |
|`jt_update_task_progress`     |taskId, progress?, name?, description?, startDate?, endDate?                                             |                                 |
|`jt_get_tasks`                |jobId?, status?, assigneeUserId?                                                                         |                                 |
|`jt_get_task_details`         |taskId                                                                                                   |Includes assignees + dependencies|
|`jt_get_schedule_templates`   |(none)                                                                                                   |                                 |
|`jt_get_todo_templates`       |(none)                                                                                                   |                                 |
|`jt_get_task_template_details`|taskTemplateId                                                                                           |Tasks inside a template          |

### Time Entries

|Tool                       |Params                                                                    |Notes                          |
|---------------------------|--------------------------------------------------------------------------|-------------------------------|
|`jt_create_time_entry`     |jobId, userId, startedAt, endedAt, notes?, costItemId?, type?, isApproved?|ISO 8601 with timezone required|
|`jt_get_time_entries`      |jobId?, userId?, startDate?, endDate?, isApproved?                        |                               |
|`jt_get_time_entry_details`|timeEntryId                                                               |                               |
|`jt_get_time_summary`      |startDate, endDate, groupBy?, jobId?, userId?                             |                               |

### Daily Logs

|Tool                       |Params                                       |Notes                         |
|---------------------------|---------------------------------------------|------------------------------|
|`jt_create_daily_log`      |jobId, date, notes, customFields?            |Field names (case-insensitive)|
|`jt_get_daily_logs`        |jobId?, userId?, startDate?, endDate?        |                              |
|`jt_get_daily_log_details` |logId                                        |                              |
|`jt_get_daily_logs_summary`|startDate, endDate, groupBy?, jobId?, userId?|                              |

### Files

|Tool                           |Params                                                         |Notes                           |
|-------------------------------|---------------------------------------------------------------|--------------------------------|
|`jt_upload_file`               |targetId, targetType, url, name?, folder?, fileTagIds?         |Requires public HTTPS URL       |
|`jt_update_file`               |fileId, name?, folder?, fileTagIds?, description?              |                                |
|`jt_copy_file`                 |sourceFileId, targetId, targetType, name?, folder?, fileTagIds?|                                |
|`jt_read_file`                 |fileId                                                         |Returns content inline          |
|`jt_attach_file_to_budget_item`|fileId, jobId, targetId, targetType(costItem/costGroup)        |Upload to job first, then attach|
|`jt_get_files`                 |jobId?, documentId?, folder?                                   |                                |
|`jt_get_file_tags`             |(none)                                                         |Org-level tags                  |
|`jt_get_job_folders`           |jobId                                                          |Available folder names          |

### Comments

|Tool                    |Params                                                                            |Notes              |
|------------------------|----------------------------------------------------------------------------------|-------------------|
|`jt_create_comment`     |message, name, targetId, targetType, isPinned?, parentCommentId?, visibility flags|                   |
|`jt_get_comments`       |targetId?, targetType?                                                            |                   |
|`jt_get_comment_details`|commentId                                                                         |Full thread + files|

### Dashboards

|Tool                 |Params                  |Notes|
|---------------------|------------------------|-----|
|`jt_create_dashboard`|name, tiles(JSON string)|     |
|`jt_update_dashboard`|id, tiles(JSON string)  |     |
|`jt_get_dashboards`  |name?                   |     |

### Custom Fields & Search

|Tool                       |Params                                                  |Notes                         |
|---------------------------|--------------------------------------------------------|------------------------------|
|`jt_get_custom_fields`     |targetType                                              |Discover field IDs dynamically|
|`jt_search_by_custom_field`|entityType, customFieldName, customFieldValue, operator?|                              |

### Organization & Users

|Tool                    |Params        |Notes|
|------------------------|--------------|-----|
|`jt_get_users`          |searchTerm?   |     |
|`jt_list_organizations` |(none)        |     |
|`jt_switch_organization`|organizationId|     |

-----

## Tier 1: Paperless-ngx Tools (Planned)

|Tool                            |Params                                                            |Notes                                 |
|--------------------------------|------------------------------------------------------------------|--------------------------------------|
|`paperless_search_documents`    |query?, tags?, correspondent?, document_type?, date_range?        |Full-text search across OCR'd docs    |
|`paperless_get_document`        |document_id                                                       |Full metadata + custom fields         |
|`paperless_get_document_content`|document_id                                                       |OCR text content                      |
|`paperless_update_document`     |document_id, tags?, correspondent?, document_type?, custom_fields?|                                      |
|`paperless_upload_document`     |file_url, title?, tags?, correspondent?, document_type?           |Drop into consume folder or API upload|
|`paperless_get_tags`            |(none)                                                            |All tags with hierarchy               |
|`paperless_get_correspondents`  |(none)                                                            |All vendors/senders                   |
|`paperless_get_document_types`  |(none)                                                            |                                      |

## Tier 1: Firefly III Tools (Planned)

|Tool                        |Params                                                                                                                      |Notes                     |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------|--------------------------|
|`firefly_create_transaction`|type(withdrawal/deposit/transfer), amount, source_account, destination_account, description, date, category?, budget?, tags?|                          |
|`firefly_get_transactions`  |start?, end?, type?, account_id?                                                                                            |                          |
|`firefly_get_accounts`      |type?(asset/expense/revenue)                                                                                                |                          |
|`firefly_create_category`   |name                                                                                                                        |                          |
|`firefly_get_budgets`       |(none)                                                                                                                      |                          |
|`firefly_get_summary`       |start, end                                                                                                                  |P&L summary for date range|

## Tier 1: Infrastructure Tools

|Tool                |Params                |Notes                   |
|--------------------|----------------------|------------------------|
|`slack_send_message`|channel, text, blocks?|Slack webhook           |
|`twilio_send_sms`   |to, body              |For lead response       |
|`server_run_command`|command, args?        |Sandboxed bash execution|
|`server_run_script` |script_path, args?    |Python/bash scripts     |

-----

## Tier 2: Compound Operations (n8n-Backed)

Each tool triggers an n8n workflow via webhook and returns the structured result.

|Tool                      |n8n Workflow |What It Does                                                                                                                 |
|--------------------------|-------------|-----------------------------------------------------------------------------------------------------------------------------|
|`hwc_create_full_customer`|#09          |createAccount → updateAccount (custom fields) → createContact → createLocation → createJob → Slack → Postgres                |
|`hwc_push_estimate`       |#08b         |Duplicate check → addBudgetLineItems → Postgres archive → Slack                                                              |
|`hwc_create_vendor_bill`  |#13 (future) |Ensure vendor account → createDocument(vendorBill) → createPayment → uploadFile → attachToDocument → update Paperless → Slack|
|`hwc_process_voice_note`  |#12          |Claude extraction → confidence check → createTimeEntry (loop) → createDailyLog → Postgres → Slack                            |
|`hwc_process_receipt`     |#13 (future) |Paperless OCR → Claude job matching → confidence routing → JT vendor bill → Firefly transaction → Slack                      |
|`hwc_run_follow_up_check` |#11 (planned)|Query stale leads → format report → Slack                                                                                    |
|`hwc_advance_job_phase`   |(new)        |Update JT job Phase custom field → create next-stage tasks → Slack                                                           |

### How Tier 2 Works

```
MCP Client calls: hwc_create_vendor_bill({ vendor: "Kenyon Noble", amount: 30, job: "Margulies #280", ... })
  → MCP server POSTs to n8n webhook: /webhook/hwc-create-vendor-bill
    → n8n workflow executes:
      1. Search JT for vendor account (or create)
      2. Search JT for job by name/number
      3. Create vendor bill document
      4. Record payment
      5. Upload receipt from Paperless
      6. Update Paperless custom fields
      7. Create Firefly transaction
      8. Log to Postgres workflow_log
      9. Send Slack notification
    → n8n responds to webhook with: { success: true, vendorBillId: "...", paymentId: "...", ... }
  → MCP server returns clean response to caller
```

The caller (Claude, another workflow, an app) never knows this was 9 steps across 5 systems. It's one tool call.

-----

## Tier 3: Query & Intelligence Tools

|Tool                          |Source                           |What It Returns                                                |
|------------------------------|---------------------------------|---------------------------------------------------------------|
|`hwc_get_pipeline_summary`    |Postgres `pipeline_summary` view |Jobs by stage, total value, avg margin                         |
|`hwc_get_lead_funnel`         |Postgres `lead_funnel` view      |Monthly conversion rates                                       |
|`hwc_get_channel_roi`         |Postgres `channel_roi` view      |Revenue by marketing channel                                   |
|`hwc_get_job_costing`         |Postgres daily_logs + estimates  |Estimated vs actual hours by trade for a job                   |
|`hwc_get_catalog_items`       |Postgres/SQLite catalog          |Cost items with rates, triggers, formulas                      |
|`hwc_get_active_project_state`|Postgres projects + project_state|Current state for a specific job                               |
|`hwc_get_server_status`       |bash                             |Service health check (n8n, Paperless, Firefly, Postgres, Caddy)|
|`hwc_search_documents`        |Paperless API                    |Cross-reference: "find all receipts for job X"                 |

-----

## Implementation Plan

### Phase 1: JT MCP Server (Replace datax — $50/mo savings)

1. Scaffold MCP server using `@modelcontextprotocol/sdk` (Node.js/TypeScript)
1. Implement shared PAVE infrastructure: envelope builder, auth injection, error checker, response flattener, logger
1. Implement the 63 JT tools using PAVE patterns from `jobtread_api_reference.md`
1. Add Heartwood-specific enhancements:
- `jt_create_account` automatically calls `jt_update_account` for custom fields (fixes the #1 gotcha)
- `jt_add_budget_line_items` validates pipe-delimited naming, numeric types, group separators
- All tools inject org ID (`22Nm3uFevXMb`), user ID (`22Nm3uFeRB7s`), `notify: false`
1. Deploy on homeserver via Caddy + Tailscale (SSE transport for remote, stdio for local Claude Code)
1. Test by connecting to Claude chat (replace datax connector)
1. Cancel datax subscription

### Phase 2: Add Paperless + Firefly Tools

1. Implement Paperless Tier 1 tools (REST API wrappers)
1. Implement Firefly Tier 1 tools (REST API wrappers)
1. Add infrastructure tools (Slack, server commands)

### Phase 3: Add Compound Operations (Tier 2)

1. Refactor existing n8n workflows to accept webhook input and return structured responses
1. Implement Tier 2 MCP tools that trigger n8n workflows
1. Test compound operations end-to-end

### Phase 4: Add Query Tools (Tier 3)

1. Implement Postgres query tools against existing views
1. Add server status and file system tools
1. Build any missing Postgres views needed by the tools

### Phase 5: Migrate n8n Workflows

1. Update existing n8n workflows to use the MCP server's Tier 1 tools (via HTTP) instead of raw PAVE calls
1. Simplify workflow logic — move PAVE construction out of n8n into the MCP server
1. New workflows only use MCP tools, never raw API calls

-----

## Technical Decisions

### Transport

- **SSE (Server-Sent Events)** for remote access (Claude chat, Claude API calls from n8n)
- **stdio** for local access (Claude Code on Eric's machine via Tailscale SSH)
- Served via Caddy reverse proxy on the homeserver, accessible across Tailnet

### Language

- **TypeScript** using `@modelcontextprotocol/sdk`
- Alternatively: Python with `mcp` package if TypeScript MCP SDK has gaps
- Decision deferred until Phase 1 scaffolding

### Auth

- JT grant key stored in server environment, never exposed to callers
- Paperless API token stored in server environment
- Firefly API token stored in server environment
- MCP server itself protected by Tailscale (only accessible on Tailnet) + optional API key header

### Logging

- Every tool call logged to Postgres `workflow_log` table
- Fields: tool_name, params (sanitized), response summary, success/error, duration_ms, caller_context
- Enables debugging, audit trail, and usage analytics

### Error Handling

- PAVE 200-with-errors detected and converted to clean error messages
- Retries with exponential backoff for transient failures
- Structured error responses: `{ success: false, error: "human message", code: "PAVE_ERROR", details: {...} }`

-----

## What This Enables

Once the MCP server is running, any Claude session (chat, Code, or API) can:

- "Show me my current pipeline" → `hwc_get_pipeline_summary`
- "Create a customer for Jane Doe at 123 Main St, she's a referral" → `hwc_create_full_customer`
- "Push the estimate for job #281" → `hwc_push_estimate`
- "Log 4 hours of tile work on the Margulies job for today" → `jt_create_time_entry`
- "Find all Kenyon Noble receipts from this month" → `hwc_search_documents`
- "What's my actual vs estimated hours on the Margulies job?" → `hwc_get_job_costing`
- "Create a vendor bill for $30 at Kenyon Noble on the Margulies job" → `hwc_create_vendor_bill`
- "Is Postgres running?" → `hwc_get_server_status`

Your homeserver becomes a business operations API that any LLM — or you — can talk to.

-----

## Relationship to Other Systems

|System                      |Relationship to MCP Server                                                 |
|----------------------------|---------------------------------------------------------------------------|
|System 1: Estimate Assembler|Calls `jt_add_budget_line_items` via MCP (or n8n webhook that uses MCP)    |
|System 2: Client Journey    |Tier 2 tools map to journey stages (`hwc_create_full_customer` = Stage 1→2)|
|System 3: Financial Ops     |Tier 3 queries surface financial data; Tier 2 creates vendor bills         |
|System 4: Marketing Ops     |Tier 3 `hwc_get_channel_roi` surfaces marketing ROI                        |
|System 5: Public Calculator |Tier 2 `hwc_create_full_customer` processes calculator leads               |
|System 6: n8n Automation    |Tier 2 tools ARE n8n workflows; n8n can also call Tier 1 tools             |
|Paperless-ngx               |Tier 1 tools wrap Paperless REST API                                       |
|Firefly III                 |Tier 1 tools wrap Firefly REST API                                         |

-----

*This spec is a companion to `jobtread_api_reference.md` (PAVE patterns), `PAPERLESS_INTEGRATION_SPEC.docx` (Paperless setup + receipt pipeline), and `VOICE_NOTE_PIPELINE_SPEC.md` (voice-to-JT pipeline). Together they define the full integration architecture for Heartwood Craft's business operating system.*
