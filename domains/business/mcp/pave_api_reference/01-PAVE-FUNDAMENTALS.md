# Pave Fundamentals

## What Pave Is (and Isn't)

Pave is JobTread's **proprietary query language**. It looks like GraphQL but it is NOT GraphQL. Key differences:

- Standard GraphQL introspection (`__schema`, `__type`) does **not work**. Use `schema: {}` at query root instead.
- There are no separate query/mutation types — everything lives under the `root` object.
- Auth is in the request body, not in headers.
- All requests are `POST` to a single endpoint.

**Endpoint:** `POST https://api.jobtread.com/pave`

---

## The Request Envelope

Every Pave request follows this structure:

```json
{
  "query": {
    "$": {
      "grantKey": "YOUR_GRANT_KEY",
      "notify": false,
      "timeZone": "America/Denver",
      "viaUserId": "USER_ID"
    },
    "OPERATION_NAME": {
      "$": { /* operation inputs */ },
      "fieldToReturn": {},
      "nestedField": {
        "subField": {}
      }
    }
  }
}
```

### Root `$` Parameters

| Parameter | Required | Type | Notes |
|---|---|---|---|
| `grantKey` | Yes | string | API key. Created at `https://app.jobtread.com/grants`. Shown only once — copy immediately. Expires after 3 months of inactivity. |
| `notify` | No | boolean | Set `false` in automations to suppress JT notifications to users/customers. Default: `true`. |
| `timeZone` | No | string | IANA timezone string. Use `America/Denver` for Bozeman (Mountain Time). |
| `viaUserId` | No | jobtreadId | Scope the action as a specific user. |

### Auth Is in the Body

**CRITICAL:** Pave does NOT use `Authorization: Bearer <token>` headers. The `grantKey` goes inside `query.$`. Sending a Bearer header results in the key being ignored and auth failing silently.

---

## Field Selection

You select which fields to return by including them as keys with empty object values `{}`. This is how Pave knows what data to send back.

```json
{
  "query": {
    "$": { "grantKey": "..." },
    "job": {
      "$": { "id": "SOME_JOB_ID" },
      "id": {},
      "name": {},
      "number": {},
      "location": {
        "name": {},
        "city": {},
        "state": {}
      }
    }
  }
}
```

**Rules:**
- Scalar fields (string, number, boolean, date): use `"fieldName": {}`
- Object fields (relationships): nest the sub-fields you want
- Array fields (paginated lists): see Pagination below
- If you don't include a field, it won't be in the response

---

## Pagination

List fields use a standard pagination envelope:

```json
"costItems": {
  "$": {
    "size": 50,
    "page": "NEXT_PAGE_TOKEN",
    "where": { /* filter */ },
    "sortBy": [{ "field": ["name"], "order": "asc" }]
  },
  "nodes": {
    "id": {},
    "name": {}
  },
  "nextPage": {},
  "count": {}
}
```

| Parameter | Type | Notes |
|---|---|---|
| `size` | int (≥1) | Page size. Required if you want to limit results. |
| `page` | string | Pass the `nextPage` token from a previous response to get the next page. |
| `where` | expression | Filter — see Where Clauses below. |
| `sortBy` | array | Up to 5 sort fields. Each: `{ "field": ["fieldName"], "order": "asc" }` |

**Response shape:**
- `nodes` — the array of records
- `nextPage` — token for next page, or `null` if no more
- `previousPage` — token for previous page
- `count` — total count (if requested)

---

## Where Clauses

Pave where clauses use an **operator-object format**. This is the #1 source of errors.

### Single Condition

```json
"where": { "=": [{ "field": ["name"] }, { "value": "Dempsey" }] }
```

### Multiple Conditions (AND)

```json
"where": {
  "and": [
    { "=": [{ "field": ["type"] }, { "value": "customer" }] },
    { "like": [{ "field": ["name"] }, { "value": "%Dempsey%" }] }
  ]
}
```

### Custom Field Filter

```json
"where": {
  "=": [{ "field": ["cfv:CUSTOM_FIELD_ID", "values"] }, { "value": "New Lead" }]
}
```

### Available Operators

| Operator | Example |
|---|---|
| `=` | Exact match |
| `!=` | Not equal |
| `<`, `<=`, `>`, `>=` | Comparison |
| `like` | Pattern match. Requires explicit `%` wildcards: `%text%` = contains, `text%` = starts with |
| `between` | Range: `{ "between": [{ "field": ["date"] }, [{ "value": "2026-01-01" }, { "value": "2026-12-31" }]] }` |
| `in` | Set membership: `{ "in": [{ "field": ["status"] }, [{ "value": "draft" }, { "value": "pending" }]] }` |
| `not in` | Exclusion |
| `not like` | Negative pattern |

### Structure Rules

- Each condition: `{ "OPERATOR": [{ "field": ["FIELD_PATH"] }, { "value": VALUE }] }`
- The `field` value is **always an array**: `["name"]`, `["cfv:FIELD_ID", "values"]`
- Combine with `"and": [...]` or `"or": [...]`
- `like` requires explicit `%` wildcards

### WRONG (Causes 400)

```json
// Tuple format — does NOT work in Pave:
"where": { "and": [[["name", "like", "%Dempsey%"]]] }
```

---

## Operation Types

Every operation in Pave lives at the query root. There are four families:

### Create Operations

Pattern: `createXxx` → returns `createdXxx`

```json
"createAccount": {
  "$": { "name": "Test", "type": "customer", "organizationId": "ORG_ID" },
  "createdAccount": { "id": {}, "name": {} }
}
```

**Return field limitation:** `createdXxx` only supports basic fields (`id`, `name`, `type`). Requesting `createdAt`, `updatedAt`, or nested relations causes HTTP 400. Query separately after creation if you need full data.

### Update Operations

Pattern: `updateXxx` → returns empty `{}`

```json
"updateAccount": {
  "$": { "id": "ACCOUNT_ID", "name": "New Name" }
}
```

**CRITICAL:** Update operations do NOT accept return fields. Do NOT include a response block like `"account": { "id": {} }` — this causes 400. The response is always `{"updateXxx": {}}`. Re-query if you need updated data.

### Delete Operations

Pattern: `deleteXxx` → returns empty `{}`

```json
"deleteAccount": {
  "$": { "id": "ACCOUNT_ID" }
}
```

### Read Operations (Single by ID)

Use the entity name at root with `$: { id }`:

```json
"job": {
  "$": { "id": "JOB_ID" },
  "id": {},
  "name": {},
  "location": { "name": {} }
}
```

### Read Operations (List/Search)

Query through the `organization` key:

```json
"organization": {
  "$": { "id": "ORG_ID" },
  "accounts": {
    "$": { "size": 10, "where": { /* filter */ } },
    "nodes": { "id": {}, "name": {} }
  }
}
```

**CRITICAL:** The organization query requires `"$": { "id": "ORG_ID" }`. An empty `"$": {}` returns HTTP 400.

---

## Expression System

Pave has a rich expression system used in where clauses, formulas, and computed fields. Key expression types:

- **Arithmetic:** `+`, `-`, `*`, `/`, `^`, `round`, `sqrt`, `floor`, `ceil`
- **Logic:** `and`, `or`, `!`
- **Comparison:** `<`, `<=`, `=`, `>`, `>=`, `between`, `in`, `like`
- **Date/time:** `date`, `datetime` with `startOf`/`endOf`/`fromNow`
- **String:** `concat`, `like`
- **Aggregation:** `coalesce`, `max`, `min`
- **Type casting:** `cast` to string, number, boolean, date, datetime

Example — current month filter:
```json
{ "between": [
  { "field": ["createdAt"] },
  [
    { "datetime": { "startOf": "month" } },
    { "datetime": { "endOf": "month" } }
  ]
]}
```

---

## Discriminated Union Inputs (`_type`)

**Discovered 2026-04-23 by capturing JT UI network traffic — not in public API docs.**

Some input fields accept a discriminated union — an array of objects where each object's `_type` field determines its schema. This is used for `lineItems` in `createJob`, `updateJob`, `createCostGroup`, and `createDocument`.

### `_type` Values for `lineItems`

| `_type` | Purpose | Key Fields |
|---------|---------|------------|
| `"costGroup"` | Create a budget group/section | `name`, nested `lineItems` |
| `"costItem"` | Create a budget line item | `name`, `costCodeId`, `costTypeId`, `unitId`, `quantity`, `unitCost`, `unitPrice` |

### Example: `createJob` with Grouped Budget

```json
{
  "query": {
    "$": { "grantKey": "..." },
    "createJob": {
      "$": {
        "locationId": "LOC_ID",
        "name": "Bath Remodel",
        "lineItems": [
          {
            "_type": "costGroup",
            "name": "Demo",
            "lineItems": [
              {
                "_type": "costItem",
                "name": "Labor | Demo | Floor Tile",
                "costCodeId": "22Nm3uGRAMmJ",
                "costTypeId": "22Nm3uGRAMmq",
                "unitId": "22Nm3uGRAMm9",
                "quantity": 10.8,
                "unitCost": 47.25,
                "unitPrice": 94.50
              }
            ]
          },
          {
            "_type": "costItem",
            "name": "Ungrouped Item",
            "quantity": 1,
            "unitCost": 100,
            "unitPrice": 150
          }
        ]
      },
      "createdJob": { "id": {}, "number": {}, "name": {} }
    }
  }
}
```

### Declarative Tree Replacement

`lineItems` on `updateJob` is a **full tree replacement**:
- Items with an `id` field are preserved (matched to existing)
- Items without `id` are created new
- Existing items NOT in the array are **deleted**
- To add items to an existing budget, you must first read the current budget and include all existing items with their IDs

### Important

- `_type` is the input discriminator — NOT `_on_<TypeName>` (that's query output only)
- NOT `{ newCostItem: {...} }` wrapping — no such pattern exists
- Line item name uniqueness is scoped **per-job**, NOT org-wide
- `createCostItem` with `jobId` placement is a DIFFERENT code path that enforces org-wide catalog uniqueness — avoid it for budget pushes

---

## Additive Budget Push (createCostGroup + createCostItem)

**Discovered 2026-04-23.** For adding items to an existing job budget WITHOUT replacing it, use the two-mutation sequence:

1. **`createCostGroup`** with `jobId` → returns `createdCostGroup.id`
2. **`createCostItem`** with `costGroupId` → returns `createdCostItem.id`

This is **additive** — existing budget items are untouched. Unlike `createCostItem` with `jobId` placement (Gotcha #21), `costGroupId` placement is job-scoped and does NOT create org catalog entries.

### Example: Add a Grouped Item to Job #300

**Step 1 — Create the group:**
```json
{
  "query": {
    "$": { "grantKey": "...", "notify": false },
    "createCostGroup": {
      "$": { "jobId": "22PW6UsgufG3", "name": "Demo" },
      "createdCostGroup": { "id": {}, "name": {} }
    }
  }
}
```

**Step 2 — Create item inside the group:**
```json
{
  "query": {
    "$": { "grantKey": "...", "notify": false },
    "createCostItem": {
      "$": {
        "costGroupId": "<id from step 1>",
        "name": "Labor | Demo | Floor Tile",
        "costCodeId": "22Nm3uGRAMmJ",
        "costTypeId": "22Nm3uGRAMmq",
        "unitId": "22Nm3uGRAMm9",
        "quantity": 10.8,
        "unitCost": 47.25,
        "unitPrice": 94.50
      },
      "createdCostItem": { "id": {}, "name": {} }
    }
  }
}
```

### Nested Groups (e.g. "Demo > Labor")

For `groupName` with `>` separator:
1. `createCostGroup` with `jobId` for top-level ("Demo") → `parentGroupId`
2. `createCostGroup` with `parentCostGroupId` for sub-group ("Labor") → `childGroupId`
3. `createCostItem` with `costGroupId = childGroupId` for each item

### When to Use Which

| Approach | Use Case | Behavior |
|----------|----------|----------|
| `createJob`/`updateJob` + `lineItems` | Full estimate push, known complete budget | Declarative replacement |
| `createCostGroup` + `createCostItem` | Add items to existing budget | Additive, non-destructive |

---

## Verified Working Examples

**Tested 2026-04-23 via Explorer + n8n workflow #08b (estimate-push).**

These payloads were sent to production and confirmed working. Job IDs are proof of successful execution.

### createJob with 73-item Grouped Budget (Job #300)

Job `22PW6UsgufG3` — Greg Wagner, "bathroom remodel". Created via `updateJob` with full budget tree. 73 line items across 12 cost groups pushed successfully in a single call.

### createJob with lineItems (Job #305)

Job `22PW6nQdGWSY` — created via `createJob` with `lineItems` embedded. Single PAVE call created job + budget atomically.

### Minimal Working Payload

```json
{
  "query": {
    "$": { "grantKey": "...", "notify": false },
    "createJob": {
      "$": {
        "locationId": "22PVyFahVXVy",
        "name": "Test Job",
        "lineItems": [
          {
            "_type": "costGroup",
            "name": "Demo",
            "lineItems": [
              {
                "_type": "costGroup",
                "name": "Labor",
                "lineItems": [
                  {
                    "_type": "costItem",
                    "name": "Labor | Demo | Floor Tile",
                    "costCodeId": "22Nm3uGRAMmJ",
                    "costTypeId": "22Nm3uGRAMmq",
                    "unitId": "22Nm3uGRAMm9",
                    "quantity": 10.8,
                    "unitCost": 47.25,
                    "unitPrice": 94.50
                  }
                ]
              }
            ]
          },
          {
            "_type": "costGroup",
            "name": "Allowances",
            "lineItems": [
              {
                "_type": "costItem",
                "name": "Allowance | Bathtub",
                "costCodeId": "22Nm3uGRAMmg",
                "costTypeId": "22Nm3uGRAMmr",
                "unitId": "22Nm3uGRAMmB",
                "quantity": 1,
                "unitCost": 1200,
                "unitPrice": 1714.32
              }
            ]
          }
        ]
      },
      "createdJob": { "id": {}, "number": {}, "name": {} }
    }
  }
}
```

**Response:**
```json
{
  "createJob": {
    "createdJob": {
      "id": "22PW6nQdGWSY",
      "number": "305",
      "name": "Test Job"
    }
  }
}
```

### updateJob with lineItems (Budget Replacement)

```json
{
  "query": {
    "$": { "grantKey": "...", "notify": false },
    "updateJob": {
      "$": {
        "id": "22PW6UsgufG3",
        "lineItems": [
          {
            "_type": "costGroup",
            "name": "Preconstruction",
            "lineItems": [
              {
                "_type": "costItem",
                "name": "Admin | Planning | Site Walkthrough",
                "costCodeId": "22Nm3uGRAMmH",
                "costTypeId": "22Nm3uGRAMmq",
                "unitId": "22Nm3uGRAMm9",
                "quantity": 2,
                "unitCost": 47.25,
                "unitPrice": 67.57
              }
            ]
          }
        ]
      }
    }
  }
}
```

**Response:** `{ "updateJob": {} }` (empty — standard for update mutations, see Gotcha #2).

**Warning:** This replaces the ENTIRE job budget. See Gotcha #22.

---

## Error Handling

- **Pave returns HTTP 200 even on errors.** Always check `response.errors` array.
- Error messages are descriptive: `A non-null value is required at "organization"."$"."id"`
- Common 400 causes: missing required field, wrong field type, return fields on update mutations, tuple-format where clauses.
