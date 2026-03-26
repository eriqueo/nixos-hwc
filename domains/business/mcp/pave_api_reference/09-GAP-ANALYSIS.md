# Gap Analysis: Pave vs MCP Coverage

Known gaps between what the Pave API supports and what DataX / Heartwood MCP tools currently expose. These are feature contribution opportunities.

**Last updated:** 2026-03-26

---

## Gap 1: Allowance Type (Confirmed by Schema + Elliott)

**Facebook post:** User asked why Claude/DataX can't toggle allowances on budget items.
**Elliott's response:** "DataX hasn't gotten to allowances yet."

### Pave Support

| Layer | Pave Operation | `allowanceType` Support | Status |
|---|---|---|---|
| Read | `costItem` entity | `allowanceType` field exists (nullable allowanceType) | ✅ In schema |
| Create | `createCostItem` | `allowanceType` accepted as input (nullable) | ✅ In schema |
| Update | `updateCostItem` | `allowanceType` accepted as optional input (nullable) | ✅ In schema |

**allowanceType enum values:** `cost`, `costAndFee`, `price`, or `null` (clear)

### DataX Coverage

| DataX Tool | `allowanceType` | Status |
|---|---|---|
| `jobtread_get_job_budget` | Not queried | ❌ Gap |
| `jobtread_get_cost_item_details` | Not queried | ❌ Gap |
| `jobtread_add_budget_line_items` | Not accepted as param | ❌ Gap |
| `jobtread_update_cost_item` | Tool does not exist | ❌ Gap |

### Proposed Fix (Elliott confirmed 2 tools)

1. **`create_allowance`** — wraps `createCostItem` with `allowanceType` param
2. **`update_allowance`** — wraps `updateCostItem` with `allowanceType` param
3. **Update read tools** — add `allowanceType` to return fields on `get_job_budget` and `get_cost_item_details`

### Pave Mutation Signature

```json
// Update existing cost item's allowance:
{
  "query": {
    "$": { "grantKey": "..." },
    "updateCostItem": {
      "$": {
        "id": "COST_ITEM_ID",
        "allowanceType": "cost"   // or "costAndFee", "price", null
      }
    }
  }
}

// Create new cost item with allowance:
{
  "query": {
    "$": { "grantKey": "..." },
    "createCostItem": {
      "$": {
        "name": "Bathtub Allowance",
        "costCodeId": "...",
        "costTypeId": "...",
        "unitId": "...",
        "allowanceType": "price",
        "quantity": 1,
        "unitCost": 2000,
        "unitPrice": 2500
      },
      "createdCostItem": { "id": {}, "name": {} }
    }
  }
}
```

---

## Gap 2: No `updateCostItem` Tool in DataX

Beyond allowances, there is NO general-purpose `update_cost_item` MCP tool in DataX at all. The existing tools can:
- **Read** cost items (`get_job_budget`, `get_cost_item_details`)
- **Create** cost items (`add_budget_line_items`)
- But NOT **update** existing ones (name, price, quantity, description, etc.)

### Pave Support
`updateCostItem` exists with full field support — every field on `costItem` can be updated.

### Impact
Users can't modify budget line items via AI. They have to go into the JT UI. This blocks workflows like:
- Updating prices after getting vendor quotes
- Marking items as having final actual cost
- Changing cost codes or types after initial setup
- Toggling allowance type (the Facebook complaint)

---

## Gap 3: No `updateCostGroup` Tool in DataX

Same pattern — can create and read groups but not update them.

### Pave Support
`updateCostGroup` exists. Can update name, description, quantity, display settings, and even restructure children via `lineItems`.

---

## Gap 4: No `deleteCostItem` / `deleteCostGroup` Tools

Pave supports both `deleteCostItem` and `deleteCostGroup`. DataX has neither. This means:
- Can't clean up duplicate budget items pushed by automation
- Can't remove line items that are no longer needed
- The "no bulk delete" problem is actually a tool gap, not a Pave limitation

---

## Gap 5: Document `allowanceCostItem` and `allowanceDeductionCostItem`

The `document` entity has two allowance-related fields:
- `allowanceCostItem` — the allowance line item on the doc
- `allowanceDeductionCostItem` — the deduction line item

`createDocument` accepts `allowanceCostItemId` as input. `updateDocument` also accepts it. Neither is exposed in DataX's `create_document` or `update_document` tools.

---

## Gap 6: Cost Item Formulas

Pave supports `unitCostFormula`, `unitPriceFormula`, and `quantityFormula` on cost items — these reference job parameters for dynamic calculations. DataX's `add_budget_line_items` does expose these, but `get_job_budget` may not return them, making it hard to audit existing formulas.

---

## Gap 7: Webhook Management

Pave supports `createWebhook`, `deleteWebhook` with `eventTypes` filtering. No MCP tools exist for managing webhooks, which would enable JT → n8n push-trigger architectures.

---

## Priority for DataX Contribution

| Priority | Gap | Effort | User Impact |
|---|---|---|---|
| 1 | Allowance CRUD | Medium (2 tools) | High — active FB complaint |
| 2 | updateCostItem (general) | Medium (1 tool) | High — enables budget editing |
| 3 | updateCostGroup | Low (1 tool) | Medium |
| 4 | deleteCostItem/Group | Low (2 tools) | Medium — fixes duplicate problem |
| 5 | Document allowance fields | Low (param additions) | Low |
| 6 | Webhook management | Medium (2 tools) | Niche but powerful |
