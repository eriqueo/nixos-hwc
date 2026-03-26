# Paperless-ngx Integration Spec

## Document Management, Receipt Processing, and System Plumbing

**Status:** Phase 1 = BUILD NOW · Phase 2 = BUILD NEXT · Phase 3 = FUTURE
**Last updated:** March 25, 2026

-----

## 1. Architecture: How the Systems Connect

The homeserver runs a shadow system that mirrors and extends JT. During the parallel period, both systems are authoritative for their strengths. n8n is the glue. Claude is the intelligence layer that makes routing decisions humans would otherwise have to make manually.

### System Roles

|System       |Role                        |Manages                                                        |Status                  |
|-------------|----------------------------|---------------------------------------------------------------|------------------------|
|JobTread     |Operational system of record|Customers, jobs, budgets, invoicing, portal                    |LIVE — primary          |
|Paperless-ngx|Document archive + OCR      |All documents: receipts, invoices, contracts, permits, personal|LIVE — fresh install    |
|Firefly III  |Accounting (parallel to QB) |Transactions, budgets, categories, reports                     |LIVE — unused           |
|n8n          |Automation / integration hub|Webhooks, API calls, routing, fan-out                          |LIVE — workflows running|
|Postgres     |Shared analytical layer     |Catalog, estimates, daily logs, receipts, workflow log         |LIVE                    |
|Claude (API) |Intelligence layer          |Job matching, expense categorization, data extraction          |Available               |

### Data Flow: Receipt Pipeline (Full Vision)

```
Receipt photo/email/scan
  → Paperless-ngx (OCR + archive + auto-tag + search)
    → Post-consumption script → n8n webhook
      → n8n fetches document from Paperless API
        → Claude: match job + categorize expense
          → JT: create vendor bill on matched job
          → Firefly III: create expense transaction
          → Paperless: update custom fields (job, status)
          → Postgres: archive to workflow_log
          → Slack: confirmation notification
```

One receipt input, five systems updated, zero manual data entry for high-confidence matches. Low-confidence matches go to Slack for one-tap confirmation.

-----

## 2. Build Now: Paperless Setup + n8n Glue

**Goal:** Get Paperless-ngx structured for Heartwood business documents and personal documents. Wire post-consumption hook to n8n so every ingested document triggers a notification. No AI, no JT push yet — just the foundation.

### 2.1 Paperless Tags (Hierarchical)

Set these up in the Paperless admin UI. Use nested tags for organization.

|Parent Tag|Child Tags                                                                           |Matching Rule                                      |
|----------|-------------------------------------------------------------------------------------|---------------------------------------------------|
|Business  |Receipt, Invoice, Contract, Permit, Warranty, Insurance, Estimate                    |Auto: tag based on document type assignment        |
|Personal  |Tax, Medical, Home, Vehicle, Financial                                               |Auto: anything not tagged Business                 |
|Job       |One child per active job (e.g., Margulies #280)                                      |Set by n8n after Claude matching (Phase 2)         |
|Trade     |Demo, Framing, Plumbing, Electrical, Tile, Drywall, Painting, Finish Carpentry, Admin|Set by n8n after Claude matching (Phase 2)         |
|Status    |Inbox, Matched, Review Needed, Pushed to JT, Pushed to Firefly                       |Inbox = default on all new docs. Others set by n8n.|
|Vendor    |(Managed via Correspondents, not tags)                                               |Paperless auto-learns correspondents from OCR text |

### 2.2 Paperless Document Types

Create these in admin. Paperless uses document types to classify what a document is.

|Document Type |Auto-Match Pattern                          |Notes                               |
|--------------|--------------------------------------------|------------------------------------|
|Receipt       |Any: total, subtotal, amount due, change    |Most common business doc            |
|Vendor Invoice|Any: invoice, bill, statement, net terms    |Sub invoices, supplier bills        |
|Purchase Order|Exact: purchase order                       |Your POs to suppliers               |
|Contract      |Any: agreement, contract, terms, signature  |Client contracts, sub agreements    |
|Permit        |Any: permit, building department, inspection|Building permits, inspection reports|
|Warranty      |Any: warranty, guarantee                    |Product + workmanship warranties    |
|Insurance     |Any: certificate of insurance, COI, policy  |GL, workers comp, sub COIs          |
|Tax Document  |Any: 1099, W-9, W-2, tax return             |Personal + business tax docs        |

### 2.3 Paperless Correspondents (Vendors)

Seed these in admin. Paperless will auto-match future documents. Add more as they appear.

|Correspondent       |Match Algorithm|Match Text          |
|--------------------|---------------|--------------------|
|Kenyon Noble        |Any            |kenyon noble, kenyon|
|Montana Tile & Stone|Any            |montana tile        |
|Ferguson            |Any            |ferguson            |
|Home Depot          |Any            |home depot          |
|Lowe's              |Any            |lowes, lowe's       |
|Yellowstone Lumber  |Any            |yellowstone lumber  |

### 2.4 Paperless Custom Fields

Custom fields allow n8n to write structured data back to Paperless after processing.

|Field Name |Type    |Purpose                                                                      |
|-----------|--------|-----------------------------------------------------------------------------|
|jt_job_id  |Text    |JT job ID once matched by Claude. Empty until Phase 2.                       |
|jt_job_name|Text    |Human-readable job name (e.g., "Margulies Kids Bathroom #280")               |
|amount     |Monetary|Total receipt/invoice amount. Extracted by Claude in Phase 2.                |
|cost_code  |Text    |JT cost code name (e.g., "1800 Tiling"). Set by Claude in Phase 2.           |
|n8n_status |Text    |Processing status: pending, matched, review_needed, pushed_jt, pushed_firefly|
|firefly_id |Text    |Firefly III transaction ID once synced. Empty until Phase 3.                 |

### 2.5 NixOS Post-Consumption Script

Add this to your Paperless NixOS config. The script fires after every document is consumed and POSTs the document ID to n8n.

**File:** `domains/business/paperless/parts/post-consume.sh`

```bash
#!/usr/bin/env bash
# Paperless-ngx post-consumption hook
# Fires after OCR + indexing complete
# Posts document metadata to n8n for processing

WEBHOOK_URL="https://hwc.ocelot-wahoo.ts.net/webhook/paperless-consumed"
API_KEY="${PAPERLESS_N8N_API_KEY}"

curl -s -X POST "${WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d "{
    \"document_id\": \"${DOCUMENT_ID}\",
    \"correspondent\": \"${DOCUMENT_CORRESPONDENT}\",
    \"tags\": \"${DOCUMENT_TAGS}\",
    \"document_type\": \"${DOCUMENT_TYPE}\",
    \"filename\": \"${DOCUMENT_FILE_NAME}\",
    \"source\": \"paperless\",
    \"created\": \"${DOCUMENT_CREATED}\"
  }"
```

**NixOS config addition** (in container environment):

```nix
PAPERLESS_POST_CONSUME_SCRIPT = "/app/scripts/post-consume.sh";
```

Mount the script into the Podman container via a bind mount in your `config.nix`. The script must be executable inside the container.

### 2.6 n8n Workflow #13: Paperless Document Processor

**Phase 1 scope:** Receive webhook, fetch document details from Paperless API, send Slack notification. That's it. No Claude, no JT, no Firefly.

**Trigger:** POST webhook at `/webhook/paperless-consumed`

**Node 1 — Validate:** Check document_id exists and is non-empty.

**Node 2 — Fetch from Paperless API:** GET `http://localhost:8102/api/documents/{document_id}/` with auth token. Returns full metadata including OCR content, tags, correspondent, document type, custom fields.

**Node 3 — Slack Notification:**

```
📄 *New Document Ingested*

*Type:* {{ document_type }}
*Correspondent:* {{ correspondent }}
*Tags:* {{ tags }}
*Filename:* {{ filename }}
*Created:* {{ created }}

_Processed by Paperless-ngx_
```

This gives you immediate visibility into what Paperless is processing. Every document you drop in the consume folder, email, or scan gets a Slack ping.

-----

## 3. Build Next: Claude Job Matching + JT Vendor Bills

**Goal:** When a receipt is consumed, Claude examines the OCR text, matches it to an active JT job, categorizes the expense, and creates a vendor bill in JT. This is the "job cost inbox" concept.

**Prerequisite:** Phase 1 (Section 2) working — Paperless consuming documents and n8n receiving webhooks.

### 3.1 New Nodes Added to Workflow #13

These insert between the Paperless API fetch (Node 2) and the Slack notification (Node 3).

**Node 2a — Is this a receipt/invoice?**
If document_type is "Receipt" or "Vendor Invoice", continue to Claude matching. Otherwise skip to Slack notification (just archive notification, no job matching needed for contracts/permits/etc).

**Node 2b — Fetch active JT jobs**
GET active jobs from JT via MCP server or PAVE API (same pattern as workflow 08a). Returns job ID, name, number, customer, phase. Inject into Claude prompt.

**Node 2c — Claude job matching**
POST to Anthropic API with OCR text + active jobs list. Claude returns structured JSON:

```json
{
  "job_match": {
    "job_id": "JT_JOB_ID",
    "job_name": "Margulies Kids Bathroom (#280)",
    "confidence": "high | medium | low | none"
  },
  "expense_category": "Tiling",
  "cost_code_id": "22Nm3uGRAMma",
  "cost_type_id": "22Nm3uGRAMmr",
  "amount": 42.99,
  "is_personal": false,
  "reasoning": "Schluter thinset = tile. Only active bath job."
}
```

**Node 2d — Confidence router**

|Confidence|Personal?|Action                                                                             |
|----------|---------|-----------------------------------------------------------------------------------|
|High      |No       |Auto: create JT vendor bill + update Paperless custom fields + Slack confirm       |
|Medium    |No       |Slack with suggested match + confirm/reject buttons. Eric's tap triggers push.     |
|Low / None|No       |Slack flag: "Unmatched receipt from [vendor], $[amount]." Stays in Paperless Inbox.|
|Any       |Yes      |Tag as Personal. No JT push. Optionally route to Firefly (Phase 3).                |

### 3.2 JT Vendor Bill Creation (The Key Integration)

When Claude matches a receipt to a job with high confidence, n8n creates a vendor bill in JT. This is the native JT mechanism for recording expenses against a job's budget.

**JT PAVE API call:** `createDocument` (via MCP tool `jt_create_document`)

|Parameter        |Value                                                                            |
|-----------------|---------------------------------------------------------------------------------|
|jobId            |From Claude's job_match.job_id                                                   |
|type             |"vendorBill"                                                                     |
|accountId        |Vendor account in JT (Kenyon Noble, etc). Create if doesn't exist.               |
|externalId       |Receipt number or Paperless document ID (cross-reference)                        |
|date             |Receipt date from OCR / Paperless                                                |
|name             |"Receipt | {Vendor} | {Date}" (pipe-delimited, consistent with naming convention)|
|costCodeIds      |Filter to Claude's matched cost code (e.g., ["22Nm3uGRAMma"] for Tiling)         |
|costItemOverrides|Set unitCost to actual receipt amount (may differ from budgeted cost)            |

**After vendor bill created:**

1. **Create payment:** `createPayment` against the vendor bill document, amount = receipt total, date = receipt date. Marks the bill as paid.
1. **Attach receipt image:** Upload the Paperless archived PDF to JT via `uploadFile`, then attach to the vendor bill document.
1. **Update Paperless:** PATCH document custom fields (jt_job_id, jt_job_name, amount, cost_code, n8n_status = "pushed_jt"). Remove Inbox tag, add Matched + Pushed to JT tags.

### 3.3 Claude Extraction Prompt

Same design pattern as the voice note pipeline. Key elements:

- Active jobs list injected dynamically from JT (fetched each time)
- 9 trade categories mapped to JT cost code IDs (same mapping as voice pipeline)
- Common Bozeman vendor list with typical purchase categories
- If only 1 active job, confidence = high unless items clearly don't match
- Personal purchases (groceries, gas, non-construction) = is_personal: true
- Multi-job ambiguity = low confidence → Slack for human decision

*See VOICE_NOTE_PIPELINE_SPEC.md for the full prompt pattern. The receipt prompt follows the same structure with vendor/amount fields instead of hours/trade fields.*

-----

## 4. Future: Firefly III Sync + Full Parallel System

**Goal:** Every receipt that flows through the pipeline also creates a transaction in Firefly III, building a parallel accounting system alongside QB. Personal expenses go to Firefly without touching JT.

### 4.1 Firefly III Integration

New node added to workflow #13 after the JT push (or in parallel):

**Business receipt (matched to job):** Create Firefly transaction with category = trade, budget = job name, source = business checking, destination = vendor. Tags: business, job name, trade.

**Personal receipt:** Create Firefly transaction with category from Claude (groceries, fuel, medical, etc.), source = personal checking, destination = vendor. Tags: personal, category.

Firefly transaction ID written back to Paperless custom field (firefly_id).

### 4.2 Plaid / Bank Sync

JT has Plaid integration for bank transaction reconciliation. Firefly III also supports bank imports. The eventual flow:

- Bank transactions sync to both JT (via Plaid) and Firefly (via import/API)
- Receipt images in Paperless match to bank transactions by amount + date + vendor
- Three-way reconciliation: receipt image (Paperless) ↔ expense entry (JT vendor bill) ↔ bank transaction (Firefly/Plaid)

### 4.3 QB Transition

Once Firefly III has 3–6 months of validated data running in parallel with QB, you can evaluate whether to drop QB entirely. The decision criteria:

- Firefly P&L matches QB P&L within 5%
- All tax-relevant transactions captured in Firefly
- CPA is comfortable with Firefly exports for tax prep
- JT + Firefly together give you everything QB did

-----

## 5. Migration: Existing Receipt OCR Pipeline

Your current receipt OCR pipeline (port 8001, Tesseract + Ollama, Postgres tables) is superseded by Paperless-ngx. Here's the migration path:

|Current Component           |Replaced By                              |Action                                                      |
|----------------------------|-----------------------------------------|------------------------------------------------------------|
|OCR service (port 8001)     |Paperless-ngx OCR (Tesseract)            |Decommission after Paperless is handling all docs           |
|Ollama vendor normalization |Paperless correspondent matching + Claude|Paperless auto-learns vendors; Claude handles categorization|
|PG: vendors table           |Paperless correspondents                 |Correspondents are the source of truth for vendor names     |
|PG: receipts + receipt_items|Paperless documents + custom fields      |Keep PG tables for analytics; Paperless is document store   |
|PG: receipt_review_queue    |Paperless Inbox tag + Slack              |Review queue is now the Inbox tag in Paperless              |
|n8n receipt-intake.json     |Workflow #13 (this spec)                 |New workflow replaces the old one entirely                  |

**Don't delete the Postgres receipt tables yet.** They may be useful for historical data and the job costing comparison spreadsheet. But stop writing new data to them once Paperless is handling intake.

-----

## 6. Implementation Order

### Phase 1: Paperless + n8n glue (this week)

1. Create tags, document types, correspondents, and custom fields in Paperless admin UI
1. Write post-consumption script and mount into Podman container
1. Create n8n workflow #13 (webhook → fetch → Slack)
1. Test: drop a receipt into consume folder, verify Slack notification
1. Test: email a receipt to Paperless, verify Slack notification

### Phase 2: Claude job matching + JT push (when Phase 1 proven)

1. Add Claude extraction node to workflow #13
1. Add JT active jobs fetch node
1. Add confidence router + vendor bill creation nodes
1. Add Slack interactive buttons for medium-confidence confirms
1. Test with known receipts: Kenyon Noble (should match), grocery store (should flag personal)
1. Run for 2 weeks, review accuracy, tune Claude prompt

### Phase 3: Firefly III sync (when Phase 2 stable)

1. Set up Firefly III categories, budgets, accounts
1. Add Firefly transaction creation node to workflow #13
1. Route personal expenses to Firefly (skip JT)
1. Run parallel with QB for 3–6 months, compare monthly

### Phase 4: Decommission old pipeline

1. Stop OCR service (port 8001)
1. Archive old receipt-intake.json workflow
1. Evaluate QB → Firefly transition

-----

*This spec is a companion to VOICE_NOTE_PIPELINE_SPEC.md, HEARTWOOD_OPERATING_SYSTEM.md, HEARTWOOD_MCP_SERVER_SPEC.md, and the marketing/financial operations docs.*
