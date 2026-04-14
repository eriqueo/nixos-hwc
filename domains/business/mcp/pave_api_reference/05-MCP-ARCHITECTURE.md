# MCP Architecture: How Tools Wrap Pave

This file explains how MCP (Model Context Protocol) tools translate user requests into Pave queries. Covers both the DataX MCP (third-party) and the JT MCP (self-hosted).

---

## The Big Picture

```
User Request → Claude/AI Agent → MCP Tool → Pave Query → JobTread API → Response → MCP Tool → Agent → User
```

An MCP tool is a function that:
1. Accepts structured parameters from the AI agent
2. Translates those parameters into a Pave query
3. Sends the query to `POST https://api.jobtread.com/pave`
4. Extracts and formats the response for the agent

The MCP server is the bridge between the AI agent (which thinks in natural language) and the Pave API (which requires precise JSON queries).

---

## DataX MCP (Third-Party: ai.winyourdata.com)

DataX is Elliott Wittstruck's commercial MCP server for JobTread. It provides ~63 tools covering the most common JT operations.

**How DataX works (per Elliott):**
- Each tool is a defined Pave query with sequencing instructions for Claude
- The tool descriptions tell Claude what parameters to collect and in what order
- DataX translates the tool parameters into the correct Pave envelope format
- Elliott's architecture: defined Pave queries → MCP tool wrappers → Claude instructions

**Producer model:** 80% to producer, 20% to DataX company

**Key tools:** `jobtread_search_jobs`, `jobtread_get_job_budget`, `jobtread_add_budget_line_items`, `jobtread_create_document`, `jobtread_update_document`, `jobtread_get_cost_items`, `jobtread_create_job`, etc.

### DataX Tool → Pave Mapping Examples

| DataX Tool | Pave Operation | Notes |
|---|---|---|
| `jobtread_search_jobs` | `organization.jobs` query with where clause | Wraps search params into Pave where |
| `jobtread_get_job_budget` | `job.costGroups` + `job.costItems` query | Fetches full budget tree |
| `jobtread_add_budget_line_items` | `createCostGroup` / `createCostItem` | Maps lineItems array to nested Pave create calls |
| `jobtread_create_document` | `createDocument` | Maps params to Pave createDocument input |
| `jobtread_update_document` | `updateDocument` | Maps status/description/costItemUpdates |
| `jobtread_get_cost_item_details` | `costItem` query by id | Single item fetch |
| `jobtread_update_task_progress` | `updateTask` | Maps progress/dates/name |

### How DataX Creates New Tools (Elliott's Pattern)

When a new feature request comes in (like allowance toggling):

1. **Identify the Pave mutation:** Find `createXxx` or `updateXxx` in the schema
2. **Map the input parameters:** Decide which Pave inputs to expose as MCP tool params
3. **Write the tool definition:** Name, description (with Claude instructions), parameter schema
4. **Wire the Pave query:** Build the envelope with auth, the mutation, and return fields
5. **Test:** "I don't test it. Just tell them to test it and tell me if it doesn't work."

For the allowance feature, Elliott said it would be ~2 new tools: `create_allowance` and `update_allowance`, each with params mapping to the `allowanceType` field on `createCostItem` / `updateCostItem`.

---

## JT MCP (Self-Hosted)

The JT MCP server is a self-hosted alternative running on the homeserver. Built in TypeScript, deployed via NixOS.

**Location:** `workspace/projects/jt-mcp/`
**Deployed to:** `/opt/business/jt-mcp/dist/`
**Service:** `jt-mcp.service` on `127.0.0.1:6100`
**Caddy proxy:** `https://hwc.ocelot-wahoo.ts.net:16100/sse`

### Architecture

```
Claude.ai ──SSE──→ Caddy (16100) ──→ jt-mcp (6100) ──POST──→ api.jobtread.com/pave
```

### PaveClient Methods (`src/pave/client.ts`)

| Method | Pave Pattern | Use |
|---|---|---|
| `pave.create(opName, params, fields)` | `{ [opName]: { $: params, createdXxx: fields } }` | Create operations |
| `pave.update(opName, params)` | `{ [opName]: { $: params } }` | Update (no return fields) |
| `pave.read(entityType, id, fields)` | `{ node: { $: { id }, "... on Type": fields } }` | Single entity by ID |
| `pave.query(opts)` | `{ organization: { $: { id }, entities: { $, nodes: fields } } }` | List/search |
| `pave.raw(ops)` | Direct envelope | Special operations |

### MCP SDK Notes

Uses the low-level `Server` class, NOT `McpServer`. The `McpServer.tool()` method requires Zod schemas and treats plain JSON schema objects as "annotations", causing tool arguments to not be passed to handlers. With `Server` + `setRequestHandler(CallToolRequestSchema, ...)`, you get direct access to `request.params.arguments`.

### Where Clause Helpers (`src/tools/jt/helpers.ts`)

- `buildFilter(params, mappings)` — builds Pave `where` from optional params with `=` default
- `buildSearchFilter(params, searchParam, searchField)` — wraps search term with `%` for `like`

### Deployment

```bash
cd workspace/projects/jt-mcp
npm run build
sudo cp -r dist/* /opt/business/jt-mcp/dist/
sudo systemctl restart jt-mcp
journalctl -u jt-mcp -f
```

---

## Building a New MCP Tool — Step by Step

Whether contributing to DataX or adding to the JT MCP:

### 1. Find the Pave operation
Search the schema for the relevant `createXxx`, `updateXxx`, or query pattern. Reference `02-PAVE-OPERATIONS.md`.

### 2. Decide which inputs to expose
Not every Pave input needs to be an MCP param. Expose the ones users would actually set. Use sensible defaults for the rest.

### 3. Define the tool schema
```json
{
  "name": "jobtread_update_cost_item_allowance",
  "description": "Update the allowance type on a budget cost item. Use jobtread_get_job_budget to find cost item IDs first.",
  "parameters": {
    "costItemId": { "type": "string", "description": "Cost item ID", "required": true },
    "allowanceType": { "type": "string", "enum": ["cost", "costAndFee", "price", null], "description": "Allowance type or null to clear" }
  }
}
```

### 4. Build the Pave query
```json
{
  "query": {
    "$": { "grantKey": "...", "notify": false },
    "updateCostItem": {
      "$": {
        "id": "COST_ITEM_ID",
        "allowanceType": "cost"
      }
    }
  }
}
```

### 5. Handle the response
Update returns `{}`. For reads, extract `nodes` from paginated responses.

### 6. Write clear tool descriptions
The description is what tells Claude how to use the tool. Include:
- What the tool does
- What other tools to call first (prerequisite data)
- What the parameters mean
- Any gotchas

---

## DataX vs JT MCP — When to Use Which

| Scenario | Use |
|---|---|
| Standard JT operations with team | DataX — it's maintained, tested by the community |
| Custom Heartwood-specific automations | JT MCP — tailored to your workflow |
| Contributing new features | DataX — broader impact, revenue share |
| Debugging / understanding the API | Either — both hit the same Pave endpoint |
| Operations DataX doesn't support yet | JT MCP — you control the tool set |
