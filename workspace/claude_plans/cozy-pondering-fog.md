# n8n Workflow Automation Plan - hwc-server

## Overview

Design and implement 6 comprehensive n8n workflows for hwc-server that automate media management, surveillance monitoring, system alerting, AI/ML orchestration, health monitoring, and script execution via webhooks. All workflows integrate with existing ntfy and Slack notification systems using smart routing based on priority.

## Infrastructure Context

**Existing Services:**
- Media: Radarr, Sonarr, Lidarr, Jellyfin, Navidrome, Beets, qBittorrent, SABnzbd
- Surveillance: Frigate (3 cameras with NVIDIA GPU object detection)
- Monitoring: Prometheus, Alertmanager, Grafana
- AI/ML: Immich (photo management), Ollama (local LLM)
- Notifications: ntfy (working), Slack (needs webhook URL)
- Automation: n8n (port 5678 localhost, exposed via Caddy on port 2443)

**n8n Access:** `https://hwc.ocelot-wahoo.ts.net:2443` (Tailscale-only, no auth required)

---

## Workflow 1: Media Pipeline Orchestration

**Purpose:** Automate download-to-library pipeline with post-processing and notifications

**Trigger:** Webhook `/webhook/media-pipeline?source={radarr|sonarr|lidarr}`

**Flow:**
1. Parse download event (title, quality, path, media type)
2. Wait 30s for filesystem settlement
3. Branch by media type:
   - **Movies**: Trigger Jellyfin library refresh, verify indexing
   - **TV Shows**: Check season completion, trigger Jellyfin refresh
   - **Music**: Call Script Executor for Beets import, trigger Navidrome scan
4. Verify content appears in media server (poll with retries)
5. Generate rich notification with emoji, quality, path
6. Send to ntfy (hwc-media, P2) on success
7. Send to ntfy (hwc-alerts, P4) + Slack on failure

**Notifications:**
- Success: ntfy only (hwc-media, P2)
- Failure: ntfy + Slack (hwc-alerts, P4)

**Service Configuration Required:**
- Radarr: Settings → Connect → Webhook → `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr`
- Sonarr: Settings → Connect → Webhook → `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=sonarr`
- Lidarr: Settings → Connect → Webhook → `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=lidarr`

---

## Workflow 2: Frigate Surveillance Intelligence

**Purpose:** Smart filtering and contextual routing of camera detection events

**Trigger:** Webhook `/webhook/frigate-events`

**Flow:**
1. Parse Frigate event (camera, object, score, time)
2. Apply smart filters:
   - **P5 Critical**: Person at night (10pm-6am) OR car in driveway at night
   - **P4 High**: Person detected daytime
   - **P2 Info**: Animals, packages, bicycles
   - **Drop**: Known false positives (plants, low confidence)
3. Deduplicate (5-minute window per camera+object)
4. Fetch high-res snapshot from Frigate API
5. Query camera health from Prometheus (FPS metrics)
6. Generate context-aware notification with:
   - Friendly camera names (Front Door, Driveway, Backyard)
   - Confidence percentage
   - Camera health status
   - Link to recording
7. Route by priority:
   - **P5**: Slack + ntfy (hwc-critical)
   - **P4**: ntfy (hwc-alerts)
   - **P2**: ntfy (hwc-monitoring)

**Notifications:**
- Critical (person/car at night): Slack + ntfy (hwc-critical, P5)
- High priority (person daytime): ntfy (hwc-alerts, P4)
- Info (animals/packages): ntfy (hwc-monitoring, P2)

**Service Configuration Required:**
- Edit `/home/eric/.nixos/domains/server/frigate/config/config.yml`:
  ```yaml
  notifications:
    webhook:
      url: "https://hwc.ocelot-wahoo.ts.net:2443/webhook/frigate-events"
      enabled: true
  ```

---

## Workflow 3: System Monitoring & Alertmanager Router

**Purpose:** Central alert processing with enrichment and smart routing

**Trigger:** Webhook `/webhook/alertmanager` (already configured)

**Flow:**
1. Parse Alertmanager alerts (name, severity, labels, annotations)
2. Deduplicate (1-hour window per alert+instance)
3. Branch by category for enrichment:
   - **System alerts**: Query Prometheus for current metrics + trends
   - **Service alerts**: Execute `systemctl status` for details
   - **Container alerts**: Execute `podman inspect` for state
   - **Frigate alerts**: Query Frigate API for camera status
4. Merge enriched data with original alert
5. Generate rich notification with:
   - Severity emoji (🔴/⚠️/ℹ️)
   - Alert summary and description
   - Current status from enrichment
   - Link to Grafana dashboard
   - Suggested remediation action
6. Route by severity:
   - **P5**: Slack + ntfy (hwc-critical)
   - **P4**: ntfy (hwc-alerts)
   - **P3**: ntfy (hwc-monitoring)

**Notifications:**
- Critical alerts: Slack + ntfy (hwc-critical, P5)
- Warnings: ntfy (hwc-alerts, P4)
- Info: ntfy (hwc-monitoring, P3)

**Service Configuration:** Already configured in Alertmanager

---

## Workflow 4: AI/ML Service Orchestration

**Purpose:** Coordinate Immich photo processing, Ollama enrichment, and scheduled AI tasks

**Triggers:**
- Webhook `/webhook/immich-upload` (Immich photo events)
- Webhook `/webhook/ai-enrich` (called by other workflows for AI summaries)
- Schedule: Daily 2am (face clustering), Weekly Sunday 3am (duplicate detection), Monthly 1st 4am (stats report)

**Flow A - Photo Processing:**
1. Parse Immich upload event
2. Poll Immich API until ML processing complete (max 2 minutes)
3. Extract metadata (faces, objects, location)
4. Skip notification if no interesting content (reduce noise)
5. Generate rich notification for photos with faces/objects
6. Send to ntfy (hwc-ai, P2)

**Flow B - AI Enrichment (called by other workflows):**
1. Parse enrichment request (context, task, model)
2. Call Ollama API with prompt
3. Parse and return AI-generated summary
4. Respond to webhook caller with enriched text

**Flow C - Scheduled Tasks:**
1. Branch by schedule:
   - Daily: Trigger face re-clustering job
   - Weekly: Trigger duplicate detection job
   - Monthly: Generate statistics report
2. Query job status
3. Generate completion notification
4. Send to ntfy (hwc-ai, P1-P2)

**Notifications:**
- Photo with faces: ntfy (hwc-ai, P2)
- AI enrichment: Return via webhook (no notification)
- Scheduled job complete: ntfy (hwc-ai, P1)
- Job failed: ntfy (hwc-alerts, P4)

---

## Workflow 5: Cross-Service Health Monitor

**Purpose:** Proactive health monitoring with automated remediation

**Trigger:** Schedule every 5 minutes

**Flow:**
1. Define health checks:
   - HTTP endpoints: Jellyfin, Immich, Frigate, ntfy, n8n
   - systemd services: Caddy
   - Prometheus scrape targets: prometheus, alertmanager
2. Execute all checks in parallel
3. Aggregate results
4. For each failure:
   - Attempt auto-remediation:
     - HTTP service down: Call Script Executor to restart
     - Container failed: Execute `podman restart`
     - systemd service: Execute `systemctl restart`
   - **NEVER auto-restart critical services**: caddy, sshd, tailscaled
   - Wait and verify fix
5. Check container health for restart loops (>3 restarts in 10 minutes)
6. Generate notifications based on outcome:
   - Auto-fix successful: ntfy (hwc-monitoring, P3)
   - Auto-fix failed: ntfy + Slack (hwc-alerts, P4)
   - No auto-fix available: ntfy + Slack (hwc-critical, P5)
7. Store health history for trend analysis

**Notifications:**
- Auto-fix successful: ntfy (hwc-monitoring, P3)
- Auto-fix failed: ntfy + Slack (hwc-alerts, P4)
- Manual intervention needed: ntfy + Slack (hwc-critical, P5)

---

## Workflow 6: Universal Script Executor

**Purpose:** Secure webhook-triggered script execution for maintenance, media processing, NixOS ops, and Claude Code skills

**Trigger:** Webhook `/webhook/script-executor`

**Input Schema:**
```json
{
  "script_name": "beets-import",
  "args": ["/mnt/hot/music/new-album"],
  "async": true,
  "callback_url": "https://hwc.ocelot-wahoo.ts.net:2443/webhook/callback",
  "requester": "workflow-1"
}
```

**Flow:**
1. Parse request (script name, args, async flag, callback)
2. Validate script against whitelist (see allowed scripts below)
3. Sanitize arguments (remove shell metacharacters)
4. Log execution request to n8n DB (audit trail)
5. Branch: async or sync execution
   - **Sync**: Execute, wait for completion, return results immediately
   - **Async**: Start background process, return execution ID, poll status
6. Capture output (stdout, stderr, exit code)
7. Generate notification based on result
8. For async: Send callback webhook when complete
9. Update execution log

**Allowed Scripts:**
```javascript
// System Maintenance
"nix-collect-garbage": /run/current-system/sw/bin/nix-collect-garbage -d
"service-restart": systemctl restart <service>
"backup-now": /home/eric/.local/bin/trigger-backup

// Media Processing
"beets-import": /home/eric/.local/bin/n8n-beets-import <path>
"jellyfin-scan": /home/eric/.local/bin/n8n-jellyfin-scan
"media-organize": /home/eric/.local/bin/run-claude-skill media-file-manager
"music-dedup": /home/eric/.local/bin/run-claude-skill beets-music-organizer

// NixOS Operations
"flake-update": /home/eric/.local/bin/n8n-flake-update
"charter-check": /home/eric/.local/bin/run-claude-skill charter-check
"build-doctor": /home/eric/.local/bin/run-claude-skill nixos-build-doctor

// Claude Code Skills (via wrapper)
"skill-system-checkup": /home/eric/.local/bin/run-claude-skill system-checkup
"skill-secret-provision": /home/eric/.local/bin/run-claude-skill secret-provision
"skill-add-container": /home/eric/.local/bin/run-claude-skill add-server-container
"skill-beets-organize": /home/eric/.local/bin/run-claude-skill beets-music-organizer
"skill-media-organize": /home/eric/.local/bin/run-claude-skill media-file-manager
```

**Security:**
- Whitelist enforcement: Only predefined scripts allowed
- Argument sanitization: Remove dangerous characters
- Audit logging: All executions logged with requester
- No arbitrary commands: Cannot execute shell commands directly
- Critical service protection: Never restart caddy, sshd, tailscaled

**Notifications:**
- Script success: ntfy (hwc-updates, P1)
- Script failed: ntfy (hwc-alerts, P4)
- Timeout: ntfy (hwc-alerts, P4)
- Security violation: ntfy + Slack (hwc-critical, P5)

**Additional Endpoint:** `/webhook/script-status/:executionId` for checking async execution status

---

## Notification Routing Strategy

**Smart routing based on priority:**

| Priority | ntfy Topic | Slack | Use Case |
|----------|-----------|-------|----------|
| P5 (Critical) | hwc-critical | ✅ Yes | Security events, critical service failures, nighttime detections |
| P4 (Warning) | hwc-alerts | ❌ No | Service warnings, failed auto-fixes, script failures |
| P3 (Info) | hwc-monitoring or hwc-backups | ❌ No | Successful auto-fixes, backup completions |
| P2 (Low) | hwc-media or hwc-ai | ❌ No | Media imports, AI processing |
| P1 (Minimal) | hwc-updates | ❌ No | Script successes, scheduled tasks |

**ntfy API Format:**
```bash
POST https://hwc.ocelot-wahoo.ts.net/notify/<topic>
Headers:
  Title: <notification title>
  Tags: <comma-separated tags>
  Priority: <1-5>
Body: <notification message>
```

**Slack Webhook Format:**
```json
POST <slack_webhook_url>
Body: {
  "blocks": [
    {"type": "header", "text": {"type": "plain_text", "text": "<title>"}},
    {"type": "section", "text": {"type": "mrkdwn", "text": "<message>"}}
  ]
}
```

---

## Implementation Steps

### 1. Prerequisites

**Add Slack Webhook Secret:**
```nix
# /home/eric/.nixos/domains/secrets/declarations/server.nix
slack_webhook_url = {
  file = ../parts/server/slack-webhook-url.age;
  owner = "eric";
  group = "secrets";
  mode = "0440";
};
```

**Create Script Wrappers:**
```bash
# /home/eric/.local/bin/run-claude-skill
#!/usr/bin/env bash
SKILL_NAME="$1"
shift
claude skill "$SKILL_NAME" "$@" 2>&1

# /home/eric/.local/bin/n8n-beets-import
#!/usr/bin/env bash
IMPORT_PATH="$1"
beet import -q "$IMPORT_PATH" 2>&1

# /home/eric/.local/bin/n8n-jellyfin-scan
#!/usr/bin/env bash
curl -X POST "http://127.0.0.1:8096/Library/Refresh" \
  -H "X-MediaBrowser-Token: $(cat /run/secrets/jellyfin-api-key)"
```

Make executable: `chmod +x /home/eric/.local/bin/{run-claude-skill,n8n-*}`

### 2. Configure Service Webhooks

**Radarr/Sonarr/Lidarr:** Via web UI, add webhook connections pointing to n8n endpoints

**Frigate:** Edit `/home/eric/.nixos/domains/server/frigate/config/config.yml` and rebuild NixOS

### 3. Build Workflows in n8n

Access n8n at `https://hwc.ocelot-wahoo.ts.net:2443`

For each workflow:
1. Create new workflow with name from plan
2. Add webhook trigger with specified endpoint
3. Build nodes according to flow diagrams above
4. Configure error handling (Error Trigger nodes)
5. Test with sample data
6. Activate workflow

**Node Types Used:**
- Webhook (triggers)
- HTTP Request (API calls)
- Code (JavaScript logic)
- Switch (conditional branching)
- IF (boolean branching)
- Loop Over Items (iteration)
- Set (data transformation)
- Wait (delays)
- Execute Command (shell execution)
- Respond to Webhook (return values)

### 4. Configure Secrets in n8n

Add credentials in n8n UI:
- `jellyfin_api_key`: HTTP Header Auth
- `radarr_api_key`: HTTP Header Auth
- `sonarr_api_key`: HTTP Header Auth
- `lidarr_api_key`: HTTP Header Auth
- `immich_api_key`: HTTP Header Auth
- `slack_webhook_url`: HTTP Basic Auth or Webhook

### 5. Test Each Workflow

**Testing Checklist:**
- [ ] Trigger webhook manually with test payload
- [ ] Verify notification received on ntfy app
- [ ] Check n8n execution logs for errors
- [ ] Test error scenarios (API failures, timeouts)
- [ ] Verify cross-workflow calls work (Workflow 1 → 6, Workflow 3 → 4)
- [ ] Test Slack webhooks for P5 alerts
- [ ] Verify deduplication logic
- [ ] Check audit logs in n8n database

**Test Commands:**
```bash
# Test Media Pipeline
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr" \
  -H "Content-Type: application/json" \
  -d '{"eventType":"Download","title":"Test Movie","quality":"1080p","path":"/mnt/media/movies/Test"}'

# Test Script Executor
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/script-executor" \
  -H "Content-Type: application/json" \
  -d '{"script_name":"service-status","args":["jellyfin"],"async":false}'

# Test Frigate Events (simulate detection)
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/frigate-events" \
  -H "Content-Type: application/json" \
  -d '{"type":"new","after":{"id":"test","camera":"cobra_cam_1","label":"person","top_score":0.9}}'
```

### 6. Enable Production Webhooks

Once tested, configure real service webhooks in Radarr/Sonarr/Lidarr/Frigate UIs.

### 7. Monitor and Iterate

- Check n8n execution history daily for first week
- Adjust notification priorities based on noise levels
- Tune deduplication windows
- Add more scripts to Workflow 6 whitelist as needed
- Export workflows as JSON backups regularly

---

## Cross-Workflow Integrations

**Workflow 1 → Workflow 6:** Music downloads trigger Beets import script
**Workflow 3 → Workflow 4:** Alertmanager alerts call Ollama for AI enrichment
**Workflow 5 → Workflow 6:** Health monitor calls scripts to restart services
**Workflow 2 → Workflow 3:** Frigate can be configured to send high-priority detections through Alertmanager

---

## Critical Files Reference

**n8n Configuration:**
- `/home/eric/.nixos/domains/server/n8n/index.nix` - n8n service definition
- `/home/eric/.nixos/domains/server/n8n/options.nix` - n8n options schema
- `/home/eric/.nixos/domains/server/routes.nix` - Caddy reverse proxy routes

**Secrets:**
- `/home/eric/.nixos/domains/secrets/declarations/server.nix` - Secret declarations
- `/home/eric/.nixos/domains/secrets/parts/server/` - Encrypted .age files

**Service Configs:**
- `/home/eric/.nixos/domains/server/frigate/config/config.yml` - Frigate webhook
- `/home/eric/.nixos/domains/server/monitoring/alertmanager/index.nix` - Alertmanager webhook

**Script Wrappers:**
- `/home/eric/.local/bin/run-claude-skill` - Claude skill executor
- `/home/eric/.local/bin/n8n-*` - n8n helper scripts

**Profiles:**
- `/home/eric/.nixos/profiles/monitoring.nix` - n8n enablement

---

## Success Criteria

✅ All 6 workflows functional and activated
✅ ntfy notifications delivering to iOS/Android
✅ Slack critical alerts reaching workspace
✅ Media imports trigger library updates automatically
✅ Frigate detections filtered and routed intelligently
✅ Alertmanager alerts enriched with live context
✅ Immich photo processing notifications working
✅ Health monitor auto-fixing service failures
✅ Script executor accepting webhook calls securely
✅ Claude Code skills triggerable via webhooks
✅ Zero false critical alerts (proper deduplication)
✅ All executions logged for audit trail

---

## Future Enhancements

- Add email notifications for P5 alerts
- Integrate with Home Assistant for smart home actions
- Add workflow for coordinating qBittorrent/SABnzbd downloads
- Create dashboard workflow for daily system summary
- Add Telegram bot integration as alternative to Slack
- Implement rate limiting for high-volume webhooks
- Add workflow versioning and rollback capability
- Create workflow for automated NixOS configuration backups
