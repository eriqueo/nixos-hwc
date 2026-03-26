# JobTread API Reference
## Heartwood Craft — n8n Workflow Integration Guide

**63 MCP tools + 57 n8n operations via the PAVE API · `POST https://api.jobtread.com/pave`**
Bozeman, MT · Single-member LLC · Last updated: 2026-03-25

---

## Table of Contents

1. [Quick Reference: Your Heartwood IDs](#section-1--quick-reference-your-heartwood-ids)
2. [PAVE API Fundamentals for n8n](#section-2--pave-api-fundamentals-for-n8n)
3. [All 57 Operations](#section-3--all-57-operations)
4. [Complete n8n Workflow Recipes](#section-4--complete-n8n-workflow-recipes)
5. [Critical Gotchas & Known Issues](#section-5--critical-gotchas--known-issues)
6. [n8n Node Patterns & Expressions](#section-6--n8n-node-patterns--expressions)
7. [JobTread Native Workflows](#section-7--jobtread-native-workflows)
8. [Heartwood MCP Server Integration](#section-8--heartwood-mcp-server-integration)

---

# Section 1 — Quick Reference: Your Heartwood IDs

## Core IDs

| Key | Value | Notes |
|---|---|---|
| Organization ID | `22Nm3uFevXMb` | Required in every createAccount, createJob |
| Eric's User ID | `22Nm3uFeRB7s` | eric@iheartwoodcraft.com — Admin |

---

## Cost Codes

| ID | Code | Name |
|---|---|---|
| `22Nm3uGRAMmG` | 0000 | Uncategorized |
| `22Nm3uGRAMmH` | 0100 | Planning |
| `22NxeGLaJCQT` | 0110 | Site Preparation |
| `22Nm3uGRAMmJ` | 0200 | Demolition |
| `22Nm3uGRAMmL` | 0400 | Utilities |
| `22Nm3uGRAMmM` | 0500 | Foundation |
| `22Nm3uGRAMmN` | 0600 | Framing |
| `22Nm3uGRAMmQ` | 0800 | Siding |
| `22Nm3uGRAMmS` | 1000 | Electrical |
| `22Nm3uGRAMmT` | 1100 | Plumbing |
| `22Nm3uGRAMmV` | 1300 | Insulation |
| `22Nm3uGRAMmW` | 1400 | Drywall |
| `22Nm3uGRAMmX` | 1500 | Doors & Windows |
| `22Nm3uGRAMmZ` | 1700 | Flooring |
| `22Nm3uGRAMma` | 1800 | Tiling |
| `22Nm3uGRAMmb` | 1900 | Cabinetry |
| `22Nm3uGRAMmc` | 2000 | Countertops |
| `22Nm3uGRAMmd` | 2100 | Trimwork |
| `22Nm3uGRAMme` | 2200 | Specialty Finishes |
| `22Nm3uGRAMmf` | 2300 | Painting |
| `22Nm3uGRAMmg` | 2400 | Appliances |
| `22Nm3uGRAMmh` | 2500 | Decking |
| `22Nm3uGRAMmi` | 2600 | Fencing |
| `22Nm3uGRAMmk` | 2800 | Concrete |
| `22Nm3uGRAMmn` | 3000 | Furnishings |
| `22Nm3uGRAMmp` | 3100 | Miscellaneous |

---

## Cost Types

| ID | Name | Default Markup |
|---|---|---|
| `22PJuNqewZmV` | Admin | 0.50 (50%) |
| `22Nm3uGRAMmq` | Labor | 0.50 (50%) |
| `22Nm3uGRAMmr` | Materials | 0.50 (50%) |
| `22Nm3uGRAMmt` | Other | 0.50 (50%) |
| `22PQ4KZExZjP` | Selections | 0.30 (30%) |
| `22Nm3uGRAMms` | Subcontractor | 0.30 (30%) |

---

## Units

| ID | Unit Name | Typical Use |
|---|---|---|
| `22Nm3uGRAMm5` | Cubic Yards | Concrete, fill |
| `22Nm3uGRAMm6` | Days | Day-rate labor |
| `22Nm3uGRAMm7` | Each | Fixtures, materials by unit |
| `22Nm3uGRAMm8` | Gallons | Paint, sealers |
| `22Nm3uGRAMm9` | Hours | All labor line items |
| `22Nm3uGRAMmA` | Linear Feet | Trim, baseboard |
| `22Nm3uGRAMmB` | Lump Sum | Allowances, misc |
| `22Nm3uGRAMmC` | Pounds | Misc materials |
| `22Nm3uGRAMmD` | Square Feet | Tile, flooring, paint areas |
| `22Nm3uGRAMmE` | Squares | Roofing |
| `22Nm3uGRAMmF` | Tons | Gravel, aggregate |

---

## Custom Fields — Customer Account

| ID | Field Name | Type | Options / Notes |
|---|---|---|---|
| `22Nnj9KMKEPC` | Project Type | option | Bathroom Remodel, Full Remodel, Kitchen Remodel, Addition, Exterior, Interior, Custom |
| `22Nnj9KTwMCe` | Notes | text | Free text |
| `22Nnj9KfuSgp` | Referred By | text | Free text |
| `22Nnj9Kk4CLH` | Lead Lost Reason | option | Price, Competition, Timing, Not a good fit, Customer changed mind, Unknown |
| `22Nnj9KwwePZ` | Status | option | New Lead, Appointment Set, Lead Lost, Active Customer |
| `22NnjWw3NTGc` | Appointment | date | YYYY-MM-DD |
| `22NnjXKR5868` | Days Choice | option | Monday–Friday |
| `22NnjXZhpFXn` | Time Choice | option | 8am-10am, 10am-12pm, 12pm-2pm, 2pm-4pm, 4pm-530pm |
| `22PU427xzLaS` | Source | option | Local Service, Google, Referral, Short Term Rental, Chamber, Facebook, Repeat, Other |
| `22PUGvBnXeYs` | Lead Source | option | **REQUIRED FIELD.** Must be set via `updateAccount` after `createAccount`. |

---

## Custom Fields — Customer Contact

| ID | Field Name | Type |
|---|---|---|
| `22Nm3uGRBrPX` | Email | emailAddress |
| `22Nm3uGb7WT2` | Phone | phoneNumber |
| `22NnjDZ39w8C` | Mobile | phoneNumber |
| `22NnjDZS2Sy8` | Secondary Email | emailAddress |

---

## Custom Fields — Job

| ID | Field Name | Type | Options |
|---|---|---|---|
| `22P4fgU4XmLY` | Job Type | option | Bathroom, Kitchen, Basement, Deck, Interior General, Exterior General |
| `22P4fguBu3Ub` | Phase | option | 1. Contacted → 2. Visited → 3. Budgeting → 4. Budget Sent → 5. Budget Approved → 6. Work Start → 7. First Milestone → 8. Second Milestone → 9. Final Milestone |

---

# Section 2 — PAVE API Fundamentals for n8n

## What is PAVE?

PAVE is JobTread's proprietary query API. Every operation — read or write — is a single `POST` to `https://api.jobtread.com/pave`. The request body is a JSON object with a `query` key. You select which fields to return by including them in the query. There are no separate GET/PUT/DELETE endpoints — everything is a POST.

---

## n8n HTTP Request Node — Baseline Setup

| n8n Field | Value |
|---|---|
| Method | POST |
| URL | `https://api.jobtread.com/pave` |
| Authentication | None (auth is in the body via grantKey) |
| Content-Type header | `application/json` |
| Body Content Type | JSON / Raw |
| Response Format | JSON |

---

## Request Envelope

Every PAVE call follows this structure:

```json
{
  "query": {
    "$": {
      "grantKey": "{{ $env.JT_GRANT_KEY }}",
      "notify": false,
      "viaUserId": "22Nm3uFeRB7s"
    },
    "OPERATION_NAME": {
      "$": { /* inputs */ },
      "fieldToReturn1": {},
      "fieldToReturn2": { "nestedField": {} }
    }
  }
}
```

| Key | Required | Notes |
|---|---|---|
| `grantKey` | Yes | Store in n8n Credentials or env variable. Never hardcode. |
| `notify` | No | Set `false` in automated workflows to suppress JT notifications |
| `viaUserId` | No | Scopes the action as a specific user. Use Eric's ID for all Heartwood automations. |

---

## Reading the Response in n8n

PAVE returns the operation name as the top-level key in the response:

```js
// After createAccount:
{{ $json.createAccount.createdAccount.id }}

// After createJob:
{{ $json.createJob.createdJob.id }}

// After querying accounts (array):
{{ $json.organization.accounts.nodes[0].id }}

// Referencing a previous node by name:
{{ $node["Create Account"].json.createAccount.createdAccount.id }}
```

> **Always include `"id": {}` in every write operation's return block.** You will almost always need the returned ID in the next workflow step.

---

## Grant Key Management

- Create keys at `https://app.jobtread.com/grants`
- Each key is shown **only once** at creation — copy it immediately
- Keys expire after **3 months of inactivity** — set a calendar reminder to rotate
- Store in n8n as a Credential (Header Auth) or environment variable, never hardcoded in workflow JSON

---

# Section 3 — All 57 Operations

**Legend:** **R** = Required · O = Optional · Types: `s`=string, `n`=number, `b`=boolean, `a`=array, `o`=object

---

## 1. Accounts (Customers & Vendors)

### createAccount

> ⚠️ **GOTCHA:** `createAccount` does NOT accept `customFieldValues`. If your org has required custom fields (e.g. Lead Source), you must call `updateAccount` immediately after. See Section 5 for the full pattern.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `name` | **R** | s | Account / company name |
| `type` | **R** | s | `customer` or `vendor` |
| `organizationId` | **R** | s | Always `22Nm3uFevXMb` for Heartwood |

Returns: `createdAccount.id`, `createdAccount.name`

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "createAccount": {
      "$": {
        "name": "{{ $json.contact.name }}",
        "type": "customer",
        "organizationId": "22Nm3uFevXMb"
      },
      "createdAccount": { "id": {}, "name": {}, "type": {} }
    }
  }
}
```

---

### updateAccount

Use immediately after `createAccount` to set custom fields. Also used to update any account field over time.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `id` | **R** | s | Account ID to update |
| `name` | O | s | Rename the account |
| `customFieldValues` | O | o | `{ "fieldId": "value" }` — use IDs from Section 1 |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "updateAccount": {
      "$": {
        "id": "{{ $node[\"Create Account\"].json.createAccount.createdAccount.id }}",
        "customFieldValues": {
          "22PUGvBnXeYs": "Website",
          "22Nnj9KwwePZ": "New Lead",
          "22PU427xzLaS": "Google"
        }
      },
      "account": { "id": {}, "name": {} }
    }
  }
}
```

---

### getAccounts

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `searchTerm` | **R** | s | Partial name match (case-insensitive) |
| `type` | O | s | `customer`, `vendor`, or `both` (default) |

Returns: array of accounts with locations and associated jobs.

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}" },
    "organization": {
      "$": {},
      "accounts": {
        "$": {
          "size": 10,
          "where": { "and": [[["type","=","customer"],["name","like","Dempsey"]]] }
        },
        "nodes": { "id": {}, "name": {}, "type": {} }
      }
    }
  }
}
```

---

## 2. Contacts

### createContact

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `accountId` | **R** | s | Parent account ID |
| `name` | **R** | s | Full name |
| `title` | O | s | Role / job title |
| `customFields` | O | o | `{ "Email": "...", "Phone": "..." }` — by name, case-insensitive |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "createContact": {
      "$": {
        "accountId": "{{ $json.accountId }}",
        "name": "{{ $json.contact.name }}",
        "customFields": {
          "Email": "{{ $json.contact.email }}",
          "Phone": "{{ $json.contact.phone }}"
        }
      },
      "createdContact": { "id": {}, "name": {} }
    }
  }
}
```

---

### getContacts / getContactDetails

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `accountId` | O | s | `getContacts`: filter by parent account |
| `contactId` | **R** | s | `getContactDetails`: returns all custom fields |

---

## 3. Locations

> **NOTE:** A Location is required before you can create a Job. The job address in JT is the location address.

### createLocation

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `accountId` | **R** | s | Parent account ID |
| `address` | **R** | s | Full address: `123 Main St, Bozeman, MT 59715` |
| `name` | **R** | s | Display name — typically the street address |
| `contactId` | O | s | Link a contact to this location |
| `customFieldValues` | O | o | `{ fieldId: value }` |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "createLocation": {
      "$": {
        "accountId": "{{ $json.accountId }}",
        "name": "{{ $json.address }}",
        "address": "{{ $json.address }}, Bozeman, MT 59715"
      },
      "createdLocation": { "id": {}, "name": {} }
    }
  }
}
```

---

## 4. Jobs

### createJob

> **NOTE:** `customFields` on `createJob` accepts field **names** (not IDs), unlike `updateAccount` which requires IDs. This inconsistency is by design in PAVE.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `locationId` | **R** | s | Must create location first and use returned ID |
| `name` | **R** | s | Job display name — e.g. `Dempsey Bathroom Remodel` |
| `number` | O | s | Job number — auto-generated if omitted |
| `description` | O | s | Internal notes |
| `customFields` | O | o | `{ "Job Type": "Bathroom", "Phase": "1. Contacted" }` |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "createJob": {
      "$": {
        "locationId": "{{ $json.locationId }}",
        "name": "{{ $json.projectName }}",
        "customFields": {
          "Job Type": "Bathroom",
          "Phase": "1. Contacted"
        }
      },
      "createdJob": { "id": {}, "name": {}, "number": {} }
    }
  }
}
```

---

### searchJobs

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `searchTerm` | **R** | s | Partial match on job name or number |
| `searchBy` | O | s | `name` (default) or `number` |
| `status` | O | s | `open`, `closed`, `all` (default) |
| `createdAfter` | O | s | YYYY-MM-DD |
| `createdBefore` | O | s | YYYY-MM-DD |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}" },
    "organization": {
      "$": {},
      "jobs": {
        "$": { "where": { "=": [{ "field": ["number"] }, { "value": "281" }] } },
        "nodes": { "id": {}, "name": {}, "number": {} }
      }
    }
  }
}
```

---

### getJobDetails / getActiveJobs / setJobParameters

- **getJobDetails:** Returns full job record — location, account, custom fields, files, documents, tasks, time entries. Requires `jobId` (UUID).
- **getActiveJobs:** No params. Returns all jobs with at least one approved customer order (in-progress).
- **setJobParameters:** Updates arbitrary key-value pairs on the job.

---

## 5. Budget & Cost Items

### addBudgetLineItems ⭐ (Estimator Push — Critical)

> **KEY PATTERN:** This is the core operation used by the Estimate Assembler. Build an array of line items from the assembled estimate and POST them all in one call.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | **R** | s | Target job UUID |
| `lineItems` | **R** | a | Array of item objects — see structure below |

**Each line item object:**

| Field | Req | Type | Notes |
|---|---|---|---|
| `name` | **R** | s | Pipe-delimited: `Labor \| Tile \| Shower Installation` |
| `costCodeId` | **R** | s | From cost codes table in Section 1 |
| `costTypeId` | **R** | s | From cost types table in Section 1 |
| `unitId` | **R** | s | From units table in Section 1 |
| `quantity` | O | n | Default 1. Must be a number, not a string. |
| `unitCost` | O | n | Default 0. Number, not string. |
| `unitPrice` | O | n | Default 0. Number, not string. |
| `groupName` | O | s | Use ` > ` for nesting: `Tilework > Shower Tile Labor` |
| `groupDescription` | O | s | Group description |
| `description` | O | s | Item-level description / notes |
| `organizationCostItemId` | O | s | Links to org catalog item |
| `isTaxable` | O | b | Default false |
| `customFieldValues` | O | o | `{ customFieldId: value }` |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "addBudgetLineItems": {
      "$": {
        "jobId": "{{ $json.jobId }}",
        "lineItems": [
          {
            "name": "Labor | Tile | Shower Installation",
            "costCodeId": "22Nm3uGRAMma",
            "costTypeId": "22Nm3uGRAMmq",
            "unitId": "22Nm3uGRAMm9",
            "quantity": 16,
            "unitCost": 47.25,
            "unitPrice": 94.50,
            "groupName": "Tilework > Shower Tile Labor"
          },
          {
            "name": "Allowance | Shower Tile",
            "costCodeId": "22Nm3uGRAMma",
            "costTypeId": "22PQ4KZExZjP",
            "unitId": "22Nm3uGRAMmB",
            "quantity": 1,
            "unitCost": 1154,
            "unitPrice": 1500,
            "groupName": "Tilework > Selections"
          }
        ]
      },
      "addedBudgetLineItems": { "id": {}, "name": {}, "unitPrice": {} }
    }
  }
}
```

---

### getJobBudget

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | **R** | s | Returns cost groups + all line items with costs, prices, and margins |

---

### getCostItems / createCostItem / getCostItemDetails

These operate on the **org-level cost catalog**, not a specific job budget.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `searchName` | O | s | `getCostItems`: partial name match |
| `costCodeId` | O | s | `getCostItems`: filter by code |
| `costTypeId` | O | s | `getCostItems`: filter by type |
| `name` | **R*** | s | `createCostItem`: required |
| `costCodeId` | **R*** | s | `createCostItem`: required |
| `costTypeId` | **R*** | s | `createCostItem`: required |

### getCostCodes / getCostTypes / getUnits

No params. Return the lookup tables from Section 1.

---

## 6. Documents (Estimates, Invoices, POs, Bills)

### createDocument ⭐ (Critical for invoicing)

> **NOTE:** Always call `getDocumentTemplates` first to get the `documentTemplateId`. The template provides your company from-name, logo, display settings, and footer.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | **R** | s | Target job |
| `type` | **R** | s | `customerOrder` (Estimate), `customerInvoice` (Invoice), `vendorOrder` (PO), `vendorBill` (Bill), `bidRequest` |
| `documentTemplateId` | O | s | Get from `getDocumentTemplates`. Provides branding + footer. |
| `accountId` | O | s | Required for vendor docs. Auto-detected for customer docs. |
| `costCodeIds` | O | a | Filter which budget items appear on doc by cost code |
| `costGroupNames` | O | a | Filter by group name (case-insensitive) |
| `costItemIds` | O | a | Specific item IDs. Default: all un-documented items. |
| `costItemOverrides` | O | o | `{costItemId: {unitCost, unitPrice, quantity}}` — doc only, not budget |
| `name` | O | s | Document title — e.g. `Proposal`, `Deposit Invoice` |
| `subject` | O | s | Document subject line |
| `description` | O | s | Header text displayed on doc |
| `footer` | O | s | Footer text |
| `date` | O | s | YYYY-MM-DD — defaults to today |
| `dueDate` | O | s | YYYY-MM-DD |
| `taxRate` | O | s | e.g. `0.08` for 8% |

---

### updateDocument

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `documentId` | **R** | s | Document to update |
| `status` | O | s | `draft`, `pending`, `approved`, `denied` |
| `description` | O | s | |
| `pushToQbo` | O | b | Trigger QuickBooks sync |
| `costItemUpdates` | O | o | `{docCostItemId: {unitCost, unitPrice, quantity, description}}` |

---

### getDocuments / getDocumentLineItems / getDocumentTemplates

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | O | s | `getDocuments`: filter by job |
| `type` | O | s | `getDocuments`: `customerOrder`, `customerInvoice`, `all`, etc. |
| `documentId` | **R** | s | `getDocumentLineItems`: required — returns groups + items for that doc |
| `type` | **R** | s | `getDocumentTemplates`: required — same type enum as `createDocument` |

---

## 7. Payments

### createPayment

> **NOTE:** This records a payment against a document. It does NOT process a Stripe charge — that happens in the client portal. Use this to log manual/check payments or to record that a Stripe payment has cleared.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `amount` | **R** | n | Payment amount in dollars |
| `date` | **R** | s | YYYY-MM-DD |
| `documentId` | **R** | s | Document to record against |
| `description` | O | s | Memo / check number / payment method |
| `paymentType` | O | s | `credit` (customer pays you) or `debit` (you pay vendor). Auto-detected from doc type. |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "createPayment": {
      "$": {
        "amount": 10500,
        "date": "{{ $now.toISODate() }}",
        "documentId": "{{ $json.depositInvoiceId }}",
        "description": "Stripe deposit — 30%",
        "paymentType": "credit"
      },
      "createdPayment": { "id": {}, "amount": {}, "date": {} }
    }
  }
}
```

---

### getPayments

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | O | s | Filter by job |
| `documentId` | O | s | Filter by document |
| `accountId` | O | s | Filter by account |

---

## 8. Tasks & To-Dos

### createTask

> **KEY PATTERN:** Use `isToDo: true` for client journey checklist items. Use `isToDo: false` for calendar-scheduled work tasks.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `name` | **R** | s | Task title |
| `targetId` | **R** | s | Job, account, or location ID |
| `targetType` | **R** | s | `job`, `account`, `location` |
| `description` | O | s | Full description / script — supports long text |
| `assignees` | O | a | Array of user IDs: `["22Nm3uFeRB7s"]` |
| `startDate` | O | s | YYYY-MM-DD |
| `endDate` | O | s | YYYY-MM-DD |
| `isToDo` | O | b | `true` = checklist item, `false` = calendar task. Default: true |
| `isGroup` | O | b | Creates a group/folder header task |
| `progress` | O | n | 0–1 (0.5 = 50% complete) |
| `notify` | O | b | Notify assignees |

---

### Client Journey Task Template IDs (from job #280)

These are the pre-built task IDs. Reference them to mark complete or update progress via `updateTaskProgress`.

| Task Name | Stage | Task ID |
|---|---|---|
| S2 Confirmation Text | Stage 2 | `22PU9QAVFdNG` |
| S2 Pre-Visit Materials | Stage 2 | `22PU9QBeFkrw` |
| S3 Photo Upload | Stage 3 | `22PU9QCiLhkp` |
| S3 State Entry | Stage 3 | `22PU9QE2YA3A` |
| S3 Follow-Up Text | Stage 3 | `22PU9QFB9Art` |
| S4 Assemble Estimate | Stage 4 | `22PU9QGGLcpG` |
| S4 Present Estimate | Stage 4 | `22PU9QHby4DU` |
| S4 Day 3 Follow-Up | Stage 4 | `22PU9QKANqjS` |
| S4 Day 7 Follow-Up | Stage 4 | `22PU9QLUiiBG` |
| S4 Day 14 Follow-Up | Stage 4 | `22PU9QMg5P7r` |
| S5 Pre-Con Meeting | Stage 5 | `22PU9QPFJgK2` |
| S6 Final Walkthrough | Stage 6 | `22PU9QQYzM6v` |
| S6 Final Payment | Stage 6 | `22PU9QRZT2CE` |
| S6 Post-Project Package | Stage 6 | `22PU9RgkiAfz` |
| S6 Job Costing Review | Stage 6 | `22PU9RiC6QrF` |
| S7 Review Request (Day 1) | Stage 7 | `22PU9RjdYjFb` |
| S7 Referral Ask (Day 14) | Stage 7 | `22PU9Rm262U8` |
| S7 GBP Post (Day 30) | Stage 7 | `22PU9RnDzCH4` |
| S7 6-Month Check-In | Stage 7 | `22PU9RpUMeGt` |
| S7 1-Year Anniversary | Stage 7 | `22PU9RqhCNma` |
| Group Header | — | `22PU9Q8DpCmq` |

---

### updateTaskProgress

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `taskId` | **R** | s | Task to update |
| `progress` | O | n | 0–1 (1.0 = complete) |
| `name` | O | s | Rename |
| `description` | O | s | Update description / script |
| `startDate` | O | s | YYYY-MM-DD |
| `endDate` | O | s | YYYY-MM-DD |
| `isToDo` | O | b | |
| `notify` | O | b | |

---

### getTasks / getTaskDetails

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | O | s | Filter by job |
| `status` | O | s | `completed`, `inProgress`, `notStarted`, `all` |
| `taskType` | O | s | `todo`, `schedule`, `all` |
| `assigneeUserId` | O | s | Filter to specific person |
| `startDateFrom` / `startDateTo` | O | s | YYYY-MM-DD date range |
| `isGroup` | O | b | Filter to group headers only |
| `taskId` | **R** | s | `getTaskDetails`: includes assignees + dependencies |

---

## 9. Time Entries

> **VOICE PIPELINE:** The Voice Log Pipeline (Workflow #12) calls `createTimeEntry` for each trade detected in Eric's end-of-day voice note. `startedAt` / `endedAt` must be ISO 8601 with timezone.

### createTimeEntry

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | **R** | s | Job UUID (not job number) |
| `userId` | **R** | s | Person who did the work — use `22Nm3uFeRB7s` for Eric |
| `startedAt` | **R** | s | ISO 8601: `2026-03-20T07:00:00-07:00` |
| `endedAt` | **R** | s | ISO 8601: `2026-03-20T11:30:00-07:00` |
| `type` | O | s | `work` (default), `travel`, `break` |
| `costItemId` | O | s | Link to specific budget line item |
| `notes` | O | s | Description of work done |
| `isApproved` | O | b | Auto-approve if you're sole operator |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "createTimeEntry": {
      "$": {
        "jobId": "{{ $json.job_id }}",
        "userId": "22Nm3uFeRB7s",
        "startedAt": "{{ $json.date }}T07:00:00-07:00",
        "endedAt": "{{ $json.date }}T11:30:00-07:00",
        "notes": "{{ $json.description }}",
        "isApproved": true
      },
      "createdTimeEntry": { "id": {}, "notes": {} }
    }
  }
}
```

---

### getTimeEntries / getTimeEntryDetails / getTimeSummary

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | O | s | `getTimeEntries`: filter by job |
| `userId` | O | s | Filter by person |
| `startDate` / `endDate` | O | s | YYYY-MM-DD range |
| `isApproved` | O | b | Filter by approval status |
| `timeEntryId` | **R** | s | `getTimeEntryDetails`: full record |
| `groupBy` | O | s | `getTimeSummary`: `user`, `job`, `date` |

---

## 10. Daily Logs

> **VOICE PIPELINE:** Also triggered by Workflow #12. The `daily_log_summary` extracted by Claude maps directly to the `notes` field here.

### createDailyLog

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | **R** | s | Job UUID |
| `date` | **R** | s | YYYY-MM-DD |
| `notes` | **R** | s | Full log text. This is also the source for the daily client update text. |
| `customFields` | O | o | `{ "Weather": "Sunny" }` — by field name |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}", "notify": false },
    "createDailyLog": {
      "$": {
        "jobId": "{{ $json.job_id }}",
        "date": "{{ $json.date }}",
        "notes": "{{ $json.daily_log_summary }}"
      },
      "createdDailyLog": { "id": {}, "date": {}, "notes": {} }
    }
  }
}
```

---

### getDailyLogs / getDailyLogDetails / getDailyLogsSummary

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `jobId` | O | s | Filter by job |
| `userId` | O | s | Filter by person |
| `startDate` / `endDate` | O | s | Date range |
| `logId` | **R** | s | `getDailyLogDetails`: full record |
| `groupBy` | O | s | `getDailyLogsSummary`: `user`, `job`, `date` |

---

## 11. Files

> ⚠️ **NOTE:** `uploadFile` requires a **public HTTPS URL**. You cannot upload raw file bytes directly. Stage the file somewhere public first (S3 presigned URL, Cloudflare R2, etc.).

### uploadFile / updateFile / copyFile

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `targetId` | **R** | s | `uploadFile`: Job, doc, account, etc. |
| `targetType` | **R** | s | `uploadFile`: `organization`, `job`, `account`, `document`, `timeEntry`, `dailyLog` |
| `url` | **R** | s | `uploadFile`: public HTTPS URL to the file |
| `name` | O | s | Override filename |
| `folder` | O | s | Use `getJobFolders` to see available folder names |
| `fileTagIds` | O | a | Use `getFileTags` to look up tag IDs |
| `fileId` | **R** | s | `updateFile` / `copyFile`: source file ID |
| `sourceFileId` | **R** | s | `copyFile`: file to duplicate |

### attachFileToBudgetItem

Upload the file to the job first, then use the returned `fileId` to attach it to a specific budget item.

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `fileId` | **R** | s | File already uploaded to the job |
| `jobId` | **R** | s | |
| `targetId` | **R** | s | Cost item or group ID from `getJobBudget` |
| `targetType` | **R** | s | `costItem` or `costGroup` |

### getFiles / getFileTags / getJobFolders / readFile

- **getFiles:** Filter by `jobId`, `documentId`, or `folder`
- **getFileTags:** No params — returns org-level file tags
- **getJobFolders:** Requires `jobId` — returns available folder names
- **readFile:** Requires `fileId` — returns file content inline

---

## 12. Comments

### createComment

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `name` | **R** | s | Subject line |
| `message` | **R** | s | Body text |
| `targetId` | **R** | s | Entity to comment on |
| `targetType` | **R** | s | `job`, `account`, `file`, `dailyLog`, `timeEntry`, `task`, `document`, `organization`, `comment` |
| `parentCommentId` | O | s | For replies on comment threads |
| `isPinned` | O | b | Pin to top |
| `isVisibleToAll` | O | b | |
| `isVisibleToCustomerRoles` | O | b | Makes visible in client portal |
| `isVisibleToInternalRoles` | O | b | Default true |
| `isVisibleToVendorRoles` | O | b | |

### getComments / getCommentDetails

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `targetId` | O | s | Must pair with `targetType` for `getComments` |
| `targetType` | O | s | |
| `commentId` | **R** | s | `getCommentDetails`: full message + reply thread + files |

---

## 13. Dashboards

### createDashboard / updateDashboard / getDashboards

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `name` | **R** | s | Dashboard display name |
| `tiles` | **R** | s | JSON-stringified array of tile objects |
| `type` | O | s | Default `organization` |
| `id` | **R** | s | `updateDashboard`: dashboard to update |
| `name` | O | s | `getDashboards`: partial match filter |

**Tile types:** `custom` (charts/KPIs), `dataView` (tables), `activity` (feed)  
**Chart types:** `singleValue`, `line`, `bar`, `pie`, `table`  
**Aggregations:** `count`, `sum`, `avg`  
**Target types:** `job`, `document`, `payment`, `dailyLog`

**Where clause patterns:**

```js
// Filter by field value:
{ "=": [{ "field": ["type"] }, { "value": "customerOrder" }] }

// Filter by custom field:
{ "=": [{ "field": ["cfv:22Nnj9KwwePZ", "values"] }, { "value": "Active Customer" }] }

// Date range (current month):
{ "between": [{ "field": ["createdAt"] }, [
  { "datetime": { "startOf": "month" } },
  { "datetime": { "endOf": "month" } }
]]}
```

**Existing dashboards:**
- Sales Pipeline & Lead Tracker: `id 22PU2MtJJiM7`
- Lead Source & Conversion Tracker: `id 22PU7MUwuq3A`

---

## 14. Custom Fields & Search

### getCustomFields

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `targetType` | **R** | s | `customer`, `customerContact`, `vendor`, `vendorContact`, `location`, `job`, `costItem`, `dailyLog` |

Use this to discover field IDs dynamically. Returns fieldId, name, type, and options for option fields.

---

### searchByCustomField

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `entityType` | **R** | s | `jobs`, `contacts`, `accounts`, `costItems` |
| `customFieldName` | **R** | s | Field name (case-insensitive) |
| `customFieldValue` | **R** | s | Value to match |
| `operator` | O | s | `=`, `!=`, `>`, `<`, `>=`, `<=`, `like` — default `=` |

```json
{
  "query": {
    "$": { "grantKey": "{{ $env.JT_GRANT_KEY }}" },
    "organization": {
      "$": {},
      "accounts": {
        "$": {
          "where": {
            "=": [{ "field": ["cfv:22Nnj9KwwePZ", "values"] }, { "value": "New Lead" }]
          }
        },
        "nodes": { "id": {}, "name": {} }
      }
    }
  }
}
```

---

## 15. Organization & Users

### getUsers / listOrganizations / switchOrganization

| Parameter | Req | Type | Notes |
|---|---|---|---|
| `searchTerm` | O | s | `getUsers`: name or email partial match |
| `organizationId` | **R** | s | `switchOrganization`: all subsequent calls use this org |

`listOrganizations`: No params. Shows active + available orgs.

---

# Section 4 — Complete n8n Workflow Recipes

## Recipe 1 — Calculator Lead → JT Account + Contact + Job

Triggered by the website calculator webhook (Workflow #09). Creates the full customer record in JT, sets all custom fields, fires a Slack notification.

| Step | n8n Node | Operation | Key Inputs / Notes |
|---|---|---|---|
| 1 | Webhook | Receive lead | POST from calculator: `contact` + `projectState` + `estimate` |
| 2 | HTTP Request | `createAccount` | `name`, `type=customer`, `organizationId` |
| 3 | HTTP Request | `updateAccount` | `id` (from step 2), `customFieldValues`: Lead Source, Status, Source |
| 4 | HTTP Request | `createContact` | `accountId` (from step 2), `name`, `email`, `phone` |
| 5 | HTTP Request | `createLocation` | `accountId` (from step 2), `address`, `name` |
| 6 | HTTP Request | `createJob` | `locationId` (from step 5), `name`, `customFields`: Job Type + Phase=1. Contacted |
| 7 | HTTP Request | Slack webhook | Format message with customer name, estimate range, project config |
| 8 | Postgres | INSERT lead | Archive full payload to `leads` table |

> **NODE CHAINING:** Each node references the previous via `$node["Node Name"].json.PATH` — e.g. the `createJob` node uses `locationId` from `$node["Create Location"].json.createLocation.createdLocation.id`

---

## Recipe 2 — Estimate Assembler Push (Workflow #08b)

Receives assembled estimate JSON from the React app, validates, pushes all line items to JT, archives to Postgres, notifies via Slack.

| Step | n8n Node | Operation | Notes |
|---|---|---|---|
| 1 | Webhook | Receive estimate payload | POST from assembler app with `jobId` + `lineItems` array |
| 2 | Code | Duplicate check | Query Postgres: has this job been pushed already? If yes, abort. |
| 3 | HTTP Request | `addBudgetLineItems` | Full `lineItems` array in one call |
| 4 | Postgres | INSERT estimate archive | Store `projectState` + `lineItems` + `jobId` + timestamp |
| 5 | HTTP Request | Slack webhook | Summary: job name, item count, total cost, total price, margin % |

> ⚠️ **DUPLICATE PREVENTION:** There is no easy bulk-delete for budget items in JT. Always check Postgres for an existing record before pushing. Pushing twice creates duplicate line items.

---

## Recipe 3 — Voice Note → Time Entries + Daily Log (Workflow #12)

iOS Shortcut sends Granola transcript to n8n. Claude extracts structured data. n8n pushes time entries and daily log to JT, archives to Postgres, notifies via Slack.

| Step | n8n Node | Operation | Notes |
|---|---|---|---|
| 1 | Webhook | Receive transcript | POST: `{ transcript, date, source: 'granola' }` |
| 2 | HTTP Request | Fetch active jobs | GET open JT jobs to inject into Claude prompt |
| 3 | HTTP Request | Claude API | `claude-sonnet-4-5` extraction → returns `time_entries`, `materials`, `conditions`, `daily_log_summary` |
| 4 | Code | Confidence check | If `job_match.confidence = 'low'` → Slack for confirmation. High/medium → continue. |
| 5 | HTTP Request (loop) | `createTimeEntry` | One call per entry in `time_entries` array. `userId` always Eric's ID. |
| 6 | HTTP Request | `createDailyLog` | `notes = daily_log_summary` from Claude |
| 7 | Postgres | INSERT daily_logs | Full structured archive including raw transcript |
| 8 | HTTP Request | Slack webhook | Formatted: job, total hours, trades, materials, conditions, tomorrow plan |

**Voice Pipeline Cost Code Map** (Claude maps natural language → JT IDs):

| Trade | JT Cost Code ID |
|---|---|
| Demo | `22Nm3uGRAMmJ` |
| Framing | `22Nm3uGRAMmN` |
| Plumbing | `22Nm3uGRAMmT` |
| Electrical | `22Nm3uGRAMmS` |
| Tile | `22Nm3uGRAMma` |
| Drywall | `22Nm3uGRAMmW` |
| Painting | `22Nm3uGRAMmf` |
| Finish Carpentry | `22Nm3uGRAMmb` |
| Admin | `22Nm3uGRAMmH` |

---

## Recipe 4 — LSA Lead Response (Workflow #10, Planned)

When a new JT customer account is created with Source = 'Local Service', trigger immediate Slack ping and SMS.

| Step | n8n Node | Operation | Notes |
|---|---|---|---|
| 1 | JT Webhook | New customer created | Subscribe to `customerCreated` event in JT |
| 2 | Code | Source check | Filter: only proceed if Source = 'Local Service' |
| 3 | HTTP Request | Twilio SMS | Text Eric: "New LSA lead: [name]. Call within 5 min." |
| 4 | HTTP Request | Slack webhook | Detailed notification with customer name, phone, notes |
| 5 | HTTP Request | `updateAccount` | Set Status = 'New Lead' if not already set |

---

## Recipe 5 — Follow-Up Reminders (Workflow #11, Planned)

Daily cron at 8am MT checks for stale leads and pings Slack.

| Step | n8n Node | Operation | Notes |
|---|---|---|---|
| 1 | Cron | Trigger daily | `0 8 * * 1-5` (weekdays, 8am MT) |
| 2 | HTTP Request | `getAccounts` | Fetch all customer accounts |
| 3 | HTTP Request | `searchByCustomField` | Status = 'New Lead' or 'Appointment Set' |
| 4 | Code | Stale filter | Keep accounts where Appointment date > 7 days ago with no update |
| 5 | HTTP Request | Slack webhook | List of stale leads with names, last-contact date, phone numbers |

---

# Section 5 — Critical Gotchas & Known Issues

## 1. createAccount vs updateAccount — Custom Fields (Most Common Error)

> 🚨 **CRITICAL:** `createAccount` does NOT accept `customFieldValues`. Required custom fields (Lead Source) must be set via a separate `updateAccount` call immediately after creation.

| Operation | Custom Field Pattern | Field Key Format |
|---|---|---|
| `createAccount` | ❌ Not accepted — returns error | — |
| `updateAccount` | ✅ `customFieldValues` in `$` args | `{ "fieldId": "value" }` — uses **IDs** |
| `createJob` | ✅ `customFields` in `$` args | `{ "fieldName": "value" }` — uses **names** |
| `createDailyLog` | ✅ `customFields` in `$` args | `{ "fieldName": "value" }` — uses **names** |
| `createContact` | ✅ `customFields` in `$` args | `{ "fieldName": "value" }` — uses **names** |

**Two-step pattern in n8n:** Node 1 = `createAccount` → Node 2 = `updateAccount` using `$node["Create Account"].json.createAccount.createdAccount.id`

---

## 2. Numeric Fields Must Be Numbers, Not Strings

PAVE silently accepts string numbers but calculations will be wrong.

```js
// WRONG:
"quantity": "16",
"unitCost": "47.25",

// CORRECT:
"quantity": 16,
"unitCost": 47.25,
```

---

## 3. Job ID vs Job Number

Almost every PAVE operation requires the JT job **UUID** (e.g. `22PU9Q8DpCmq`), not the human-readable job **number** (e.g. `#281`). Use `searchJobs` with `searchBy: "number"` to look up UUID by number.

---

## 4. groupName Nesting Uses ` > ` (Space-Arrow-Space)

Budget group nesting in `addBudgetLineItems` requires the exact separator with spaces on both sides:

```js
// CORRECT:
"groupName": "Tilework > Shower Tile Labor"

// WRONG — creates literal group name:
"groupName": "Tilework>Labor"
"groupName": "Tilework / Labor"
```

---

## 5. Time Entry Timestamps Must Be ISO 8601 With Timezone

Bozeman is UTC-7 (MDT summer) or UTC-6 (MST winter).

```js
// Correct:
"startedAt": "2026-03-20T07:00:00-07:00",
"endedAt":   "2026-03-20T11:30:00-07:00",

// Voice pipeline approximation when exact times unknown:
// startedAt = date + "T07:00:00-07:00"
// endedAt   = date + "T" + (7 + totalHours) + ":00:00-07:00"
```

---

## 6. Grant Key Security

```js
// WRONG — key exposed in workflow JSON:
"grantKey": "grant_abc123xyz..."

// CORRECT — use environment variable:
"grantKey": "{{ $env.JT_GRANT_KEY }}"
```

Never hardcode the grant key in n8n node bodies or code nodes. Store in n8n Credentials or environment variables. Keys shown once at creation — copy immediately.

---

## 7. Duplicate Budget Push Prevention

> 🚨 **CRITICAL:** There is no easy bulk-delete for budget items in JT. If you push a budget twice, you get duplicate line items. Always check Postgres before pushing.

```js
// Postgres pre-check in n8n Code node:
const existing = await $runQuery(
  "SELECT id FROM estimates WHERE job_id = $1 AND pushed_at IS NOT NULL",
  [jobId]
);
if (existing.rows.length > 0) {
  throw new Error("Job " + jobId + " already has a pushed estimate. Confirm to overwrite.");
}
```

---

## 8. notify Flag — Set false in All Automated Calls

Set `"notify": false` inside `$` for every automated workflow call. Otherwise JT sends email/push notifications to customers and team members on every automated action — noisy during testing and confusing in production.

---

## 9. PAVE Returns HTTP 200 Even on Errors

Check `$json.errors` in the response, not just the HTTP status code. Add an error check node after every write operation.

```js
// n8n Code node — add after every PAVE HTTP Request:
const response = $input.first().json;
if (response.errors && response.errors.length > 0) {
  const msg = response.errors.map(e => e.message).join("; ");
  throw new Error("JT API Error: " + msg);
}
return [{ json: response }];
```

---

# Section 6 — n8n Node Patterns & Expressions

## Referencing Data Between Nodes

```js
// Current node output:
{{ $json.createAccount.createdAccount.id }}

// Previous node by name:
{{ $node["Create Account"].json.createAccount.createdAccount.id }}

// Item from input array (loop context):
{{ $input.item.json.fieldName }}

// Current date (Mountain time):
{{ $now.toISODate() }}                           // "2026-03-20"
{{ $now.toISO() }}                               // "2026-03-20T14:30:00.000Z"
{{ $now.setZone("America/Denver").toISO() }}     // Mountain time ISO
```

---

## Loop Pattern — One API Call Per Array Item

For the voice pipeline, you need one `createTimeEntry` per `time_entries` element. Use a Code node to fan out the array:

```js
// n8n Code node — split array into items:
const entries = $input.first().json.time_entries;
return entries.map(entry => ({ json: entry }));

// Connect to HTTP Request node.
// Each item becomes a separate API call.
// Reference fields as: "notes": "{{ $json.description }}"
```

---

## Slack Notification Template

```json
{
  "text": "🏠 *New Calculator Lead*",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*{{ $json.contact.name }}*\n{{ $json.contact.phone }}\n{{ $json.contact.email }}"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Estimate:* ${{ $json.estimate.low }} – ${{ $json.estimate.high }}\n*Timeline:* {{ $json.projectState.timeline }}"
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*JT Job:* <https://app.jobtread.com/jobs/{{ $json.jtJobId }}|View in JobTread>"
      }
    }
  ]
}
```

---

## AI-in-the-Loop Validation Node

Place a Claude API call before any JT budget push to validate the payload:

**System prompt:**
```
You are a JobTread PAVE API validator for Heartwood Craft. Given a lineItems payload 
intended for addBudgetLineItems, verify:
1. All required fields present (name, costCodeId, costTypeId, unitId)
2. costCodeId, costTypeId, unitId match known Heartwood IDs
3. groupName nesting uses " > " separator with spaces
4. quantity, unitCost, unitPrice are numbers not strings
5. name follows pipe-delimited convention: "Labor | Trade | Task"

Return the payload unchanged if valid.
Return { "error": "description of issue" } if invalid.
```

This costs ~500 tokens per validation — cheap insurance against malformed pushes.

---

# Section 7 — JobTread Native Workflows

JT Workflows (launched Sep 2025) are trigger-based automations built directly into JobTread — no n8n required. They complement n8n: JT Workflows handles pure in-JT actions, n8n handles cross-system operations.

**Decision rule:** Use JT Workflows for actions that stay inside JT. Use n8n for anything crossing system boundaries (JT↔Slack, JT↔Postgres, JT↔Claude API, JT↔Twilio). Both can coexist on the same trigger.

---

## Available Trigger Events

| Trigger | Description | Key Use Case |
|---|---|---|
| Customer created | New account added | Apply task template, set initial status |
| Job created | New job record created | Apply client journey task checklist |
| Document created | Any document type added | — |
| Document updated | Status/content changed | Advance pipeline when estimate signed |
| Document expired | Due date passed | Auto-decline expired estimates |
| Task completed | To-do checked off | Trigger next stage reminder |
| Time entry created | Hours logged | Remind Eric to complete daily log |
| Job phase changed | Phase custom field updated | Notify on pipeline movement |

---

## Available Actions

| Action | Notes |
|---|---|
| Apply task template | Apply pre-built to-do list to a job — use for client journey checklist |
| Apply schedule template | Apply calendar schedule template |
| Advance job in pipeline | Change Phase custom field automatically |
| Decline document | Auto-decline when expired |
| Send notification | In-app notification to a team member |
| Send external webhook | If available — triggers n8n from JT events (confirm in seminar) |

---

## Recommended JT Workflows for Heartwood

| # | Trigger | Filter | Action | Notes |
|---|---|---|---|---|
| 1 | Job created | (none) | Apply client journey task template | Replaces planned n8n task creation |
| 2 | Document updated | Type=estimate, Status=approved | Advance Phase to 5. Budget Approved | Replaces manual phase update |
| 3 | Document expired | Type=estimate | Decline document | Keeps pipeline clean automatically |
| 4 | Time entry created | (none) | Notify Eric to complete daily log | Habit trigger for Voice Pipeline |
| 5 | Customer created | Source=LSA | In-app notify (+ pair with n8n #10 for SMS) | 5-min response speed |

---

## Key Questions for the Automations Seminar

1. **Can workflow actions hit an external webhook URL?** If yes, JT Workflows can push-trigger n8n instead of n8n polling JT.
2. **Does "apply task template" preserve task descriptions/scripts?** The client journey scripts live in the description fields.
3. **Can filters reference custom field values?** Specifically: can you filter on Source to apply different templates to different lead types?
4. **How does branching logic work in practice?** Ask for a live demo.
5. **Are there rate limits on workflow executions?** Important for a high-volume automation setup.

---

# Section 8 — Heartwood MCP Server Integration

The self-hosted Heartwood MCP Server (`workspace/projects/heartwood-mcp/`) replaces the $50/month datax JT MCP connector. It exposes 63 JT tools via MCP protocol over SSE transport.

**Deployed:** 2026-03-25 · **Status:** Operational (createAccount verified)

---

## Architecture

| Component | Location | Notes |
|---|---|---|
| TypeScript source | `workspace/projects/heartwood-mcp/src/` | Build with `npm run build` |
| Built server | `/opt/business/heartwood-mcp/dist/` | Deployed manually after build |
| NixOS module | `domains/ai/mcp/heartwood/index.nix` | `hwc.ai.mcp.heartwood.enable = true` |
| systemd service | `heartwood-mcp.service` | SSE on `127.0.0.1:6100` |
| Caddy proxy | Port 16100 | `https://hwc.ocelot-wahoo.ts.net:16100/sse` |
| Secrets | agenix `jobtread-grant-key` | Injected via `heartwood-mcp-env.service` |
| API reference | `domains/business/jobtread_api_reference.md` | This file |

---

## PAVE Envelope Format (Critical)

PAVE is NOT a REST API. ALL requests are `POST https://api.jobtread.com/pave` with auth **in the body** (not as a Bearer header). The request envelope wraps everything in a `query` key:

```json
{
  "query": {
    "$": {
      "grantKey": "{{ from agenix secret }}",
      "notify": false,
      "viaUserId": "22Nm3uFeRB7s"
    },
    "OPERATION_NAME": {
      "$": { /* parameters */ },
      "returnedField1": {},
      "returnedField2": { "nestedField": {} }
    }
  }
}
```

**Key rules:**
- Auth is `grantKey` inside `query.$`, NOT an `Authorization: Bearer` header
- Operations are named keys (`createAccount`, `updateAccount`, `organization`)
- Fields to return are nested empty objects (`{ id: {}, name: {} }`)
- Parameters go inside the operation's `$` key
- Responses are nested under the operation name

---

## Operation Patterns

### Create: `createAccount`, `createJob`, `createContact`, etc.

```json
{
  "query": {
    "$": { "grantKey": "...", "notify": false },
    "createAccount": {
      "$": { "name": "Test", "type": "customer", "organizationId": "22Nm3uFevXMb" },
      "createdAccount": { "id": {}, "name": {}, "type": {} }
    }
  }
}
```

Response: `{ "createAccount": { "createdAccount": { "id": "22PUPiRetepp", ... } } }`

**Return field gotcha:** `createdAccount` does NOT support all fields that a query does. Fields like `updatedAt`, `createdAt`, and nested relations will cause HTTP 400. Use only basic fields (`id`, `name`, `type`) for create return values.

### Update: `updateAccount`, `updateDocument`, etc.

```json
{
  "query": {
    "$": { "grantKey": "...", "notify": false },
    "updateAccount": {
      "$": { "id": "22PUPiRetepp", "customFieldValues": { "22PUGvBnXeYs": "Website" } },
      "account": { "id": {}, "name": {} }
    }
  }
}
```

### Read (single by ID): uses `node` query

```json
{
  "query": {
    "$": { "grantKey": "..." },
    "node": {
      "$": { "id": "22PUPiRetepp" },
      "... on Account": { "id": {}, "name": {}, "type": {}, "customFieldValues": { "id": {}, "value": {}, "customField": { "id": {}, "name": {} } } }
    }
  }
}
```

### Query (list/search): uses `organization` key

```json
{
  "query": {
    "$": { "grantKey": "..." },
    "organization": {
      "$": {},
      "accounts": {
        "$": { "size": 10, "where": { "and": [[["name", "like", "%Dempsey%"]]] } },
        "nodes": { "id": {}, "name": {}, "type": {} }
      }
    }
  }
}
```

---

## MCP Server Implementation Notes

### PaveClient (`src/pave/client.ts`)

Methods map to PAVE patterns:

| Method | PAVE Pattern | Example |
|---|---|---|
| `pave.create(opName, params, fields)` | `{ createAccount: { $: params, createdAccount: fields } }` | `pave.create("createAccount", { name, type }, ACCOUNT_BASIC_FIELDS)` |
| `pave.update(opName, params, fields)` | `{ updateAccount: { $: params, account: fields } }` | `pave.update("updateAccount", { id, ...data }, ACCOUNT_BASIC_FIELDS)` |
| `pave.read(entityType, id, fields)` | `{ node: { $: { id }, "... on Type": fields } }` | `pave.read("account", id, ACCOUNT_FIELDS)` |
| `pave.query(opts)` | `{ organization: { $: {}, entities: { $: where, nodes: fields } } }` | `pave.query({ entityPlural: "accounts", returnFields, where })` |
| `pave.raw(ops)` | Direct envelope passthrough | For special operations |

### MCP SDK Integration (`src/index.ts`)

Uses the low-level `Server` class (not `McpServer`) because `McpServer.tool()` requires Zod schemas and treats plain JSON schemas as "annotations", causing tool arguments to not be passed to handlers. With `Server` + `setRequestHandler(CallToolRequestSchema, ...)`, we get direct access to `request.params.arguments`.

### Where Clause Format

PAVE `where` uses nested arrays, not the object/condition format common in ORMs:

```json
{ "and": [[["fieldName", "operator", value]]] }
```

Operators: `=`, `!=`, `>`, `>=`, `<`, `<=`, `like`, `in`, `not in`, `is null`, `is not null`

The helpers in `src/tools/jt/helpers.ts` build these:
- `buildFilter(params, mappings)` — builds `where` from optional params with `=` default
- `buildSearchFilter(params, searchParam, searchField)` — wraps search term with `%` for `like`

---

## Deployment Workflow

After code changes in `workspace/projects/heartwood-mcp/`:

```bash
cd workspace/projects/heartwood-mcp
npm run build                              # Compile TypeScript
sudo cp -r dist/* /opt/business/heartwood-mcp/dist/   # Deploy
sudo systemctl restart heartwood-mcp       # Restart service
journalctl -u heartwood-mcp -f             # Watch logs
```

---

## Verified Operations Log

| Date | Tool | Status | Notes |
|---|---|---|---|
| 2026-03-25 | `jt_create_account` | PASS | Created `22PUPiRetepp` via SSE transport |

---

## Known Issues & Lessons Learned

### 1. Return fields differ between create and query contexts

`createdAccount` only supports basic fields (`id`, `name`, `type`). Requesting `updatedAt`, `createdAt`, or nested relations causes HTTP 400. Use `ACCOUNT_BASIC_FIELDS` for create/update, full `ACCOUNT_FIELDS` for query/read.

### 2. McpServer.tool() doesn't work with JSON schemas

The MCP SDK's `McpServer` class expects Zod schemas for tool registration. Passing plain JSON schema objects as the 3rd arg to `server.tool(name, desc, schema, cb)` causes the SDK to interpret them as "annotations" rather than parameter schemas. The callback then receives only the `extra` context object (sessionId, headers) instead of tool arguments. **Fix:** Use low-level `Server` class with `setRequestHandler(CallToolRequestSchema, ...)`.

### 3. PAVE auth is in the body, not a header

Unlike most APIs, PAVE does NOT use `Authorization: Bearer <token>`. The `grantKey` goes inside the request body under `query.$`. Sending a Bearer header results in the key being ignored and auth failing silently.

### 4. Missing `default.nix` for NixOS directory imports

NixOS `import ./heartwood` expects `default.nix`, not `index.nix`. The PR shipped only `index.nix`, requiring a `default.nix` shim (`import ./index.nix`).

### 5. TypeScript operator type mismatch

`PaveCondition.operator` uses a string literal union, but helper functions typed operators as plain `string`. Fix: use `PaveWhereCondition` tuple type `[string, string, unknown]` which avoids the issue.

---

*Heartwood Craft · Bozeman, MT · iheartwoodcraft.com · Org ID: `22Nm3uFevXMb`*
