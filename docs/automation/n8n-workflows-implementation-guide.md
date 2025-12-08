# n8n Workflows Implementation Guide

**Created:** 2025-12-08
**Related Plan:** `/home/eric/.claude/plans/cozy-pondering-fog.md`

This guide provides step-by-step instructions for building the 6 n8n automation workflows in the n8n UI.

---

## Prerequisites Completed

✅ Slack webhook secret added to agenix declarations
✅ Script wrappers created in `/home/eric/.local/bin/`
✅ Frigate config updated with n8n webhook URL
✅ n8n running on `https://hwc.ocelot-wahoo.ts.net:2443`

---

## Next Steps: Manual Configuration

### Step 1: Add Slack Webhook URL to agenix

You need to create and encrypt the Slack webhook URL:

```bash
# 1. Create a Slack incoming webhook in your Slack workspace
# Go to: https://api.slack.com/apps → Create App → Incoming Webhooks

# 2. Get the age public key
sudo age-keygen -y /etc/age/keys.txt

# 3. Encrypt the webhook URL
echo "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" | \
  age -r <pubkey> > /home/eric/.nixos/domains/secrets/parts/server/slack-webhook-url.age

# 4. Rebuild NixOS to activate the secret
sudo nixos-rebuild switch --flake /home/eric/.nixos#hwc-server
```

### Step 2: Add Jellyfin API Key (if needed)

If you want the Jellyfin scan script to work, add the API key:

```bash
# 1. Get Jellyfin API key from Jellyfin dashboard: Settings → API Keys

# 2. Add to secrets declarations
# Edit /home/eric/.nixos/domains/secrets/declarations/server.nix and add:
#   jellyfin-api-key = {
#     file = ../parts/server/jellyfin-api-key.age;
#     mode = "0440";
#     owner = "eric";
#     group = "secrets";
#   };

# 3. Encrypt the API key
echo "your-jellyfin-api-key" | \
  age -r <pubkey> > /home/eric/.nixos/domains/secrets/parts/server/jellyfin-api-key.age

# 4. Rebuild NixOS
sudo nixos-rebuild switch --flake /home/eric/.nixos#hwc-server
```

### Step 3: Configure Service Webhooks

#### Radarr, Sonarr, Lidarr

For each *arr service, add webhook connections:

1. Open the service web UI (e.g., `https://hwc.ocelot-wahoo.ts.net/radarr`)
2. Go to: **Settings → Connect → Add Connection → Webhook**
3. Configure:
   - **Name:** n8n Media Pipeline
   - **Webhook URL:** `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr` (change radarr to sonarr/lidarr as appropriate)
   - **Method:** POST
   - **Triggers:** Enable "On Download", "On Upgrade", "On Rename"
4. Click "Test" to verify, then "Save"

Repeat for Sonarr and Lidarr with their respective source parameters.

---

## Building Workflows in n8n UI

Access n8n at: `https://hwc.ocelot-wahoo.ts.net:2443`

### General Workflow Creation Process

1. Click "**Add workflow**" in n8n
2. Name the workflow (use names from plan)
3. Add nodes by clicking the "+" button
4. Configure each node according to specifications below
5. Connect nodes by dragging from output to input dots
6. Add "**Error Trigger**" node for error handling
7. Test with sample data using "Execute Workflow" button
8. Activate workflow with the toggle switch

---

## Workflow 1: Media Pipeline Orchestration

### Nodes to Add:

1. **Webhook** (Trigger)
   - HTTP Method: POST
   - Path: `media-pipeline`
   - Respond: Immediately
   - Response Code: 200

2. **Code** (Parse Event Data)
   ```javascript
   const source = $node["Webhook"].parameter.options.queryParameters.source;
   const event = $input.item.json;

   return {
     json: {
       mediaType: source,
       title: event.movie?.title || event.series?.title || event.album?.title || "Unknown",
       path: event.movieFile?.path || event.episodeFile?.path || event.trackFiles?.[0]?.path || "",
       quality: event.movieFile?.quality || event.episodeFile?.quality || event.trackFiles?.[0]?.quality || "Unknown",
       timestamp: new Date().toISOString()
     }
   };
   ```

3. **Wait** (File Settlement)
   - Amount: 30
   - Unit: Seconds

4. **Switch** (Branch by Media Type)
   - Mode: Rules
   - Rule 1: `{{ $json.mediaType }}` equals `radarr` → Movies
   - Rule 2: `{{ $json.mediaType }}` equals `sonarr` → TV
   - Rule 3: `{{ $json.mediaType }}` equals `lidarr` → Music

5. **HTTP Request** (Jellyfin Refresh - Movies/TV branches)
   - Method: POST
   - URL: `http://127.0.0.1:8096/Library/Refresh`
   - Authentication: Generic Credential Type
     - Add Header: `X-MediaBrowser-Token: {{ $credentials.jellyfin_api_key }}`

6. **HTTP Request** (Script Executor - Music branch)
   - Method: POST
   - URL: `https://hwc.ocelot-wahoo.ts.net:2443/webhook/script-executor`
   - Body:
     ```json
     {
       "script_name": "beets-import",
       "args": ["{{ $json.path }}"],
       "async": true,
       "requester": "workflow-1-media-pipeline"
     }
     ```

7. **Code** (Generate Notification)
   ```javascript
   const { mediaType, title, quality, path } = $json;

   const emoji = {
     radarr: "🎬",
     sonarr: "📺",
     lidarr: "🎵"
   }[mediaType];

   return {
     json: {
       title: `${emoji} ${title}`,
       message: `New ${mediaType} available\nQuality: ${quality}\nPath: ${path}`,
       topic: "hwc-media",
       priority: 2,
       tags: `${mediaType},media,new`
     }
   };
   ```

8. **HTTP Request** (Send to ntfy)
   - Method: POST
   - URL: `https://hwc.ocelot-wahoo.ts.net/notify/{{ $json.topic }}`
   - Headers:
     - `Title`: `{{ $json.title }}`
     - `Tags`: `{{ $json.tags }}`
     - `Priority`: `{{ $json.priority }}`
   - Body: `{{ $json.message }}`

9. **Error Trigger** (Error Handler)
   - Connect to HTTP Request node that sends error notification to ntfy (hwc-alerts, P4)

---

## Workflow 2: Frigate Surveillance Intelligence

### Nodes to Add:

1. **Webhook** (Trigger)
   - Path: `frigate-events`
   - HTTP Method: POST

2. **Code** (Parse & Filter)
   ```javascript
   const event = $input.item.json.after;
   const now = new Date();
   const hour = now.getHours();

   // Filter logic
   const isNight = hour >= 22 || hour <= 6;
   const object = event.label;
   const camera = event.camera;

   // Determine priority
   let priority = 2; // Info
   if (object === "person" && isNight) priority = 5; // Critical
   else if (object === "car" && isNight && camera === "cobra_cam_3") priority = 5;
   else if (object === "person" && !isNight) priority = 4; // High

   // Drop false positives
   if (event.top_score < 0.6) return [];

   return {
     json: {
       eventId: event.id,
       camera: camera,
       object: object,
       score: event.top_score,
       priority: priority,
       isNight: isNight,
       timestamp: now.toISOString()
     }
   };
   ```

3. **HTTP Request** (Fetch Snapshot)
   - URL: `http://127.0.0.1:5000/api/events/{{ $json.eventId }}/snapshot.jpg`
   - Response Format: File

4. **Code** (Generate Notification)
   ```javascript
   const { camera, object, score, priority } = $json;

   const cameraNames = {
     cobra_cam_1: "Front Door",
     cobra_cam_2: "Driveway",
     cobra_cam_3: "Backyard"
   };

   const emojis = {
     person: "🚶",
     car: "🚗",
     dog: "🐕",
     cat: "🐈"
   };

   const title = priority === 5
     ? `🔴 CRITICAL: ${object} at ${cameraNames[camera]}`
     : `${emojis[object]} ${object} at ${cameraNames[camera]}`;

   return {
     json: {
       title: title,
       message: `Confidence: ${(score * 100).toFixed(0)}%\nTime: ${new Date().toLocaleString()}`,
       topic: priority === 5 ? "hwc-critical" : (priority === 4 ? "hwc-alerts" : "hwc-monitoring"),
       priority: priority,
       sendToSlack: priority === 5
     }
   };
   ```

5. **Switch** (Route by Priority)
   - Rule 1: `{{ $json.sendToSlack }}` is true → Send to both
   - Rule 2: Otherwise → Send to ntfy only

6. **HTTP Request** (ntfy - both branches)
7. **HTTP Request** (Slack - high priority branch only)

---

## Workflow 3: System Monitoring & Alertmanager Router

### Nodes to Add:

1. **Webhook** (Trigger)
   - Path: `alertmanager`
   - HTTP Method: POST

2. **Code** (Parse Alerts)
   ```javascript
   const alerts = $input.item.json.alerts || [];

   return alerts.map(alert => ({
     json: {
       name: alert.labels.alertname,
       severity: alert.labels.severity || "P4",
       category: alert.labels.category || "system",
       instance: alert.labels.instance || "unknown",
       summary: alert.annotations.summary || "",
       description: alert.annotations.description || "",
       status: alert.status
     }
   }));
   ```

3. **Loop Over Items** (Process each alert)

4. **Switch** (Branch by Category)
   - Rule 1: category = "system" → Query Prometheus
   - Rule 2: category = "service" → Check systemctl
   - Rule 3: category = "container" → Inspect container

5. **HTTP Request** (Prometheus Query - system branch)
   - URL: `http://127.0.0.1:9090/api/v1/query`
   - Query parameters: Build PromQL based on alert type

6. **Code** (Generate Rich Notification)
   ```javascript
   const { name, severity, summary, description } = $json;

   const emoji = {
     P5: "🔴",
     P4: "⚠️",
     P3: "ℹ️"
   }[severity];

   return {
     json: {
       title: `${emoji} [${severity}] ${name}`,
       message: `${summary}\n\n${description}`,
       topic: severity === "P5" ? "hwc-critical" : (severity === "P4" ? "hwc-alerts" : "hwc-monitoring"),
       priority: parseInt(severity.replace("P", "")),
       sendToSlack: severity === "P5"
     }
   };
   ```

7. **Switch** (Route notifications)
8. **HTTP Request** nodes for ntfy and Slack

---

## Workflow 4: AI/ML Service Orchestration

### Nodes to Add:

1. **Webhook** (Trigger - immich-upload)
   - Path: `immich-upload`

2. **Webhook** (Trigger - ai-enrich)
   - Path: `ai-enrich`

3. **Schedule Trigger** (Scheduled tasks)
   - Daily 2am: `0 2 * * *`
   - Weekly Sunday 3am: `0 3 * * 0`
   - Monthly 1st 4am: `0 4 1 * *`

4. **HTTP Request** (Poll Immich API)
   - URL: `http://127.0.0.1:2283/api/assets/{{ $json.assetId }}`
   - Headers: `x-api-key: {{ $credentials.immich_api_key }}`

5. **HTTP Request** (Ollama Generate)
   - Method: POST
   - URL: `http://127.0.0.1:11434/api/generate`
   - Body:
     ```json
     {
       "model": "llama3",
       "prompt": "{{ $json.context }}",
       "stream": false
     }
     ```

6. **HTTP Request** (Trigger Immich Jobs)
   - URL: `http://127.0.0.1:2283/api/jobs/start`
   - Body: `{ "job": "face-clustering" }` (adjust per schedule)

---

## Workflow 5: Cross-Service Health Monitor

### Nodes to Add:

1. **Schedule Trigger**
   - Every 5 minutes: `*/5 * * * *`

2. **Code** (Define Health Checks)
   ```javascript
   const checks = [
     { name: "Jellyfin", url: "http://127.0.0.1:8096/health", type: "http" },
     { name: "Immich", url: "http://127.0.0.1:2283/api/server/ping", type: "http" },
     { name: "Frigate", url: "http://127.0.0.1:5000/api/config", type: "http" },
     { name: "ntfy", url: "http://127.0.0.1:2586/v1/health", type: "http" },
     { name: "Caddy", service: "caddy", type: "systemd" }
   ];

   return checks.map(check => ({ json: check }));
   ```

3. **Loop Over Items** (Process each check)

4. **Switch** (Branch by check type)

5. **HTTP Request** (HTTP health checks)
   - URL: `{{ $json.url }}`
   - Timeout: 5000ms

6. **Execute Command** (systemd checks)
   - Command: `systemctl is-active {{ $json.service }}`

7. **Code** (Detect Failures & Attempt Remediation)
8. **HTTP Request** (Call Script Executor for service restart)
9. **Code** (Generate notification based on remediation result)

---

## Workflow 6: Universal Script Executor

### Nodes to Add:

1. **Webhook** (Trigger)
   - Path: `script-executor`
   - HTTP Method: POST
   - Respond: Using 'Respond to Webhook' Node

2. **Code** (Validate & Sanitize)
   ```javascript
   const { script_name, args = [], async = false } = $input.item.json;

   // Whitelist
   const allowed = {
     "nix-collect-garbage": "/run/current-system/sw/bin/nix-collect-garbage",
     "service-restart": "/run/current-system/sw/bin/systemctl",
     "beets-import": "/home/eric/.local/bin/n8n-beets-import",
     "jellyfin-scan": "/home/eric/.local/bin/n8n-jellyfin-scan",
     "skill-system-checkup": "/home/eric/.local/bin/run-claude-skill",
     "charter-check": "/home/eric/.local/bin/run-claude-skill"
   };

   if (!allowed[script_name]) {
     throw new Error(`Script '${script_name}' not whitelisted`);
   }

   // Sanitize args
   const sanitized = args.map(arg =>
     String(arg).replace(/[;&|`$(){}[\]<>]/g, '')
   );

   return {
     json: {
       scriptPath: allowed[script_name],
       args: sanitized,
       async: async,
       executionId: `exec-${Date.now()}`
     }
   };
   ```

3. **IF** (Async or Sync?)
   - Condition: `{{ $json.async }}` is true

4. **Execute Command** (Sync branch)
   - Command: `{{ $json.scriptPath }}`
   - Arguments: `{{ $json.args }}`

5. **Respond to Webhook** (Return results)

6. **Code** (Generate notification)
7. **HTTP Request** (Send to ntfy)

---

## Testing Workflows

Use these curl commands to test each workflow:

```bash
# Test Media Pipeline
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr" \
  -H "Content-Type: application/json" \
  -d '{"movie":{"title":"Test Movie"},"movieFile":{"quality":"1080p","path":"/test"}}'

# Test Frigate Events
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/frigate-events" \
  -H "Content-Type: application/json" \
  -d '{"type":"new","after":{"id":"test","camera":"cobra_cam_1","label":"person","top_score":0.9}}'

# Test Script Executor
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/script-executor" \
  -H "Content-Type: application/json" \
  -d '{"script_name":"service-status","args":["jellyfin"],"async":false}'

# Test Alertmanager Router (simulate alert)
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/alertmanager" \
  -H "Content-Type: application/json" \
  -d '{"alerts":[{"status":"firing","labels":{"alertname":"TestAlert","severity":"P4"},"annotations":{"summary":"Test alert"}}]}'
```

---

## Credentials to Add in n8n

Go to **Settings → Credentials** and add:

1. **Jellyfin API Key** (Generic Credential)
   - Value from `/run/secrets/jellyfin-api-key` or Jellyfin dashboard

2. **Radarr/Sonarr/Lidarr API Keys** (Generic Credential)
   - Values from `/run/secrets/*-api-key`

3. **Immich API Key** (Generic Credential)
   - Value from Immich settings

4. **Slack Webhook URL** (Webhook Credential)
   - Value from `/run/secrets/slack-webhook-url`

---

## Verification Checklist

After building all workflows:

- [ ] All 6 workflows created and activated
- [ ] Error Trigger nodes added to each workflow
- [ ] Webhook endpoints tested with curl commands
- [ ] ntfy notifications received on phone
- [ ] Slack critical alerts delivered (once webhook is encrypted)
- [ ] Service webhooks configured (Radarr, Sonarr, Lidarr)
- [ ] Frigate webhook working (test by triggering camera)
- [ ] Script executor whitelist validated
- [ ] Cross-workflow calls working (Workflow 1 → 6)
- [ ] Health monitor attempting auto-remediation
- [ ] Deduplication preventing spam

---

## Maintenance

**Weekly:**
- Review n8n execution history for errors
- Check notification delivery rates
- Tune deduplication windows if too noisy

**Monthly:**
- Export workflows as JSON backups
- Review and update script whitelist
- Check for n8n updates

**Quarterly:**
- Audit workflow execution logs
- Optimize slow-running nodes
- Add new scripts to Workflow 6 as needed

---

## Troubleshooting

**Webhook not triggering:**
- Check n8n is accessible: `curl https://hwc.ocelot-wahoo.ts.net:2443`
- Verify firewall allows Tailscale connections
- Check webhook URL is correct in service config

**ntfy notifications not delivering:**
- Test ntfy directly: `hwc-ntfy-send hwc-test "Test" "Message"`
- Check ntfy service status: `systemctl status ntfy`
- Verify ntfy topic names match plan

**Script execution failing:**
- Check script permissions: `ls -la /home/eric/.local/bin/`
- Test script manually: `/home/eric/.local/bin/run-claude-skill system-checkup`
- Review n8n execution logs for error details

**Slack notifications not working:**
- Verify webhook URL is encrypted in agenix
- Test Slack webhook directly with curl
- Check n8n has access to `/run/secrets/slack-webhook-url`

---

## Reference

- **Full Plan:** `/home/eric/.claude/plans/cozy-pondering-fog.md`
- **n8n Access:** `https://hwc.ocelot-wahoo.ts.net:2443`
- **Script Wrappers:** `/home/eric/.local/bin/`
- **Secrets:** `/home/eric/.nixos/domains/secrets/`
- **Frigate Config:** `/home/eric/.nixos/domains/server/frigate/config/config.yml`

---

**Next Action:** Follow Step 1 to encrypt the Slack webhook URL, then build workflows in n8n UI following the node specifications above.
