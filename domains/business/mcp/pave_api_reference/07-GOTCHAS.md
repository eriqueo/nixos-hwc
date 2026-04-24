# Pave Gotchas & Known Issues

Every lesson learned the hard way. Read this when debugging a 400 error or unexpected behavior.

---

## 1. Auth Is in the Body, Not a Header

**CRITICAL.** Pave does NOT use `Authorization: Bearer <token>`. The `grantKey` goes inside `query.$`:

```json
{ "query": { "$": { "grantKey": "YOUR_KEY" }, ... } }
```

Sending a Bearer header results in the key being ignored and auth failing **silently**.

---

## 2. Update Mutations Return Empty — No Return Fields

**Discovered 2026-03-26.** All update mutations (`updateAccount`, `updateJob`, `updateCostItem`, etc.) return `{}`. Do NOT include a return-field block:

```json
// WRONG — causes 400:
"updateAccount": {
  "$": { "id": "...", "name": "New" },
  "account": { "id": {}, "name": {} }   // ← This breaks it
}

// CORRECT:
"updateAccount": {
  "$": { "id": "...", "name": "New" }
}
```

If you need the updated data, re-query separately.

---

## 3. Create Return Fields Are Limited

`createdXxx` return blocks only support basic fields (`id`, `name`, `type`). Requesting `createdAt`, `updatedAt`, or nested relations causes HTTP 400.

Use basic fields for create returns, then query separately for full data.

---

## 4. Organization Queries Require `$: { id }`

An empty `"$": {}` on `organization` returns HTTP 400 with `A non-null value is required at "organization"."$"."id"`.

```json
// WRONG:
"organization": { "$": {}, "accounts": { ... } }

// CORRECT:
"organization": { "$": { "id": "22Nm3uFevXMb" }, "accounts": { ... } }
```

---

## 5. Where Clause Format — Operator-Object, NOT Tuples

The #1 source of query errors.

```json
// CORRECT:
"where": { "like": [{ "field": ["name"] }, { "value": "%Dempsey%" }] }

// WRONG — tuple format causes 400:
"where": { "and": [[["name", "like", "%Dempsey%"]]] }
```

Field paths are always arrays: `["name"]`, `["cfv:FIELD_ID", "values"]`.

> **Warning (2026-04-04):** The `cfv:` syntax does NOT work for job custom fields in organization-level queries. Error: `The field "cfv:22P4fguBu3Ub" does not exist at "job"`. Custom field values ARE returned in query results (`customFieldValues.nodes`), so you can query without the `cfv:` filter and then filter client-side. It's unknown whether `cfv:` works for other entity types (accounts, contacts, etc.).

---

## 6. Numeric Fields Must Be Numbers

Pave silently accepts string numbers but calculations go wrong.

```json
// WRONG:
"quantity": "16", "unitCost": "47.25"

// CORRECT:
"quantity": 16, "unitCost": 47.25
```

---

## 7. Job ID vs Job Number

Almost every operation requires the JT **UUID** (e.g. `22PU9Q8DpCmq`), not the human-readable **number** (e.g. `#281`). Use `searchJobs` to look up UUID by number.

---

## 8. createAccount Custom Fields May Fail

In practice, `createAccount` may not accept `customFieldValues` for all field types (specifically option fields with required validation). Use a two-step pattern:

1. `createAccount` — basic fields only
2. `updateAccount` — set custom fields using field **IDs**

---

## 9. Custom Field Key Format Differs by Operation

| Operation | Key Format | Example |
|---|---|---|
| `updateAccount` | Field **IDs** | `{ "22PUGvBnXeYs": "Website" }` |
| `createJob` | Field **names** | `{ "Job Type": "Bathroom" }` |
| `createDailyLog` | Field **names** | `{ "Weather": "Sunny" }` |
| `createContact` | Field **names** | `{ "Email": "..." }` |

This inconsistency is by design in Pave.

---

## 10. groupName Nesting Uses ` > ` (Space-Arrow-Space)

Budget group nesting in `addBudgetLineItems` / `createCostGroup` requires exact separator:

```json
// CORRECT:
"groupName": "Tilework > Shower Tile Labor"

// WRONG:
"groupName": "Tilework>Labor"
"groupName": "Tilework / Labor"
```

---

## 11. Time Entry Timestamps Must Be ISO 8601 With Timezone

Bozeman is `America/Denver` — UTC-7 (MDT summer) or UTC-6 (MST winter).

```json
"startedAt": "2026-03-20T07:00:00-07:00"
```

---

## 12. HTTP 200 Even on Errors

Pave returns HTTP 200 even when the operation fails. Always check `response.errors`:

```json
{
  "errors": [{ "message": "A non-null value is required at ..." }]
}
```

---

## 13. Grant Key Expiration

Keys expire after **3 months of inactivity**. Set a calendar reminder. Keys shown only once at creation — copy immediately. Store in env variables, never hardcode.

---

## 14. No Bulk Delete for Budget Items

There is no easy bulk-delete for budget cost items/groups in Pave. Pushing a budget twice creates duplicates. Always check before pushing.

---

## 15. `__schema` Introspection Does Not Work

Pave is NOT standard GraphQL. Use `schema: {}` at query root instead of `__schema`. The field `__schema` returns "does not exist" error.

---

## 16. McpServer.tool() vs Server Class (MCP SDK)

The MCP SDK's `McpServer.tool()` expects Zod schemas. Passing plain JSON schema objects causes the SDK to treat them as "annotations", and tool arguments don't reach the handler. Use the low-level `Server` class with `setRequestHandler(CallToolRequestSchema, ...)` for direct argument access.

---

## 17. NixOS Module Naming

NixOS `import ./heartwood` expects `default.nix`, not `index.nix`. If you only ship `index.nix`, add a shim: `default.nix` → `import ./index.nix`.

---

## 18. notify Flag in Automations

Set `"notify": false` in `query.$` for every automated call. Otherwise JT sends email/push notifications on every API action.

---

## 19. Max Page Size Is 100 — Large Fields Can Cause 413

**Discovered 2026-04-04.** PAVE enforces a maximum `size` of 100 per page. Requesting more causes a validation error: `Expected size of 200 to be no more than 100`.

Even at `size: 100`, requesting entities with many nested fields (e.g., jobs with `customFieldValues.nodes`, `location.account`, etc.) can trigger HTTP 413 (Request Entity Too Large). In practice, `size: 50` is a safe ceiling for full-detail job queries.

---

## 20. Job Name Has 30-Character Limit

**Discovered 2026-04-23.** `createJob` and `updateJob` enforce a 30-character max on the `name` field. Longer names cause HTTP 400. The estimator PWA should truncate or validate before pushing.

---

## 21. createCostItem with jobId Creates Org Catalog Entries

**Discovered 2026-04-23.** `createCostItem` with `jobId` placement does NOT just add an item to the job budget. It creates a **new org-wide catalog entry** and links it to the job. JT enforces uniqueness on `name + costCode + costType + unit` across the entire catalog. If an item with the same combo exists, you get:

```
400 - "A cost item with the name \"Labor | Demo | Floor Tile\", code \"0200 Demolition\", type \"Labor\" and unit \"Hours\" already exists in the catalog"
```

**This is the wrong mutation for pushing estimates.** Two correct alternatives:

1. **`createJob` / `updateJob` with `lineItems`** — declarative tree replacement, scoped to job (see Gotcha #22)
2. **`createCostItem` with `costGroupId` placement** — additive, job-scoped, no catalog pollution. Create a cost group first (`createCostGroup` with `jobId`), then create items inside it with `costGroupId`. Only `jobId` placement triggers the catalog path.

---

## 22. lineItems on updateJob Is Declarative Tree Replacement

**Discovered 2026-04-23.** Sending `lineItems` on `updateJob` **replaces the entire budget**:
- Items with `id` → preserved (matched to existing)
- Items without `id` → created new
- Existing items NOT in the array → **deleted**

To add items without destroying existing ones, first read the budget, merge, then send the full tree. For fresh jobs (just created), this isn't an issue.

---

## 23. Discriminated Union _type Syntax (Not Documented Publicly)

**Discovered 2026-04-23 by capturing JT UI network traffic.**

`lineItems` arrays in `createJob`/`updateJob`/`createCostGroup` use `_type` to discriminate between cost groups and cost items:

```json
{ "_type": "costGroup", "name": "Demo", "lineItems": [...] }
{ "_type": "costItem", "name": "Floor Tile", "costCodeId": "...", ... }
```

NOT `_on_<TypeName>` (output only). NOT `{ newCostItem: {...} }` wrapping. See `01-PAVE-FUNDAMENTALS.md` for full syntax.

---

## 24. cfv: Where Clauses Don't Work for Jobs

**Discovered 2026-04-04.** Despite the `["cfv:FIELD_ID", "values"]` field path syntax documented in Gotcha #5, using `cfv:` in `where` clauses for **job** custom fields in organization-level queries fails:

```json
// FAILS with: "The field \"cfv:22P4fguBu3Ub\" does not exist at \"job\""
"where": { "in": [{ "field": ["cfv:22P4fguBu3Ub", "values"] }, [{ "value": "5. Budget Approved" }]] }
```

Custom field values ARE returned in query results (as `customFieldValues.nodes[].customField.id` + `.value`), just not filterable server-side.

**Workaround:** Query without the `cfv:` filter, then filter client-side in JS by inspecting `customFieldValues.nodes`.
