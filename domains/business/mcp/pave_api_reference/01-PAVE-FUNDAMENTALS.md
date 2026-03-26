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

## Error Handling

- **Pave returns HTTP 200 even on errors.** Always check `response.errors` array.
- Error messages are descriptive: `A non-null value is required at "organization"."$"."id"`
- Common 400 causes: missing required field, wrong field type, return fields on update mutations, tuple-format where clauses.
