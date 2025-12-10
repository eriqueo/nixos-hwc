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

**Last Updated:** 2025-12-10
**Author:** Eric (with Claude assistance)
