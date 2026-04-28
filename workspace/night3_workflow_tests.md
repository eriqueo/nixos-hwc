# Night 3: End-to-End Workflow Test Report

**Date:** 2026-03-27
**Environment:** Dev VM (no live n8n access — static analysis only)
**Analyst:** Claude Code (session claude/test-n8n-workflows-pVtr8)

---

## Executive Summary

**All 4 business workflows were analyzed from their JSON definitions, registry documentation, and NixOS configuration.** Live testing was not possible from this VM (no podman, no Tailscale, no SSH to HWC server).

| Workflow | Webhook Path | Auth | Status | Key Issue |
|----------|-------------|------|--------|-----------|
| #08b Estimate Router | POST /webhook/estimate-push | x-api-key header | 75% error rate (1/4 success) | Postgres archive uses PostgREST (may not be deployed) |
| #09 Calculator Lead | POST /webhook/calculator-lead | None | 90% error rate (1/10 success) | Depends on MCP server at localhost:6100 |
| #10 Lead Response | POST /webhook/new-lead | None | 0% error rate (healthy) | Working — most reliable workflow |
| #12 Voice Log | POST /webhook/daily-log | None | 100% error rate (0/1 success) | Claude API + PAVE integration untested |

**Bottom line:** #10 works. #08b, #09, and #12 have structural issues identifiable from code alone.

---

## Phase 1: Workflow Structures

### 1. work_estimate_router (#08b)

**Source:** `domains/automation/n8n/parts/workflows/08b-estimate-router.json`
**n8n ID:** `jbIqSwVByVnEAk7e`
**Nodes:** 16
**Active:** Yes

**Trigger:** POST /webhook/estimate-push
**Auth:** `x-api-key` header validated against `$env.ESTIMATOR_API_KEY`

**Pipeline:**
```
Webhook → Validate Request (check action="push_estimate", jtPayload array, jobId or newJob)
        → Is New Job? (IF mode === "new_job")
          → YES: Create JT Job (PAVE createJob) → Parse Created Job
          → NO: Use Existing Job (passthrough)
        → Merge Job Data
        → Push to JobTread (PAVE addBudgetLineItems, continueOnFail=true, 30s timeout)
        → Parse JT Result
        → Archive to Postgres (HTTP POST to PostgREST, continueOnFail=true)
        → JT Push Success? (IF)
          → YES: Notify Slack (Success)
          → NO: Notify Slack (Failure)
        → Respond Success (webhook response)
```

**Expected Payload:**
```json
{
  "action": "push_estimate",
  "mode": "existing",
  "jobId": "uuid",
  "jobNumber": "281",
  "jobName": "Test Job",
  "customerId": "uuid",
  "customerName": "Test Customer",
  "projectType": "bathroom",
  "projectState": {},
  "jtPayload": [
    {
      "name": "Labor | Demo | Bathroom Demo",
      "costCodeId": "22Nm3uGRAMmJ",
      "costTypeId": "22Nm3uGRAMmq",
      "unitId": "22Nm3uGRAMm9",
      "quantity": 8,
      "unitCost": 47.25,
      "unitPrice": 94.50
    }
  ],
  "totals": { "cost": 1000, "price": 1500, "items": 10, "laborHrs": 8, "margin": 33.3 }
}
```

**IMPORTANT:** The task description payload format uses `estimate.line_items` — the *actual* workflow expects `jtPayload[]` at the top level and `action: "push_estimate"` (not `"estimate-push"`).

---

### 2. work_calculator_lead (#09)

**Source:** `workspace/media/n8n-workflows/work-calculator-lead.json`
**n8n ID:** `SoLwmxgkMILrOYbP`
**Nodes:** 11 (Webhook + Extract Lead + 6 JT calls via MCP + Prepare DB + Postgres + Slack + Respond)
**Active:** Yes

**Trigger:** POST /webhook/calculator-lead
**Auth:** None (public-facing for website calculator)

**Pipeline:**
```
Webhook → Extract Lead (validate name + phone required)
        → JT: Create Account (POST localhost:6100/call, tool=jt_create_account)
        → JT: Update Account (POST localhost:6100/call, tool=jt_update_account, set custom fields)
        → JT: Create Contact (POST localhost:6100/call, tool=jt_create_contact)
        → JT: Create Location (POST localhost:6100/call, tool=jt_create_location)
        → JT: Create Job (POST localhost:6100/call, tool=jt_create_job)
        → Prepare DB Record (merge all JT IDs)
        → Postgres: Archive Lead (INSERT into hwc.calculator_leads)
        → Slack: Notify Eric
        → Respond to Webhook (200 with jt_account_id + jt_job_id)
```

**Expected Payload:**
```json
{
  "contact": { "name": "Test User", "phone": "406-555-0199", "email": "test@example.com", "notes": "test" },
  "projectState": { "project_type": "full_gut", "bathroom_size": "medium", "shower_tub": "shower_only", "tile_level": "mid", "fixtures": "upgraded", "features": ["heated_floor", "niches"], "timeline": "just_exploring" },
  "estimate": { "low": 22000, "high": 32000 },
  "source": "website_calculator"
}
```

**Key architectural difference:** This workflow calls the **Heartwood MCP server** (`localhost:6100/call`) instead of direct PAVE GraphQL. All other workflows use raw PAVE.

---

### 3. work_lead_response (#10)

**Source:** Not in git (stored in n8n database only)
**n8n ID:** `lead-response-automation`
**Nodes:** 29
**Active:** Yes

**Trigger:** POST /webhook/new-lead
**Auth:** None documented

**Pipeline (from registry):**
```
Webhook → Log raw payload to Postgres (webhook_payloads table)
        → Validate phone → E.164 normalize
        → Business hours check (7am-7pm Mon-Sat, Mountain Time)
          → Business hours: Immediate ntfy push + Slack
          → After hours: Schedule notification for 8am next business day
        → Claude API: Analyze lead (extract service type, urgency, etc.)
        → 2-hour follow-up reminder (if no response)
        → Postgres logging + Slack + Twilio SMS
```

**Expected Payload:**
```json
{
  "name": "John Smith",
  "phone": "4065551234",
  "email": "john@example.com",
  "service_type": "bathroom remodel",
  "source": "website"
}
```

**Status:** This is the **most reliable workflow** — 0% error rate, 5+ recent successful runs as of March 25.

---

### 4. work_voice_log (#12)

**Source:** Not in git (stored in n8n database only)
**n8n ID:** `XAm7ehKjJers5NqC`
**Nodes:** 18
**Active:** Yes

**Trigger:** POST /webhook/daily-log
**Auth:** None documented

**Pipeline (from registry):**
```
Webhook → Validate Transcript (non-empty check)
        → Is Valid? (IF)
          → NO: Respond 400
          → YES: continue
        → Fetch Active Jobs (PAVE query for active jobs list)
        → Call Claude API (HTTP POST to api.anthropic.com with transcript + job list)
        → Parse Claude Response (extract structured time entries)
        → Confidence Check (IF/Switch by confidence level)
        → Loop Time Entries (SplitInBatches)
          → Create Time Entry (PAVE createTimeEntry per entry)
        → Create Daily Log (PAVE createDailyLog)
        → Archive to Postgres (INSERT into daily_logs)
        → Slack notification (success or low-confidence)
        → Respond Success
```

**Expected Payload:**
```json
{
  "transcript": "Worked on the test bathroom today. About 3 hours of tile work...",
  "date": "2026-03-26",
  "source": "granola"
}
```

---

## Phase 2: Issues Identified (Static Analysis)

### work_estimate_router (#08b) — 3 Issues

**Issue 1: PostgREST dependency may not exist**
- Archive node sends `HTTP POST` to `$env.POSTGRES_REST_URL || 'http://127.0.0.1:3001'` + `/estimates`
- PostgREST is NOT configured in `sys.nix` environment variables (only ESTIMATOR_API_KEY, JOBTREAD_GRANT_KEY, SLACK_WEBHOOK_URL, ANTHROPIC_API_KEY are injected)
- The `POSTGRES_REST_URL` env var is never set → falls back to `http://127.0.0.1:3001`
- **Question:** Is PostgREST actually deployed and listening on port 3001? If not, every Postgres archive silently fails (continueOnFail=true masks the error).

**Issue 2: No duplicate prevention**
- Registry explicitly calls this out: "CRITICAL GAP: The registry spec calls for Postgres pre-check for duplicate push but no such node exists"
- Accidental re-pushes create duplicate budget line items in JT with no bulk-delete capability

**Issue 3: PAVE addBudgetLineItems may expect different field names**
- The JSON body uses `$json.jtPayload` directly in the PAVE query
- The PAVE `addBudgetLineItems` mutation expects specific field names (`costCodeId`, `costTypeId`, `unitId`, `quantity`, `unitCost`, `unitPrice`)
- If the React app sends different names (e.g., `cost_code_id` vs `costCodeId`), the mutation silently fails

---

### work_calculator_lead (#09) — 4 Issues

**Issue 1: MCP server dependency (LIKELY ROOT CAUSE of 90% error rate)**
- All 6 JT calls go to `http://localhost:6100/call` (Heartwood MCP server)
- The MCP server must be running and accessible from inside the n8n container
- n8n runs with `networkMode = "host"` so localhost:6100 should work **if** the MCP server is running
- **If the MCP server was deployed after March 24 or was down during those 10 test runs, this explains the 90% error rate**

**Issue 2: No authentication on webhook**
- Unlike #08b which checks `x-api-key`, this webhook has NO authentication
- It's designed for public website submissions, but without rate limiting or CAPTCHA, it's open to spam
- This is by design but worth noting

**Issue 3: Error handling is sequential with no continueOnFail**
- If any JT call fails (e.g., Create Account), the entire chain breaks
- No error nodes to catch and report failures — the webhook just times out
- The registry notes "9 of 10 executions failed" — likely cascading failures from one broken JT call

**Issue 4: Location is hardcoded to "Bozeman, MT"**
- `JT: Create Location` always creates a location with `name: 'Bozeman, MT', city: 'Bozeman', state: 'MT', zip: '59715'`
- No location data from the form is used — this is a reasonable default but noted

---

### work_lead_response (#10) — 0 Critical Issues

- **Working correctly** — 0% error rate, 5+ recent successful runs
- Uses Claude API for lead analysis (Anthropic API key is configured in sys.nix)
- Uses ntfy for push notifications (self-hosted, Tailscale-protected)
- Has companion `work_sms_handler` for inbound SMS
- **Minor:** Git merge conflict marker at line 456 of workflows/README.md in the lead response section

---

### work_voice_log (#12) — 3 Issues

**Issue 1: Claude API connectivity from container**
- Calls Anthropic API directly from n8n container
- `ANTHROPIC_API_KEY` IS configured in sys.nix (good)
- But the container needs outbound HTTPS access to `api.anthropic.com` — should work with host networking

**Issue 2: PAVE query for active jobs may be wrong**
- Node 5 "Fetch Active Jobs" queries PAVE to get the list of active jobs
- This is the same pattern that failed in #08a (wrong PAVE path `job` instead of `account.jobs`)
- Without seeing the actual PAVE query, this is a high-probability failure point

**Issue 3: Only 1 execution ever attempted**
- 1 total execution, 0 success, 1 error
- Need to check execution logs on the live server to see exactly which node failed
- Given the complexity (Claude API → parse → loop → multiple PAVE writes), many failure points

---

## Phase 3: Caddy/Networking Verification

**Webhook routing is correctly configured:**
```nix
# domains/networking/routes.nix:333-342
{
  name = "webhook";
  mode = "subpath";
  path = "/webhook";
  upstream = "http://127.0.0.1:5678";
  needsUrlBase = true;  # Preserves /webhook prefix for n8n routing
}
```

**n8n webhook configuration:**
```
N8N_ENDPOINT_WEBHOOK = "webhook"
WEBHOOK_URL = "https://hwc.ocelot-wahoo.ts.net:10000/"
```

**Access paths:**
- Internal (from host): `http://127.0.0.1:5678/webhook/{path}`
- Via Caddy (Tailscale): `https://hwc.ocelot-wahoo.ts.net/webhook/{path}`
- Via Tailscale Funnel (public): `https://hwc.ocelot-wahoo.ts.net:10000/webhook/{path}`

**Reverse proxy also allows:**
- `/webhook/*` through the public MCP gateway on `:10080`

---

## Phase 4: Environment Variables

Secrets injected into n8n container via `/run/n8n/secrets.env`:

| Variable | Source | Used By |
|----------|--------|---------|
| `ESTIMATOR_API_KEY` | agenix | #08b (auth) |
| `JOBTREAD_GRANT_KEY` | agenix | #08b (PAVE calls) |
| `SLACK_WEBHOOK_URL` | agenix | #08b, #09, #10, #12 |
| `ANTHROPIC_API_KEY` | agenix | #10, #12 (Claude API) |

**NOT configured but expected:**
| Variable | Expected By | Impact |
|----------|-------------|--------|
| `POSTGRES_REST_URL` | #08b | Falls back to `http://127.0.0.1:3001` — may not exist |

---

## Phase 5: Test Commands (For Live Execution on HWC Server)

These commands should be run **from the HWC server** (not this VM):

### Test #08b — Estimate Router
```bash
N8N_KEY=$(sudo cat /run/agenix/n8n-api-key)
ESTIMATOR_KEY=$(sudo cat /run/agenix/estimator-api-key)

curl -v -X POST http://127.0.0.1:5678/webhook/estimate-push \
  -H "Content-Type: application/json" \
  -H "x-api-key: $ESTIMATOR_KEY" \
  -d '{
    "action": "push_estimate",
    "mode": "existing",
    "jobId": "REPLACE_WITH_TEST_JOB_ID",
    "jobNumber": "281",
    "jobName": "Master Bathrooms",
    "customerId": "REPLACE_WITH_CUSTOMER_ID",
    "customerName": "Test Customer",
    "projectType": "bathroom",
    "projectState": {"room": "master_bath"},
    "jtPayload": [],
    "totals": {"cost": 0, "price": 0, "items": 0, "laborHrs": 0, "margin": 0},
    "timestamp": "2026-03-27T00:00:00Z"
  }'
```
**Note:** Send with empty `jtPayload` first to test auth + validation without creating JT records.

### Test #09 — Calculator Lead
```bash
curl -v -X POST http://127.0.0.1:5678/webhook/calculator-lead \
  -H "Content-Type: application/json" \
  -d '{
    "contact": {"name": "Night3 Test Lead", "phone": "406-555-0199", "email": "test@example.com", "notes": "Night 3 automated test - not a real lead"},
    "projectState": {"project_type": "full_gut", "bathroom_size": "medium", "shower_tub": "shower_only", "tile_level": "mid", "fixtures": "upgraded", "features": ["heated_floor"], "timeline": "just_exploring"},
    "estimate": {"low": 22000, "high": 32000},
    "source": "website_calculator"
  }'
```
**WARNING:** This creates real JT customer/contact/location/job records. Note all IDs returned for cleanup.

### Test #12 — Voice Log
```bash
curl -v -X POST http://127.0.0.1:5678/webhook/daily-log \
  -H "Content-Type: application/json" \
  -d '{
    "transcript": "Test voice log. Worked on the master bathroom today. About 2 hours of tile work on the shower walls. Used half a bag of thinset.",
    "date": "2026-03-27",
    "source": "granola"
  }'
```

### Test #10 — Lead Response
```bash
curl -v -X POST http://127.0.0.1:5678/webhook/new-lead \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Night3 Test",
    "phone": "4065550199",
    "service_type": "bathroom remodel",
    "source": "test"
  }'
```
**WARNING:** This may trigger SMS via Twilio if configured. The phone 406-555-0199 is a fictitious 555 number that should fail gracefully.

---

## Phase 6: Recommended Fix Priority

### Priority 1 (Business-blocking)

1. **Verify MCP server is running for #09** — Check `systemctl status` or `podman ps` for the Heartwood MCP server on port 6100. If it's not running, the calculator lead workflow is completely broken. This likely explains 90% of #09's failures.

2. **Check PostgREST for #08b** — Verify something is listening on port 3001. If not, deploy PostgREST or switch #08b's Postgres archive to use the native Postgres node (like #09 does) instead of HTTP/PostgREST.

3. **Debug #12 voice log single failure** — Run `wget` from inside the n8n container to check the execution log:
   ```bash
   sudo podman exec n8n sh -c "wget -q -O - \
     --header='X-N8N-API-KEY: $N8N_KEY' \
     'http://localhost:5678/api/v1/executions?workflowId=XAm7ehKjJers5NqC&limit=5'"
   ```

### Priority 2 (Data integrity)

4. **Add duplicate prevention to #08b** — Pre-check Postgres before pushing budget items to JT. Without this, accidental re-pushes create duplicate line items with no bulk-delete.

5. **Add error handling to #09** — Add `continueOnFail` and error notification nodes so failures are reported instead of silently timing out.

6. **Add duplicate customer check to #09** — Search JT by name/phone before creating new accounts.

### Priority 3 (Cleanup)

7. **Fix merge conflict in workflows/README.md** — Line 456 has a `<<<<<<< HEAD` marker with no closing markers.

8. **Export #10 and #12 to git** — These workflow JSONs only exist in the n8n database. Export them to `domains/automation/n8n/parts/workflows/` for version control.

9. **Set `POSTGRES_REST_URL` env var** — Either add to `sys.nix` secrets or remove the PostgREST dependency from #08b.

---

## Architecture Notes

### Two JT Integration Patterns in Use

| Pattern | Used By | Endpoint | Pros | Cons |
|---------|---------|----------|------|------|
| Raw PAVE GraphQL | #08b, #12 | `https://api.jobtread.com/pave` | Direct, no middleware | Verbose, error-prone |
| MCP Server `/call` | #09 | `http://localhost:6100/call` | Abstracted, cleaner | Extra dependency |

The registry documents a migration path from PAVE to MCP. #09 is the first workflow to use MCP. The others still use raw PAVE.

### n8n Container Networking

- Host networking mode (`networkMode = "host"`) — all localhost services are directly accessible
- This means `localhost:6100` (MCP), `localhost:5678` (self), `127.0.0.1:3001` (PostgREST?) should all work
- Outbound HTTPS works for `api.jobtread.com`, `api.anthropic.com`, Slack webhooks

---

## JT Test Record IDs

No test records were created (no live access). When running tests on the server, record:

- [ ] #08b: Budget line item IDs pushed to job #281
- [ ] #09: JT account ID, contact ID, location ID, job ID created
- [ ] #12: Time entry IDs, daily log ID created
- [ ] #10: Lead log entry in Postgres

---

## Deliverable Checklist

- [x] All 4 workflow structures documented (trigger, nodes, expected payloads)
- [ ] Each workflow tested with representative payload (BLOCKED: no server access from VM)
- [x] Issues documented per workflow (from static analysis)
- [ ] JT test record IDs noted (BLOCKED: no live tests)
- [x] Test report written
- [x] Recommended fix list prioritized by business impact
- [x] Test commands prepared for live execution on HWC server

---

*Generated by Claude Code — Night 3 session on branch claude/test-n8n-workflows-pVtr8*
