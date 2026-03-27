# n8n Workflow Registry

## Heartwood Craft — All Automation Workflows

**Last updated:** March 25, 2026
**n8n instance:** `https://hwc.ocelot-wahoo.ts.net` (port 5678, proxied on 2443)
**Webhook base:** `https://hwc.ocelot-wahoo.ts.net/webhook/`

**Last reconciled with live n8n instance:** March 25, 2026

-----

## Quick Reference

### Business Workflows

|#  |Name                        |n8n ID              |Status     |Active|Nodes|Trigger          |Systems Touched                             |
|---|----------------------------|---------------------|-----------|------|-----|-----------------|--------------------------------------------|
|08a|JT Data Provider (Jobs)     |`7JRWiYxyZeppoVE0`  |BUILT      |Yes   |5    |GET webhook      |JT → App                                    |
|—  |JT Data Provider (Customers)|`d5Gm2LRKHtcQhio9`  |DEPRECATED |No    |5    |GET webhook      |JT → App                                    |
|08b|Estimate Router             |`jbIqSwVByVnEAk7e`  |BUILT      |Yes   |16   |POST webhook     |App → JT + Postgres + Slack                 |
|09 |Calculator Lead             |`SoLwmxgkMILrOYbP`  |BUILT      |Yes   |16   |POST webhook     |Website → JT + Postgres + Slack             |
|10 |Lead Response               |`lead-response-automation`|BUILT |Yes   |29   |POST webhook     |JT → Claude → Postgres + Slack + SMS        |
|—  |SMS Handler                 |`incoming-sms-handler`|BUILT     |Yes   |14   |POST webhook     |Twilio → Postgres + Slack                   |
|11 |Follow-Up Reminders         |—                    |PLANNED    |—     |—    |Cron (daily 8am) |JT → Slack                                  |
|12 |Daily Voice Log             |`XAm7ehKjJers5NqC`  |BUILT      |Yes   |18   |POST webhook     |iOS → Claude → JT + Postgres + Slack        |
|13 |Paperless Document Processor|—                    |PLANNED    |—     |—    |POST webhook     |Paperless → Claude → JT + Firefly + Slack   |

### Marketing Workflows

|#  |Name                |n8n ID                    |Status |Active|Nodes|Trigger     |
|---|--------------------|--------------------------|-------|------|-----|------------|
|—  |Web Scraper         |`k2TN787tyntCyY1P`        |BUILT  |Yes   |29   |Various     |
|—  |Content Calendar    |`weekly-content-calendar`  |BUILT  |Yes   |23   |Scheduled   |
|—  |Intel Ingest        |`intelligence-pipeline-hwc`|BUILT  |No    |20   |Various     |
|—  |Content Generator   |`content-generator-hwc`    |BUILT  |No    |13   |Various     |

### Infrastructure Workflows

|#  |Name                     |n8n ID              |Status|Active|Nodes|Trigger       |
|---|-------------------------|---------------------|------|------|-----|--------------|
|—  |Health Monitor           |`KaGqsviVtFGp5d7l`  |BUILT |Yes   |16   |Scheduled     |
|—  |Alertmanager Router      |`YgoqxXkDtRkDrbpK`  |BUILT |Yes   |14   |POST webhook  |
|—  |Script Executor          |`zESbVHcPO88NL2Je`  |BUILT |Yes   |19   |POST webhook  |
|—  |Slack Notify (utility)   |`oPkQAoxLPnmpszRD`  |BUILT |Yes   |3    |Sub-workflow  |
|—  |Slack Approval Handler   |`8Gdamdg8MYFjhKIR`  |BUILT |Yes   |6    |POST webhook  |
|—  |Webhook→Slack (utility)  |`9qg7apJdVjzQGwkw`  |BUILT |Yes   |2    |POST webhook  |

### Home Automation Workflows

|#  |Name              |n8n ID              |Status|Active|Nodes|Trigger      |
|---|------------------|---------------------|------|------|-----|-------------|
|—  |Frigate → Slack   |`mNJKL8puSZpWhsR2`  |BUILT |Yes   |7    |POST webhook |
|—  |Events Digest     |`DxDOkTqP6UzJgxfG`  |BUILT |Yes   |10   |Scheduled    |
|—  |Media Pipeline    |`n14heZ9wzJ8Uyemo`  |BUILT |Yes   |22   |Various      |

**Total: 20 workflows (16 active, 4 inactive)**

-----

## Execution Health (as of March 25, 2026)

|Workflow|Total Executions|Success|Errors|Error Rate|Last Run|
|--------|---------------|-------|------|----------|--------|
|#08a JT Data Provider|11|1|10|**Fixed 2026-03-26** — was using wrong PAVE path (`job` instead of `account.jobs`)|2026-03-26|
|#08b Estimate Router|4|1|3|**75%**|2026-03-24|
|#09 Calculator Lead|10|1|9|**90%**|2026-03-24|
|#10 Lead Response|many|5+ recent|0|**0%** (healthy)|2026-03-25|
|#12 Voice Log|1|0|1|**100%**|2026-03-24|

**Action needed:** #08b, #09, and #12 have high error rates. #08a fixed 2026-03-26. #10 is running cleanly.

-----

## Workflow Details

### Workflow #08a — JT Data Provider (Jobs)

|Field            |Value                                                                    |
|-----------------|-------------------------------------------------------------------------|
|**n8n ID**       |`7JRWiYxyZeppoVE0`                                                      |
|**Status**       |BUILT — Active                                                           |
|**Trigger**      |GET webhook                                                              |
|**Webhook URL**  |`/webhook/jt-jobs`                                                       |
|**Purpose**      |Fetch JT jobs for a given customer, for the estimate assembler dropdowns |
|**Input**        |GET with query param `?customerId=...` + `x-api-key` header             |
|**Output**       |JSON: `{ jobs: [...], count: N, customerId: "..." }`                     |
|**Systems**      |JT (PAVE read) → HTTP response to app                                   |
|**Auth**         |`x-api-key` header validated against `$env.ESTIMATOR_API_KEY`            |
|**Executions**   |4 total, 0 success, 4 errors                                            |
|**Last run**     |2026-03-24                                                               |
|**MCP migration**|Tier 1 tool: `jt_search_jobs` could replace this entirely               |

**Actual nodes (5):**

1. `Webhook: Get Jobs` — GET /webhook/jt-jobs, responseMode=responseNode
2. `Validate Auth (Jobs)` — Code: check x-api-key, extract customerId from query
3. `Fetch JT Jobs` — HTTP POST to PAVE: query jobs by accountId, return id/number/name/status/customFields
4. `Transform Jobs` — Code: filter by Phase (estimating phases 1-3 only), sort by number desc
5. `Respond Jobs` — respondToWebhook with JSON

**Note:** Only returns jobs filtered by customerId. The customers dropdown is served by a separate (now inactive) workflow `JT_return_customers`.

-----

### Deprecated: JT Data Provider (Customers)

|Field            |Value                                                            |
|-----------------|-----------------------------------------------------------------|
|**n8n ID**       |`d5Gm2LRKHtcQhio9`                                              |
|**Status**       |DEPRECATED — Inactive                                            |
|**Trigger**      |GET webhook                                                      |
|**Webhook URL**  |`/webhook/jt-customers`                                          |
|**Purpose**      |Fetch JT customer accounts with locations for estimator dropdowns|
|**Executions**   |0 (never executed)                                               |
|**Notes**        |Was likely the "customers" half of the original 08a design. Now inactive — customers may be loaded differently in the app. |

**Actual nodes (5):**

1. `Webhook: Get Customers` — GET /webhook/jt-customers
2. `Build JT Query` — Code: PAVE query for org accounts where type=customer, with locations
3. `POST to JT API` — HTTP POST to PAVE
4. `Transform Customers` — Code: flatten accounts with locations, sort by name
5. `Respond Customers` — respondToWebhook with JSON

-----

### Workflow #08b — Estimate Router

|Field             |Value                                                                             |
|------------------|----------------------------------------------------------------------------------|
|**n8n ID**        |`jbIqSwVByVnEAk7e`                                                               |
|**Status**        |BUILT — Active                                                                    |
|**Trigger**       |POST webhook                                                                      |
|**Webhook URL**   |`/webhook/estimate-push`                                                          |
|**Purpose**       |Receive assembled estimate from React app, push to JT, archive to Postgres, Slack |
|**Input**         |`{ action: "push_estimate", jobId?, newJob?, jtPayload[], totals, projectState }` |
|**Output**        |`{ success, jtPushSuccess, jobId, jobNumber, itemsPushed, archived, requestId }`  |
|**Systems**       |App → JT (PAVE: createJob + addBudgetLineItems) + Postgres + Slack                |
|**Auth**          |`x-api-key` header validated against `$env.ESTIMATOR_API_KEY`                     |
|**Executions**    |4 total, 1 success, 3 errors                                                     |
|**Last run**      |2026-03-24                                                                        |
|**MCP migration** |Tier 2 compound tool: `hwc_push_estimate`                                         |

**Actual nodes (16):**

1. `Webhook: Estimate Push` — POST /webhook/estimate-push, responseMode=responseNode
2. `Validate Request` — Code: check action, jtPayload array, jobId or newJob.customerId
3. `Is New Job?` — IF: mode === "new_job"
4. `Build Create Job Query` — Code: build PAVE createJob query (new job branch)
5. `Create JT Job` — HTTP POST to PAVE (new job branch)
6. `Parse Created Job` — Code: extract created job ID/number/name
7. `Use Existing Job` — Code: passthrough for existing job branch
8. `Merge Job Data` — Code: merge from either branch
9. `Build Budget Push Query` — Code: build PAVE addBudgetLineItems query
10. `Push to JobTread` — HTTP POST to PAVE (continueOnFail=true, 30s timeout)
11. `Parse JT Result` — Code: check for PAVE errors, extract result
12. `Archive to Postgres` — Postgres INSERT into `estimates` table (continueOnFail=true)
13. `JT Push Success?` — IF: jtPushSuccess === true
14. `Slack: Success` — Slack post to #leads with job/customer/items/total
15. `Slack: Failure` — Slack post to #leads with error details
16. `Respond Success` — respondToWebhook with JSON summary

**CRITICAL GAP:** The registry spec calls for "Postgres pre-check for duplicate push" but **no such node exists**. Duplicate pushes will create duplicate line items in JT with no way to bulk-delete. This needs to be added.

-----

### Workflow #09 — Calculator Lead

|Field            |Value                                                                                                                                                  |
|-----------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
|**n8n ID**       |`SoLwmxgkMILrOYbP`                                                                                                                                    |
|**Status**       |BUILT — Active                                                                                                                                         |
|**Trigger**      |POST webhook                                                                                                                                           |
|**Webhook URL**  |`/webhook/calculator-lead`                                                                                                                             |
|**Purpose**      |Receive lead from public bathroom cost calculator, create full JT customer record, notify Slack                                                        |
|**Input**        |`{ contact: { name, email, phone, notes }, projectState: { project_type, bathroom_size, ... }, estimate: { low, high }, source: "website_calculator" }`|
|**Output**       |`{ success, jt_account_id, jt_job_id }`                                                                                                                |
|**Systems**      |Website → JT (6 PAVE calls) + Postgres (`hwc.calculator_leads`) + Slack (#leads)                                                                      |
|**Executions**   |10 total, 1 success, 9 errors                                                                                                                         |
|**Last run**     |2026-03-24                                                                                                                                             |
|**MCP migration**|Tier 2 compound tool: `hwc_create_full_customer`                                                                                                       |

**Actual nodes (16):**

1. `Webhook: Calculator Lead` — POST /webhook/calculator-lead, responseMode=responseNode
2. `Check Required Fields` — Code: validate name + phone required
3. `Is Valid?` — IF: isValid === true
4. `Respond 400 Error` — respondToWebhook 400 (invalid branch)
5. `Create JT Account` — HTTP POST PAVE: createAccount (customer, orgId=22Nm3uFevXMb)
6. `Set Account Custom Fields` — HTTP POST PAVE: updateAccount (Lead Source=Website, Type=Bathroom Remodel)
7. `Create JT Contact` — HTTP POST PAVE: createContact
8. `Set Contact Custom Fields` — HTTP POST PAVE: updateContact (email + phone via custom field IDs)
9. `Create JT Location` — HTTP POST PAVE: createLocation (Bozeman, MT default)
10. `Create JT Job` — HTTP POST PAVE: createJob (name = "{contact.name} - Bathroom")
11. `Set Job Custom Fields` — HTTP POST PAVE: updateJob (Job Type=Bathroom, Phase=1. Contacted)
12. `Prepare Data` — Code: build Postgres + Slack payloads
13. `Insert into Postgres` — Postgres INSERT into `hwc.calculator_leads`
14. `Send Slack Notification` — Slack post to #leads with lead details
15. `Merge Results` — Merge: combine Postgres + Slack outputs
16. `Respond 200 Success` — respondToWebhook with jt_account_id + jt_job_id

**Differences from original spec:**
- Spec had 9 planned nodes; actual has 16 (more granular)
- Added: `Set Contact Custom Fields` node (sets email/phone as custom fields, not just contact name)
- Added: `Respond 400 Error` for validation failures
- Added: `Merge Results` node to wait for parallel Postgres + Slack
- Custom field IDs are hardcoded: Account Lead Source=`22PUGvBnXeYs`, Job Type=`22P4fgU4XmLY`, Phase=`22P4fguBu3Ub`

-----

### Workflow #10 — Lead Response

|Field            |Value                                                                              |
|-----------------|-----------------------------------------------------------------------------------|
|**n8n ID**       |`lead-response-automation`                                                         |
|**Status**       |BUILT — Active (most reliable workflow, 0% error rate)                             |
|**Trigger**      |POST webhook                                                                       |
|**Webhook URL**  |`/webhook/new-lead`                                                                |
|**Purpose**      |Process new JT leads: log payload, extract fields with Claude, route to Slack + SMS|
|**Nodes**        |29                                                                                 |
|**Systems**      |JT webhook → Postgres (log) → Claude API → Slack + Twilio SMS                     |
|**Executions**   |Many — 5 recent all successful                                                     |
|**Last run**     |2026-03-25 (today, running actively)                                               |
|**MCP migration**|Stays as standalone webhook-triggered workflow                                     |

**Key differences from registry spec:**
- Registry described this as "JT webhook or Cron polling" — actual is POST webhook at `/webhook/new-lead`
- Much more complex than planned (29 nodes vs conceptual few)
- Includes Claude API integration for lead analysis
- Logs raw payloads to `webhook_payloads` table
- Has companion `work_sms_handler` workflow for Twilio SMS processing

-----

### Workflow: SMS Handler (companion to #10)

|Field            |Value                                                 |
|-----------------|------------------------------------------------------|
|**n8n ID**       |`incoming-sms-handler`                                |
|**Status**       |BUILT — Active                                        |
|**Trigger**      |POST webhook                                          |
|**Nodes**        |14                                                    |
|**Purpose**      |Handle incoming Twilio SMS responses from leads       |
|**Tags**         |sms, twilio                                           |

-----

### Workflow #11 — Follow-Up Reminders

|Field            |Value                                                            |
|-----------------|-----------------------------------------------------------------|
|**n8n ID**       |Not yet created                                                  |
|**Status**       |PLANNED                                                          |
|**Trigger**      |Cron: `0 8 * * 1-5` (weekdays, 8am MT)                           |
|**Purpose**      |Check for stale leads (no activity in 7+ days), send Slack digest|
|**Systems**      |JT (read accounts by custom field) → Slack                       |
|**Spec**         |jobtread_api_reference.md Recipe 5                               |
|**MCP migration**|Tier 2 tool: `hwc_run_follow_up_check`                           |

-----

### Workflow #12 — Daily Voice Log Processor

|Field            |Value                                                                               |
|-----------------|-------------------------------------------------------------------------------------|
|**n8n ID**       |`XAm7ehKjJers5NqC`                                                                  |
|**Status**       |BUILT — Active                                                                       |
|**Trigger**      |POST webhook                                                                         |
|**Webhook URL**  |`/webhook/daily-log`                                                                 |
|**Purpose**      |Receive voice transcript, Claude extracts structured data, push to JT + Postgres     |
|**Input**        |`{ transcript, date, source }`                                                       |
|**Systems**      |iOS → Claude API → JT (createTimeEntry × N + createDailyLog) + Postgres + Slack      |
|**Nodes**        |18                                                                                   |
|**Executions**   |1 total, 0 success, 1 error                                                         |
|**Last run**     |2026-03-24                                                                           |
|**Spec**         |VOICE_NOTE_PIPELINE_SPEC.md                                                          |
|**MCP migration**|Tier 2 tool: `hwc_process_voice_note`                                                |

**Actual nodes (18):**

1. `Webhook: Daily Log` — POST /webhook/daily-log, responseMode=responseNode
2. `Validate Transcript` — Code: check transcript exists and is non-empty
3. `Is Valid?` — IF: isValid === true
4. `Respond 400 Error` — respondToWebhook 400 (invalid branch)
5. `Fetch Active Jobs` — HTTP POST to PAVE: get active jobs list
6. `Call Claude API` — HTTP POST to Anthropic API with transcript + active jobs
7. `Parse Claude Response` — Code: extract structured data from Claude
8. `Confidence Check` — IF/Switch: route by confidence level
9. `Loop Time Entries` — SplitInBatches: iterate over time_entries array
10. `Create Time Entry` — HTTP POST to PAVE: createTimeEntry
11. `Create Daily Log` — HTTP POST to PAVE: createDailyLog
12. `Archive to Postgres` — Postgres INSERT into daily_logs
13. `Slack: Success` — Slack notification with job/hours/trades
14. `Slack: Low Confidence` — Slack notification for human review
15. `Respond Success` — respondToWebhook with result
16-18. Supporting code/merge nodes

-----

### Workflow #13 — Paperless Document Processor

|Field            |Value                                                                    |
|-----------------|-------------------------------------------------------------------------|
|**n8n ID**       |Not yet created                                                          |
|**Status**       |PLANNED (3 phases)                                                       |
|**Trigger**      |POST webhook (from Paperless post-consumption script)                    |
|**Webhook URL**  |`/webhook/paperless-consumed`                                            |
|**Purpose**      |Process Paperless documents — match receipts to JT jobs, create bills    |
|**Spec**         |paperless_integration_spec.md                                            |
|**MCP migration**|Tier 2 tools: `hwc_process_receipt`, `hwc_create_vendor_bill`            |

**Phase 1 nodes (BUILD NOW):**
1. Webhook trigger
2. Validate document_id
3. Fetch document from Paperless API
4. Slack notification

**Phase 2 (BUILD NEXT):** Claude job matching + JT vendor bill creation
**Phase 3 (FUTURE):** Firefly III transaction sync

-----

### Marketing: Web Scraper

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`k2TN787tyntCyY1P`             |
|**Status**|BUILT — Active                  |
|**Nodes** |29                              |

-----

### Marketing: Content Calendar

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`weekly-content-calendar`       |
|**Status**|BUILT — Active                  |
|**Nodes** |23                              |
|**Tags**  |calendar, content, scheduled    |

-----

### Marketing: Intel Ingest

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`intelligence-pipeline-hwc`     |
|**Status**|BUILT — **Inactive**            |
|**Nodes** |20                              |
|**Tags**  |intelligence, scraper           |

-----

### Marketing: Content Generator

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`content-generator-hwc`         |
|**Status**|BUILT — **Inactive**            |
|**Nodes** |13                              |
|**Tags**  |content, marketing              |

-----

### Infrastructure: Cross-Service Health Monitor

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`KaGqsviVtFGp5d7l`             |
|**Status**|BUILT — Active                  |
|**Nodes** |16                              |
|**Tags**  |automation, health, monitoring  |

-----

### Infrastructure: Alertmanager Router

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`YgoqxXkDtRkDrbpK`             |
|**Status**|BUILT — Active                  |
|**Nodes** |14                              |
|**Tags**  |alertmanager, automation, monitoring|

-----

### Infrastructure: Script Executor

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`zESbVHcPO88NL2Je`             |
|**Status**|BUILT — Active                  |
|**Nodes** |19                              |
|**Tags**  |scripts, automation, security   |

-----

### Infrastructure: Slack Utilities

|Workflow             |n8n ID              |Active|Nodes|Purpose                     |
|---------------------|---------------------|------|-----|----------------------------|
|Slack Notify         |`oPkQAoxLPnmpszRD`  |Yes   |3    |Sub-workflow for Slack posts|
|Slack Approval       |`8Gdamdg8MYFjhKIR`  |Yes   |6    |Handle Slack button actions |
|Webhook→Slack        |`9qg7apJdVjzQGwkw`  |Yes   |2    |Simple webhook→Slack relay  |

-----

### Home: Frigate → Slack

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`mNJKL8puSZpWhsR2`             |
|**Status**|BUILT — Active                  |
|**Nodes** |7                               |
|**Tags**  |automation, frigate, surveillance|

-----

### Home: Events Digest

|Field     |Value                           |
|----------|--------------------------------|
|**n8n ID**|`DxDOkTqP6UzJgxfG`             |
|**Status**|BUILT — Active                  |
|**Nodes** |10                              |

-----

### Home: Media Pipeline

|Field       |Value                           |
|------------|--------------------------------|
|**n8n ID**  |`n14heZ9wzJ8Uyemo`             |
|**Status**  |BUILT — Active                  |
|**Nodes**   |22                              |
|**Created** |2026-03-25 (brand new)          |

-----

## Shared Patterns Across Workflows

### Authentication

- All webhooks use `x-api-key` header for authentication
- JT PAVE calls use `grantKey` in request body (from n8n env variable `JT_GRANT_KEY`)
- Claude API calls use Anthropic API key (from n8n env variable)
- Paperless API uses token auth (from n8n env variable)
- Firefly API uses Bearer token (from n8n env variable)

### Error Handling

- PAVE returns HTTP 200 even on errors — always check `response.errors` array
- Add error check node after every JT write operation
- On failure: log to Postgres `workflow_log` + Slack error notification
- Never silently fail — every workflow must notify on error

### Slack Notification Format

- Use Block Kit for structured messages
- Include JT deep links: `https://app.jobtread.com/jobs/{jobId}`
- Use emoji for quick scanning: 🏠 (lead), 📋 (estimate), 🧾 (receipt), ⏱ (time entry), 📄 (document), ⚠️ (error)
- Business notifications go to #leads channel

### Postgres Logging

- Every workflow that writes to JT also writes to `workflow_log`
- Fields: workflow_name, trigger_source, project_id, action, target_system, request_payload, response_payload, success, error_message, duration_ms

### Duplicate Prevention

- Budget push (#08b): **NEEDS duplicate pre-check** — no such node exists yet. No bulk-delete in JT.
- Customer creation (#09): should search JT by name before creating — not currently implemented
- Time entries (#12): check Postgres daily_logs by job_id + date before pushing
- Vendor bills (#13): check Paperless n8n_status custom field — don't process twice

-----

## MCP Migration Path

As the Heartwood MCP Server (System 7) comes online, workflows migrate in stages:

**Stage 1:** New workflows (#12, #13) use MCP Tier 1 tools for JT calls instead of raw PAVE.

**Stage 2:** Existing workflows (#08a, #08b) swap HTTP Request nodes for MCP tool calls. Same logic, cleaner JT integration.

**Stage 3:** Compound operations (#09 createFullCustomer, #13 createVendorBill) become Tier 2 MCP tools backed by these workflows. Claude and other consumers call the MCP tool, which triggers the n8n workflow.

**Stage 4:** Some simple read-only workflows (#08a) may be replaced entirely by Tier 1 MCP tools (the app calls the MCP server directly instead of going through n8n).

-----

## Workflow Numbering Convention

|Range|Category               |Examples                                             |
|-----|-----------------------|-----------------------------------------------------|
|00–07|Infrastructure / shared|Health monitor, alertmanager, script executor, Slack utilities|
|08–09|Estimating + leads     |JT data provider, estimate router, calculator lead   |
|10–11|Lead management        |Lead response, SMS handler, follow-up reminders      |
|12   |Job costing            |Voice log processor                                  |
|13   |Document processing    |Paperless pipeline                                   |
|14–19|Reserved for future    |Client journey automation, JT native workflow bridges|
|20+  |Personal / non-business|Frigate, events digest, media pipeline, content/marketing|

-----

## Priority Action Items

1. **Fix #08b duplicate prevention** — Add Postgres pre-check node before budget push. Without this, accidental re-pushes create duplicate line items with no way to bulk-delete in JT.
2. **Investigate #08a 100% error rate** — All 4 executions failed. Check if the webhook is being called correctly by the estimator app.
3. **Investigate #09 90% error rate** — 9 of 10 executions failed. May be PAVE errors or validation issues during development.
4. **Fix #12 error** — Only 1 execution and it failed. Check Claude API call and PAVE integration.
5. **Add #09 duplicate prevention** — Search JT by name before creating new accounts.

-----

*This registry is the single source of truth for all n8n workflows. Update it whenever a workflow is created, modified, or retired. Claude Code sessions should read this file before building or modifying any workflow to understand what already exists.*
