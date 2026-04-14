# n8n Workflow Patterns for Pave

---

## HTTP Request Node — Baseline

| Field | Value |
|---|---|
| Method | POST |
| URL | `https://api.jobtread.com/pave` |
| Authentication | None (auth in body) |
| Content-Type | `application/json` |
| Body | JSON/Raw |

---

## Request Template

```json
{
  "query": {
    "$": {
      "grantKey": "{{ $env.JT_GRANT_KEY }}",
      "notify": false,
      "viaUserId": "22Nm3uFeRB7s"
    },
    "OPERATION": {
      "$": { /* params */ },
      "returnField": {}
    }
  }
}
```

---

## Reading Responses

```js
// After create:
{{ $json.createAccount.createdAccount.id }}

// After org query (array):
{{ $json.organization.accounts.nodes[0].id }}

// Previous node:
{{ $node["Create Account"].json.createAccount.createdAccount.id }}
```

---

## Error Check Node (Add After Every Write)

```js
const response = $input.first().json;
if (response.errors && response.errors.length > 0) {
  const msg = response.errors.map(e => e.message).join("; ");
  throw new Error("JT API Error: " + msg);
}
return [{ json: response }];
```

---

## Loop Pattern (Array → Individual API Calls)

```js
// Fan out array items:
const entries = $input.first().json.time_entries;
return entries.map(entry => ({ json: entry }));
// Each item becomes a separate HTTP Request call
```

---

## Key Expression Patterns

```js
{{ $now.toISODate() }}                         // "2026-03-26"
{{ $now.setZone("America/Denver").toISO() }}   // Mountain time ISO
{{ $env.JT_GRANT_KEY }}                        // Environment variable
{{ $input.item.json.fieldName }}               // Current loop item
```

---

## Workflow Recipes (Summary)

| # | Name | Trigger | Key Operations |
|---|---|---|---|
| 08b | Estimate Push | Webhook from assembler | `addBudgetLineItems` → Postgres archive → Slack |
| 09 | Calculator Lead | Website webhook | `createAccount` → `updateAccount` → `createContact` → `createLocation` → `createJob` → Slack |
| 10 | LSA Response | JT webhook (planned) | Filter Source=LSA → Twilio SMS → Slack |
| 11 | Follow-Up | Daily cron (planned) | Query stale leads → Slack reminders |
| 12 | Voice Pipeline | iOS Shortcut webhook | Claude extraction → `createTimeEntry` (loop) → `createDailyLog` → Postgres → Slack |

---

## Two-Step Account Creation Pattern

```
Node 1: createAccount (name, type, organizationId)
  ↓
Node 2: updateAccount (id from Node 1, customFieldValues with field IDs)
```

This is required because `createAccount` doesn't reliably accept custom field values.
