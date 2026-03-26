# n8n Workflow Definitions

This directory contains production-ready n8n workflow JSON files that can be imported directly into the n8n UI.

## Workflows

### 01-media-pipeline-orchestration.json
**Purpose:** Automate download-to-library pipeline with post-processing and notifications

**Trigger:** Webhook `/webhook/media-pipeline?source={radarr|sonarr|lidarr}`

**Features:**
- Handles downloads from Radarr (movies), Sonarr (TV), Lidarr (music)
- 30-second file settlement delay
- Triggers Jellyfin library refresh for movies/TV
- Calls Script Executor for Beets music import
- Sends success notifications to ntfy (hwc-media, P2)
- Sends failure notifications to ntfy + Slack (hwc-alerts, P4)

**Service Configuration Required:**
- Radarr: Settings → Connect → Webhook
- Sonarr: Settings → Connect → Webhook
- Lidarr: Settings → Connect → Webhook

---

### 02-frigate-surveillance-intelligence.json
**Purpose:** Smart filtering and contextual routing of camera detection events

**Trigger:** Webhook `/webhook/frigate-events`

**Features:**
- Parses Frigate camera events (person, car, animal detection)
- Smart priority assignment:
  - P5 (Critical): Person/car at night (10pm-6am)
  - P4 (High): Person during daytime
  - P2 (Info): Animals, packages, bicycles
- Filters low-confidence detections (<60%)
- Fetches high-resolution snapshots
- Routes notifications by priority (ntfy + Slack for P5)

**Service Configuration Required:**
- Edit `/home/eric/.nixos/domains/server/frigate/config/config.yml` to add webhook URL

---

### 03-system-monitoring-alertmanager-router.json
**Purpose:** Central alert processing with enrichment and smart routing

**Trigger:** Webhook `/webhook/alertmanager` (already configured)

**Features:**
- Receives alerts from Prometheus Alertmanager
- Parses and deduplicates alerts (1-hour window)
- Branches by category (system/service/container) for enrichment
- Queries Prometheus, systemctl, or podman inspect for context
- Generates rich notifications with remediation suggestions
- Routes by severity: P5 → Slack + ntfy, P4 → ntfy, P3 → ntfy

**Service Configuration:** Already configured in Alertmanager

---

### 04-ai-ml-service-orchestration.json
**Purpose:** Coordinate Immich photo processing, Ollama enrichment, and scheduled AI tasks

**Triggers:**
- Webhook `/webhook/immich-upload` (Immich photo events)
- Webhook `/webhook/ai-enrich` (AI enrichment requests from other workflows)
- Schedule: Daily 2am (face clustering)
- Schedule: Weekly Sunday 3am (duplicate detection)
- Schedule: Monthly 1st 4am (statistics report)

**Features:**
- Polls Immich API until ML processing completes
- Extracts metadata (faces, objects, location)
- Skips notification if no interesting content (noise reduction)
- Provides AI enrichment endpoint for other workflows via Ollama
- Triggers scheduled Immich maintenance jobs
- Sends notifications to ntfy (hwc-ai, P1-P2)

---

### 05-cross-service-health-monitor.json
**Purpose:** Proactive health monitoring with automated remediation

**Trigger:** Schedule every 5 minutes

**Features:**
- Health checks for: Jellyfin, Immich, Frigate, ntfy, n8n, Prometheus, Alertmanager
- Systemd checks for: Caddy, Tailscale
- Parallel execution of all checks
- Automatic remediation attempts (service restart via Script Executor)
- **Critical service protection:** Never auto-restarts caddy, sshd, tailscaled
- Detects restart loops (>3 restarts in 10 minutes)
- Smart notifications:
  - Auto-fix successful: ntfy (hwc-monitoring, P3)
  - Auto-fix failed: ntfy + Slack (hwc-alerts, P4)
  - Manual intervention needed: ntfy + Slack (hwc-critical, P5)

---

### 06-universal-script-executor.json
**Purpose:** Secure webhook-triggered script execution for maintenance, media processing, and automation

**Trigger:** Webhook `/webhook/script-executor`

**Request Schema:**
```json
{
  "script_name": "beets-import",
  "args": ["/mnt/hot/music/new-album"],
  "async": true,
  "callback_url": "https://hwc.ocelot-wahoo.ts.net:2443/webhook/callback",
  "requester": "workflow-1"
}
```

**Features:**
- **Whitelist enforcement:** Only allows predefined scripts
- **Argument sanitization:** Removes dangerous shell characters
- **Audit logging:** All executions logged with requester
- **Sync/async execution:** Supports both immediate and background execution
- **Callback support:** Notifies caller when async execution completes
- **Security violations:** Triggers P5 alert + Slack for unauthorized requests

**Whitelisted Scripts:**
- System: nix-collect-garbage, service-restart, backup-now
- Media: beets-import, jellyfin-scan, media-organize, music-dedup
- NixOS: flake-update, charter-check, build-doctor
- Claude Skills: system-checkup, secret-provision, add-container, beets-organize

**Security:**
- Cannot execute arbitrary commands
- Critical service protection (caddy, sshd, tailscaled)
- All executions audited
- Security violations trigger immediate P5 alerts

---

### 07-transcript-orchestrator.json
**Purpose:** Unified YouTube transcript extraction and formatting with Ollama/Qwen integration

**Triggers:**
- Webhook `/webhook/transcript-extract` (YouTube URL submission)
- Webhook `/webhook/transcript-format` (Manual formatting requests)

**Request Schema (Extraction):**
```json
{
  "url": "https://youtube.com/watch?v=dQw4w9WgXcQ",
  "format": "standard",
  "auto_format": true,
  "languages": "en,en-US"
}
```

**Request Schema (Formatting):**
```json
{
  "file_path": "/mnt/media/transcripts/video.md",
  "format_mode": "llm",
  "vault_dir": "/home/eric/01-documents/01-vaults/04-transcripts"
}
```

**Features:**
- **Extraction Pipeline:**
  - Async YouTube transcript extraction
  - Returns job_id immediately for status tracking
  - Retry logic: 3 attempts with exponential backoff (5s, 10s, 20s)
  - Handles network timeouts, rate limits, temporary failures
  - Dead letter queue for failed jobs
  - Auto-triggers formatting on successful extraction

- **Formatting Pipeline:**
  - LLM-based formatting via Ollama/Qwen 2.5:7b
  - Retry logic: 2 attempts with 30-second backoff
  - Fallback to basic cleaning if LLM fails
  - Saves formatted transcripts to Obsidian vault
  - Optional CouchDB sync support

- **Error Handling:**
  - Dead letter queue: `/home/eric/.cache/n8n/transcript-dlq.jsonl`
  - Smart notifications:
    - P2 (Success): Extraction/formatting completed → ntfy (hwc-transcripts)
    - P4 (Failure): All retries exhausted → ntfy + Slack (hwc-transcripts)

**Wrapper Scripts:**
- `/home/eric/.local/bin/n8n-transcript-extract` - YouTube extraction wrapper
- `/home/eric/.local/bin/n8n-transcript-format` - Formatting wrapper (basic/LLM modes)

**Service Configuration:** None required (uses existing Python scripts)

**Test Commands:**
```bash
# Extract YouTube transcript
curl -X POST https://hwc.ocelot-wahoo.ts.net:2443/webhook/transcript-extract \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://youtube.com/watch?v=dQw4w9WgXcQ",
    "auto_format": true
  }'

# Format existing file
curl -X POST https://hwc.ocelot-wahoo.ts.net:2443/webhook/transcript-format \
  -H "Content-Type: application/json" \
  -d '{
    "file_path": "/mnt/media/transcripts/video.md",
    "format_mode": "llm"
  }'
```

**Coexistence:** Runs alongside existing systemd services (`transcript-api`, `transcript-formatter`) during transition period.

---

### 08a-jt-data-provider.json
**Purpose:** Provide JobTread customer and job data for the Heartwood Estimator app dropdowns

**Triggers:**
- Webhook `GET /webhook/jt-customers` (Fetch all customers)
- Webhook `GET /webhook/jt-jobs?customerId={id}` (Fetch jobs for customer)

**Features:**
- API key authentication via `x-api-key` header
- GraphQL queries to JobTread API
- Filters jobs by Phase custom field (1-3 = estimating stages)
- Returns formatted dropdown data with IDs, names, addresses

**Request Headers:**
```
x-api-key: {ESTIMATOR_API_KEY}
```

**Response (Customers):**
```json
{
  "customers": [
    { "id": "uuid", "name": "John Smith", "address": "123 Main St, City, ST 12345" }
  ],
  "count": 42
}
```

**Response (Jobs):**
```json
{
  "jobs": [
    { "id": "uuid", "number": "281", "name": "Smith Bathroom", "displayName": "#281 - Smith Bathroom" }
  ],
  "count": 5
}
```

**Credentials Required:**
- `ESTIMATOR_API_KEY`: Shared secret for webhook authentication
- JobTread API credential (Bearer token)

---

### 08b-estimate-router.json (work_estimate_router)
**Purpose:** Route estimates from Heartwood Estimator to JobTread, Postgres archive, and Slack notifications

**Trigger:** Webhook `POST /webhook/estimate-push`

**Request Headers:**
```
Content-Type: application/json
x-api-key: {ESTIMATOR_API_KEY}
```

**Request Schema:**
```json
{
  "action": "push_estimate",
  "mode": "existing",
  "projectType": "bathroom",
  "jobId": "uuid",
  "jobNumber": "281",
  "jobName": "Smith Bathroom",
  "customerId": "uuid",
  "customerName": "John Smith",
  "newJob": null,
  "projectState": { },
  "jtPayload": [ ],
  "totals": {
    "cost": 15000,
    "price": 22500,
    "items": 47,
    "laborHrs": 120,
    "margin": 33.3
  },
  "timestamp": "2026-03-19T..."
}
```

**Features:**
- API key authentication
- Creates new JobTread job if `mode: "new_job"`
- Pushes budget line items to JobTread via GraphQL
- Archives estimate to Postgres (always, even on JT failure)
- Notifies Slack with job link and totals
- Returns detailed result with success/failure status

**Response:**
```json
{
  "success": true,
  "jtPushSuccess": true,
  "jtPushError": null,
  "jobId": "uuid",
  "jobNumber": "281",
  "jobCreated": false,
  "itemsPushed": 47,
  "archived": true,
  "requestId": "est-1710859200000-abc123"
}
```

**Postgres Schema:** See `/home/eric/.nixos/domains/automation/n8n/parts/migrations/001-estimates-table.sql`

**Slack Message Format:**
- Success: Job link, customer, type, items, labor, total with margin
- Failure: Warning with error details, note that estimate is archived

**Credentials Required:**
- `ESTIMATOR_API_KEY`: Shared secret for webhook authentication
- `SLACK_WEBHOOK_URL`: Slack incoming webhook for #hwc-estimates
- `POSTGRES_REST_URL`: PostgREST endpoint for estimates table
- JobTread API credential (Bearer token)

**Test Command:**
```bash
curl -X POST https://hwc.ocelot-wahoo.ts.net:2443/webhook/estimate-push \
  -H "Content-Type: application/json" \
  -H "x-api-key: {secret}" \
  -d '{
    "action": "push_estimate",
    "mode": "existing",
    "jobId": "22XXX...",
    "jobNumber": "281",
    "jobName": "Test Job",
    "customerId": "22YYY...",
    "customerName": "Test Customer",
    "projectType": "bathroom",
    "projectState": {},
    "jtPayload": [],
    "totals": { "cost": 1000, "price": 1500, "items": 10, "laborHrs": 8, "margin": 33.3 }
  }'
```

---

### 10-calculator-lead.json (work_calculator_lead)
**Purpose:** Process bathroom remodel calculator submissions, create full JobTread customer/job records, archive to Postgres, and notify via Slack

**Workflow ID:** `SoLwmxgkMILrOYbP`

**Trigger:** Webhook `POST /webhook/calculator-lead`

**Architecture:** Calls the Heartwood MCP server's `/call` REST endpoint (http://localhost:6100/call)
instead of raw PAVE GraphQL — all JT translation is encapsulated in the MCP layer.

**Pipeline:**
```
Webhook → Extract Lead (validate) → JT: Create Account → JT: Update Account (custom fields)
        → JT: Create Contact → JT: Create Location → JT: Create Job
        → Prepare DB Record → Postgres: Archive Lead → Slack: Notify Eric → Respond 200
```

**Request Schema:**
```json
{
  "contact": {
    "name": "John Smith",
    "email": "john@example.com",
    "phone": "406-555-1234"
  },
  "projectState": {
    "project_type": "bathroom",
    "bathroom_size": "medium",
    "shower_tub": "shower_only",
    "tile_level": "standard",
    "fixtures": "mid_range",
    "features": ["heated_floors", "niche"],
    "timeline": "3-6 months"
  },
  "estimate": {
    "low": 18000,
    "high": 28000
  }
}
```

**Features:**
- **Validation:** Requires name and phone; returns 400 error if missing
- **JobTread Integration (via Heartwood MCP /call):**
  - Creates customer Account with type `customer`
  - Sets Account custom fields (Lead Source: Website, Project Type: Bathroom Remodel)
  - Creates Contact linked to Account
  - Sets Contact custom fields (Email, Phone) via field IDs
  - Creates Location (defaults to Bozeman, MT)
  - Creates Job linked to Location
  - Sets Job custom fields (Job Type: Bathroom, Phase: 1. Contacted)
- **Postgres Archive:** Inserts lead data to `hwc.calculator_leads` table (see migration `002-calculator-leads.sql`)
- **Slack Notification:** Posts to #leads with estimate range, project details
- **Response:** Returns success with JT account/job IDs

**JT Custom Fields set on Account:**
- `22PUGvBnXeYs` (Lead Source) = `website_calculator`
- `22Nnj9KwwePZ` (Status)      = `lead_new`
- `22Nnj9KMKEPC` (Project Type)= `Bathroom`

**Response Schema:**
```json
{
  "success": true,
  "jt_account_id": "22PULhFgPZxa",
  "jt_job_id": "22PULhFmkQY2"
}
```

**PAVE API Pattern (Critical):**
- `createAccount`, `createContact`, `createJob` do NOT accept `customFields` or `customFieldValues`
- Must use two-step pattern: create entity → immediately update with `customFieldValues`
- Custom field values use field IDs (e.g., `22Nm3uGRBrPX` for Email), not field names
- See `/home/eric/600_shared/api/jobtread_api_reference.md` for full field ID reference

**Credentials Required:**
- `JOBTREAD_GRANT_KEY`: JobTread API grant key (via n8n environment)
- `HWC Postgres`: PostgreSQL credential with access to `hwc` schema
- `Slack account 2`: OAuth2 Slack credential

**Test Command:**
```bash
curl -X POST https://hwc.ocelot-wahoo.ts.net:2443/webhook/calculator-lead \
  -H "Content-Type: application/json" \
  -d '{
    "contact": {"name": "Test Lead", "email": "test@example.com", "phone": "406-555-1234"},
    "projectState": {"project_type": "bathroom", "bathroom_size": "medium"},
    "estimate": {"low": 15000, "high": 25000}
  }'
```

---

### 09-lead-response.json (work_lead_response)
**Purpose:** Automated lead response workflow with push notifications via self-hosted ntfy

**Trigger:** Webhook `POST /webhook/new-lead`

**Request Schema:**
```json
{
<<<<<<< HEAD
  "name": "John Smith",
  "phone": "4065551234",
  "email": "john@example.com",
  "service_type": "bathroom remodel",
  "source": "website"
}
```

**Features:**
- Phone validation and E.164 normalization
- Business hours detection (7am-7pm Mon-Sat, Mountain Time)
- Immediate notification during business hours
- Scheduled notification at 8am next business day for after-hours leads
- 2-hour follow-up reminder if no response
- Push notifications via **self-hosted ntfy** (`https://hwc.ocelot-wahoo.ts.net/notify/hwc-leads`)
- Slack notifications to #leads channel
- Postgres logging for all leads and errors

**Notification Flow:**
1. New lead received → Validate phone → Save to Postgres
2. During business hours: Immediate ntfy push + Slack
3. After hours: Wait until 8am → ntfy push + Slack
4. 2 hours later: Check for response → Follow-up ntfy if no response

**ntfy Topics:**
- `hwc-leads` - All lead notifications (private, Tailscale only)

**ntfy Node Configuration:**
```
- Method: POST
- URL: https://hwc.ocelot-wahoo.ts.net/notify/hwc-leads
- Body Type: raw (NOT "string")
- Headers: Content-Type: text/plain, Title, Priority, Tags
```

**Test Command:**
```bash
curl -X POST https://hwc.ocelot-wahoo.ts.net:2443/webhook/new-lead \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Lead",
    "phone": "4065551234",
    "service_type": "kitchen remodel",
    "source": "website"
  }'
```

**Phone Subscription:** Subscribe to `hwc-leads` on `https://hwc.ocelot-wahoo.ts.net/notify` in ntfy app

---

## Import Instructions

1. Access n8n: `https://hwc.ocelot-wahoo.ts.net:2443`
2. Click "Add workflow" → "Import from File"
3. Select workflow JSON file from this directory
4. Activate workflow after import
5. Configure credentials (see main implementation guide)
6. Test with curl commands

## Credentials Required

Configure these in n8n UI (Settings → Credentials):

- `JELLYFIN_API_KEY`: From Jellyfin dashboard or `/run/secrets/jellyfin-api-key`
- `IMMICH_API_KEY`: From Immich settings
- `SLACK_WEBHOOK_URL`: From `/run/secrets/slack-webhook-url`
- `ESTIMATOR_API_KEY`: Shared secret for estimator webhook authentication
- `POSTGRES_REST_URL`: PostgREST endpoint (e.g., `http://127.0.0.1:3001`)
- JobTread API Bearer token (configured as HTTP Header Auth credential)

Credentials are accessed via environment variables in workflows:
- `{{ $env.JELLYFIN_API_KEY }}`
- `{{ $env.IMMICH_API_KEY }}`
- `{{ $env.SLACK_WEBHOOK_URL }}`

## Testing

See the main implementation guide for curl test commands for each workflow.

## Maintenance

**Version Control:** These JSON files are tracked in git for version control and reproducibility.

**Backup:** Regular exports recommended via n8n UI → Settings → Export

**Updates:** Edit workflows in n8n UI, then export back to this directory to keep in sync.

---

## Related Documentation

- **Full Implementation Guide:** `/home/eric/.nixos/docs/automation/n8n-workflows-implementation-guide.md`
- **Master Plan:** `/home/eric/.claude/plans/cozy-pondering-fog.md`
- **n8n Module:** `/home/eric/.nixos/domains/server/n8n/index.nix`
- **Script Wrappers:** `/home/eric/.local/bin/`

---

**Last Updated:** 2026-03-24
**Author:** Eric (with Claude assistance)
