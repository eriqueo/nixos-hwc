# n8n Workflow Design Plan for hwc-server

## Infrastructure Context Summary

### Existing Services
- **n8n**: Port 5678 (localhost), exposed via Caddy on port 2443
- **ntfy**: Self-hosted notification server at https://hwc.ocelot-wahoo.ts.net/notify/<topic>
- **Alertmanager**: Port 9093, can send webhooks to n8n
- **Prometheus**: Port 9090, provides metrics API
- **Media Stack**: Radarr (7878), Sonarr (8989), Lidarr (8686), qBittorrent (8080), SABnzbd (8081)
- **Surveillance**: Frigate (5000) with 3 cameras (cobra_cam_1/2/3)
- **AI/ML**: Immich (2283), Ollama (11434), Open WebUI (3001)
- **Media Servers**: Jellyfin (8096), Navidrome (4533), Beets (8337)

### Notification Infrastructure
- **ntfy topics**: hwc-critical (P5), hwc-alerts (P4), hwc-backups (P3), hwc-media (P2), hwc-monitoring (P2), hwc-updates (P1), hwc-ai (P2)
- **ntfy CLI**: hwc-ntfy-send available system-wide
- **Slack**: Needs webhook URL (to be added to secrets)

### Claude Code Skills (can be wrapped as scripts)
- charter-check, nixos-build-doctor, secret-provision, add-home-app, add-server-container
- agenix-secrets, beets-music-organizer, media-file-manager, module-migrate
- nixos-charter-compliance, nixos-container-orchestrator, system-checkup

## Workflow Designs

### Workflow 1: Media Pipeline Orchestration
**Purpose**: Complete download-to-library pipeline with smart notifications

**Trigger**: Webhooks from Radarr/Sonarr/Lidarr on download completion

**Steps**:
1. Webhook receives event (movie/show/album downloaded)
2. Parse event data (media type, title, quality, path)
3. Wait for file to settle (30s delay for I/O completion)
4. Trigger appropriate post-processing:
   - Movies: Verify file integrity, update Jellyfin library
   - TV Shows: Check for season completion, update Jellyfin
   - Music: Run Beets import workflow, update Navidrome
5. Verify media server has indexed new content (poll API)
6. Generate rich notification with artwork and metadata
7. Route notification:
   - Successful import: ntfy (hwc-media, P2)
   - Import failed: ntfy (hwc-alerts, P4) + Slack
8. Log event to workflow history

**Error Handling**: Retry failed API calls 3x, alert on persistent failures

**Implementation Notes**:
- Radarr webhook: POST to https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr
- Sonarr webhook: POST to https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=sonarr
- Lidarr webhook: POST to https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=lidarr
- Beets import: Execute via script trigger (Workflow 6)
- Jellyfin scan: POST to http://127.0.0.1:8096/Library/Refresh?api_key=SECRET
- Navidrome scan: POST to http://127.0.0.1:4533/api/scan

---

### Workflow 2: Frigate Surveillance Intelligence
**Purpose**: Smart filtering and routing of Frigate detection events

**Trigger**: Frigate webhook on object detection

**Steps**:
1. Receive Frigate event (camera, object type, score, snapshot URL)
2. Apply intelligent filtering:
   - Person detected: Priority P4 (always notify)
   - Car in driveway (after 10pm or before 6am): Priority P5 (critical)
   - Animal during daytime: Priority P2 (info only)
   - Known false positives (tree shadows): Drop
3. Enrich event data:
   - Fetch high-res snapshot from Frigate API
   - Query Prometheus for camera health metrics
   - Check recent event history (avoid duplicate alerts)
4. Generate context-aware notification:
   - Include camera name, object type, confidence score
   - Embed snapshot image (via ntfy attachment or Slack)
   - Add Frigate web link for video review
5. Route by priority:
   - P5 (nighttime car): Slack + ntfy (hwc-critical)
   - P4 (person): ntfy (hwc-alerts)
   - P2 (animal/daytime): ntfy (hwc-monitoring)
6. Update detection log (could be stored in n8n database or external)

**Error Handling**: Queue failed notifications, retry with exponential backoff

**Implementation Notes**:
- Frigate webhook: POST to https://hwc.ocelot-wahoo.ts.net:2443/webhook/frigate-events
- Configure in Frigate config.yml: `notifications.webhook.url`
- Frigate API: GET http://127.0.0.1:5000/api/events/{event_id}/snapshot.jpg
- Prometheus query: `frigate_camera_fps{camera="cobra_cam_1"}`

---

### Workflow 3: System Monitoring & Alertmanager Router
**Purpose**: Central alert processing hub with enrichment and smart routing

**Trigger**: Alertmanager webhook (already configured to send to n8n)

**Steps**:
1. Receive Alertmanager alert payload
2. Parse alert metadata (severity, category, instance, labels)
3. Enrich alert with live context:
   - System alerts: Query Prometheus for current metrics (CPU/mem/disk trends)
   - Service alerts: Check systemd status via script execution
   - Container alerts: Query Podman API for container state
   - Frigate alerts: Fetch camera health from Frigate API
4. Apply deduplication logic (suppress repeat alerts within time window)
5. Generate rich notification:
   - Alert title with severity emoji (🔴 P5, ⚠️ P4, ℹ️ P3)
   - Current metric value + threshold
   - Link to Grafana dashboard for affected service
   - Suggested remediation action
6. Route by severity:
   - P5 (Critical): Slack + ntfy (hwc-critical, priority=5)
   - P4 (Warning): ntfy (hwc-alerts, priority=4)
   - P3 (Info): ntfy (hwc-monitoring, priority=3)
7. Store alert in n8n database for trend analysis

**Error Handling**: Always deliver critical alerts (P5) even if enrichment fails

**Implementation Notes**:
- Alertmanager config: webhook_configs.url = "https://hwc.ocelot-wahoo.ts.net:2443/webhook/alertmanager"
- Prometheus API: GET http://127.0.0.1:9090/api/v1/query?query=<expr>
- Grafana links: https://hwc.ocelot-wahoo.ts.net:4443/d/<dashboard_uid>
- ntfy with tags: `-H "Tags: alert,host-hwc-server,severity-p5"`

---

### Workflow 4: AI/ML Service Orchestration
**Purpose**: Coordinate Immich processing, Ollama queries, and AI-powered automation

**Trigger**: Multiple triggers (Immich webhooks, schedule, manual webhook)

**Steps**:

**Sub-flow A: Immich Photo Processing**
1. Webhook on Immich upload complete
2. Wait for ML processing to finish (poll Immich API)
3. Extract metadata (faces, objects, location)
4. If faces detected: Send notification with count + preview
5. If location detected: Enrich with reverse geocoding (optional)
6. Notify: ntfy (hwc-ai, P2) with photo preview

**Sub-flow B: Ollama-Powered Notifications**
1. Receive alert/event from another workflow
2. Send context to Ollama API: "Summarize this system alert in one sentence"
3. Generate human-friendly summary
4. Append to notification payload
5. Send enriched notification

**Sub-flow C: Scheduled ML Tasks**
1. Daily at 2am: Trigger Immich face re-clustering
2. Weekly: Run Immich duplicate detection
3. Monthly: Generate photo statistics summary
4. Send report via ntfy (hwc-ai, P1)

**Error Handling**: ML failures are non-critical, log and skip enrichment

**Implementation Notes**:
- Immich webhook: Configure in Immich settings or via API
- Immich API: GET http://127.0.0.1:2283/api/jobs (check status)
- Ollama API: POST http://127.0.0.1:11434/api/generate with model=llama3
- Face clustering: POST http://127.0.0.1:2283/api/jobs/start?job=face-clustering

---

### Workflow 5: Cross-Service Health Monitor
**Purpose**: Proactive health checks and automated remediation

**Trigger**: Schedule (every 5 minutes)

**Steps**:
1. Execute health checks in parallel:
   - Ping all critical services (Jellyfin, Immich, Frigate, ntfy, n8n)
   - Query Prometheus for service_up metrics
   - Check container status via Podman API
   - Verify Tailscale connectivity
2. Detect anomalies:
   - Service not responding (timeout > 5s)
   - Container restart loop (>3 restarts in 10min)
   - High error rate in logs
   - Disk space > 90%
3. Attempt automated remediation:
   - Service down: Trigger restart via systemctl (Workflow 6 script execution)
   - Container failed: Execute `podman restart <container>`
   - Disk full: Run cleanup script (nix-collect-garbage, temp files)
4. Notify on remediation attempt:
   - Success: ntfy (hwc-monitoring, P3) "Auto-fixed: Restarted <service>"
   - Failure: Slack + ntfy (hwc-alerts, P4) "Manual intervention needed"
5. Update health status dashboard (store in n8n DB or external)

**Error Handling**: Never auto-restart critical services (Caddy, SSH) without user confirmation

**Implementation Notes**:
- Health check URLs: https://hwc.ocelot-wahoo.ts.net:<port>/health or /api/ping
- Prometheus query: `up{job="node-exporter"}`
- Podman API: `curl --unix-socket /run/podman/podman.sock http://localhost/v4.0.0/libpod/containers/json`
- Systemctl via script: Execute Workflow 6 with script_name="service-restart", args=["jellyfin"]

---

### Workflow 6: Universal Script Executor
**Purpose**: Secure webhook-triggered script execution hub

**Trigger**: Webhook with JSON payload

**Steps**:

**Request Validation**:
1. Receive POST to https://hwc.ocelot-wahoo.ts.net:2443/webhook/script-executor
2. Parse JSON: `{ "script_name": "...", "args": [...], "async": true/false, "callback_url": "..." }`
3. Validate script_name against whitelist
4. Sanitize arguments (prevent injection)

**Script Categories**:

**A. System Maintenance**
- `nix-collect-garbage`: Run garbage collection, return freed space
- `service-restart`: Restart systemd service, return status
- `service-status`: Get detailed service status + recent logs
- `disk-cleanup`: Clean temp files, Docker images, old downloads
- `backup-now`: Trigger immediate backup job

**B. Media Processing**
- `beets-import`: Run Beets import on specified directory
- `jellyfin-scan`: Trigger Jellyfin library scan (full or path-specific)
- `transcode-queue`: Add file to Tdarr transcode queue
- `media-organize`: Run media-file-manager skill on /mnt/hot
- `music-dedup`: Run beets-music-organizer skill for deduplication

**C. NixOS Operations**
- `nixos-rebuild`: Rebuild NixOS configuration (test/switch)
- `flake-update`: Update flake.lock, report changes
- `charter-check`: Run charter-check skill on specified domain
- `build-doctor`: Run nixos-build-doctor skill to diagnose build failures

**D. Claude Code Skills (wrapped as executables)**
- `skill-system-checkup`: Run system-checkup skill
- `skill-secret-provision`: Run secret-provision skill with args
- `skill-add-container`: Run add-server-container skill
- `skill-beets-organize`: Run beets-music-organizer skill
- `skill-media-organize`: Run media-file-manager skill

**Execution Flow**:
1. Log request to n8n database (timestamp, script, args, requester)
2. If async=true: 
   - Start background process
   - Return execution_id immediately
   - Send callback to callback_url when complete
3. If async=false:
   - Execute synchronously (timeout: 60s)
   - Return stdout/stderr in response
4. Capture execution results (exit code, output, duration)
5. Send notification based on result:
   - Success: ntfy (hwc-updates, P1) with summary
   - Failure: ntfy (hwc-alerts, P4) with error details
6. Store execution log for auditing

**Error Handling**:
- Unknown script: Return 400 Bad Request
- Execution timeout: Kill process, return partial output
- Permission denied: Log security event, alert via Slack

**Security**:
- Whitelist of allowed scripts (hardcoded in workflow)
- Argument validation per script type
- No arbitrary command execution
- All executions logged with timestamp

**Implementation Notes**:
- Scripts location: /home/eric/.local/bin/ or /run/current-system/sw/bin/
- Claude skills wrapper: `/home/eric/.local/bin/run-claude-skill <skill-name> [args]`
- Async execution: Use n8n's Execute Command node with background mode
- Status endpoint: GET https://hwc.ocelot-wahoo.ts.net:2443/webhook/script-status/<execution_id>

**Example Payloads**:
```json
{
  "script_name": "beets-import",
  "args": ["/mnt/hot/music/new"],
  "async": true,
  "callback_url": "https://hwc.ocelot-wahoo.ts.net:2443/webhook/beets-import-complete"
}

{
  "script_name": "skill-system-checkup",
  "args": [],
  "async": false
}

{
  "script_name": "service-restart",
  "args": ["jellyfin"],
  "async": false
}
```

---

## Cross-Workflow Integration

### Media Pipeline → Script Executor
- Workflow 1 calls Workflow 6 to execute Beets import after music download

### Health Monitor → Script Executor
- Workflow 5 calls Workflow 6 to restart failed services automatically

### Alertmanager Router → AI Orchestration
- Workflow 3 calls Workflow 4 to generate human-friendly alert summaries via Ollama

### Frigate Events → Script Executor
- Workflow 2 could trigger Workflow 6 to capture high-res snapshot or record clip

---

## Notification Routing Matrix

| Priority | Condition | ntfy Topic | ntfy Priority | Slack | Example |
|----------|-----------|------------|---------------|-------|---------|
| P5 | Critical system issue | hwc-critical | 5 | YES | CPU > 95%, service down, nighttime intruder |
| P4 | Warning/needs attention | hwc-alerts | 4 | NO | Memory high, person detected, import failed |
| P3 | Informational | hwc-monitoring | 3 | NO | Backup complete, health check passed |
| P2 | Low priority | hwc-media, hwc-ai | 2 | NO | Movie downloaded, photo processed |
| P1 | Background | hwc-updates | 1 | NO | Package updated, cleanup complete |

---

## Implementation Requirements

### Secrets to Add (via agenix)
- `slack_webhook_url`: Slack incoming webhook for alerts
- `n8n_encryption_key`: Already exists (used for workflow encryption)
- API keys already exist: Radarr, Sonarr, Lidarr, Jellyfin, Immich (in secrets domain)

### n8n Nodes Required
- Webhook (trigger)
- Schedule Trigger (cron)
- HTTP Request (API calls)
- Code (JavaScript for logic)
- IF (conditional branching)
- Switch (multi-way branching)
- Set (variable manipulation)
- Execute Command (script execution)
- Wait (delays)
- Loop (iteration)
- Merge (data combination)
- Error Trigger (error handling)

### Script Wrappers to Create
Location: `/home/eric/.local/bin/`

1. `run-claude-skill`: Wrapper to execute Claude Code skills
2. `n8n-service-restart`: Safe systemctl restart with validation
3. `n8n-disk-cleanup`: Disk cleanup script with size reporting
4. `n8n-beets-import`: Beets import with proper logging
5. `n8n-media-organize`: Wrapper for media-file-manager skill
6. `n8n-nixos-rebuild`: Safe NixOS rebuild with rollback support

All scripts should:
- Accept JSON input via stdin (optional)
- Return JSON output to stdout
- Use proper exit codes (0=success, 1=error)
- Log to journald with identifier

---

## Testing Plan

### Workflow 1 (Media Pipeline)
1. Manually trigger Radarr download
2. Verify webhook reaches n8n
3. Confirm Jellyfin scan triggers
4. Check ntfy notification received

### Workflow 2 (Frigate)
1. Trigger test detection via Frigate UI
2. Verify event reaches n8n
3. Confirm filtering logic works
4. Check snapshot embedded in notification

### Workflow 3 (Alertmanager)
1. Trigger test alert via Prometheus
2. Verify n8n enrichment occurs
3. Confirm routing by severity
4. Check Grafana links work

### Workflow 4 (AI/ML)
1. Upload photo to Immich
2. Verify ML processing notification
3. Test Ollama summary generation
4. Trigger scheduled task manually

### Workflow 5 (Health Monitor)
1. Stop a service temporarily
2. Verify detection and auto-restart
3. Confirm notification sent
4. Check remediation logged

### Workflow 6 (Script Executor)
1. Send test webhook with each script type
2. Verify whitelisting works (reject invalid scripts)
3. Test async vs sync execution
4. Confirm callback URLs work
5. Test Claude skill execution

---

## Next Steps for Implementation

1. **Add Slack webhook secret** to domains/secrets/
2. **Create script wrappers** in /home/eric/.local/bin/
3. **Configure service webhooks**:
   - Radarr/Sonarr/Lidarr: Settings → Connect → Webhook
   - Frigate: config.yml notifications section
   - Alertmanager: Already configured
4. **Build workflows in n8n UI**:
   - Import workflow JSON (can be exported from designs)
   - Or build manually following specs above
5. **Test each workflow** individually
6. **Enable cross-workflow integrations**
7. **Monitor n8n logs** for errors
8. **Document workflow IDs** for reference

