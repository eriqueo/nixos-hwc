# HWC n8n Slack Integration Setup Guide

This guide walks you through completing the Slack integration setup for HWC server notifications.

## Prerequisites Completed (by Claude)

- [x] Slack signing secret moved to agenix
- [x] *arr API keys exposed to n8n environment
- [x] Workflow JSON files with state tracking, deduplication, retry logic
- [x] ntfy fallback for when Slack fails

---

## Part 1: Slack App Configuration

### Step 1: Access Your Slack App

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Select your existing HWC app (or create new one)

### Step 2: Configure OAuth Scopes

Navigate to **OAuth & Permissions** → **Scopes** → **Bot Token Scopes**

Add these scopes:
```
chat:write          # Send messages
chat:write.public   # Send to channels bot isn't in
commands            # Slash commands
files:write         # Upload images (for Frigate snapshots)
users:read          # Look up user info
channels:read       # List channels
groups:read         # List private channels
```

### Step 3: Create Slack Channels

Create these channels in your Slack workspace:

| Channel | Purpose |
|---------|---------|
| `#hwc-alerts` | Critical alerts, service down, errors |
| `#hwc-system` | Infrastructure status, routine notifications |
| `#hwc-media` | Media service updates, library changes |

**Important**: Invite the bot to each channel:
```
/invite @HWC Server
```

### Step 4: Configure Slash Commands

Navigate to **Slash Commands** → **Create New Command**

Create each command with this Request URL:
```
https://hwc.ocelot-wahoo.ts.net:10000/webhook/slack-commands
```

| Command | Short Description |
|---------|-------------------|
| `/hwc` | HWC Server main menu |
| `/sys` | System commands (status, disk, logs) |
| `/arr` | Arr stack commands (Sonarr, Radarr, etc) |
| `/dl` | Download commands (qBit, SAB, VPN) |
| `/media` | Media services (Jellyfin, Immich) |
| `/cam` | Surveillance (Frigate) |
| `/ai` | AI services (Ollama) |
| `/docs` | Documents (Paperless) |
| `/finance` | Finance (Firefly) |
| `/books` | Books & audiobooks |

### Step 5: Enable Interactivity

Navigate to **Interactivity & Shortcuts** → Enable **Interactivity**

Set Request URL:
```
https://hwc.ocelot-wahoo.ts.net:10000/webhook/slack-interactivity
```

### Step 6: Reinstall App

After changing scopes, you need to reinstall:

1. Go to **OAuth & Permissions**
2. Click **Reinstall to Workspace**
3. Authorize the new permissions

---

## Part 2: Import Workflows into n8n

### Step 1: Access n8n

1. Open [https://hwc.ocelot-wahoo.ts.net:2443/](https://hwc.ocelot-wahoo.ts.net:2443/)
2. Login with `eric@iheartwoodcraft.com`

### Step 2: Import Each Workflow

For each workflow file:

1. Click **Add workflow** (+ button)
2. Click **Import from File**
3. Select the JSON file from `~/.nixos/docs/n8n-workflows/`
4. Click **Save**

Import in this order:
1. `notification-router.json` - Central notification hub
2. `error-handler.json` - Workflow error reporting
3. `slack-command-router.json` - Slash command handling
4. `system-health-dashboard.json` - Service monitoring

### Step 3: Activate Workflows

For each imported workflow:

1. Open the workflow
2. Toggle the **Active** switch (top right) to ON
3. The webhook URLs will become live

### Step 4: Verify Slack Credentials

1. Open any workflow with a Slack node
2. Click on the Slack node
3. Verify **Credentials** shows "Slack account"
4. If not connected, click to add credentials using your Bot OAuth Token

---

## Part 3: Apply NixOS Changes

```bash
# Rebuild to apply secret changes
sudo nixos-rebuild switch --flake /home/eric/.nixos#hwc-server

# Verify n8n has the new environment variables
sudo systemctl show n8n -p Environment | tr ' ' '\n' | grep -E "SLACK|SONARR|RADARR"
```

---

## Part 4: Test the Integration

### Test 1: Notification Router

```bash
curl -X POST https://hwc.ocelot-wahoo.ts.net/webhook/notify \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Notification",
    "message": "If you see this in Slack, the notification router works!",
    "service": "test",
    "domain": "system",
    "severity": "info"
  }'
```

Expected: Message appears in `#hwc-system`

### Test 2: Health Check

```bash
curl -X POST https://hwc.ocelot-wahoo.ts.net/webhook/health-check
```

Expected: JSON response with service health. If any services are down, message appears in `#hwc-alerts`

### Test 3: Slack Commands

In Slack, type:
```
/hwc
```

Expected: Help menu appears with all available commands

### Test 4: System Status

```
/sys status
```

Expected: "Checking system health..." followed by full health report

---

## Part 5: Error Handler Integration

To connect workflow errors to the error handler, add an **Error Trigger** node to important workflows:

1. Open a workflow
2. Add node → Search "Error Trigger"
3. Add an **HTTP Request** node after it:
   - Method: POST
   - URL: `http://127.0.0.1:5678/webhook/error-handler`
   - Body: `{{ JSON.stringify($json) }}`

Or use **Settings** → **Error Workflow** and select "HWC Error Handler"

---

## Troubleshooting

### Slack commands return "dispatch_failed"

- Verify the Request URL is correct
- Check Tailscale Funnel is running: `tailscale funnel status`
- Ensure n8n is running: `systemctl status n8n`

### No messages appearing in Slack

1. Check bot is in the channel: `/invite @HWC Server`
2. Verify OAuth token is valid (try sending test message in n8n)
3. Check n8n execution logs for errors

### Signature verification failing

- Ensure `SLACK_SIGNING_SECRET` is set in n8n environment
- Rebuild NixOS if secret was recently added
- Check the signing secret matches your Slack app

### Health checks failing for *arr services

- API keys need to be set in n8n environment
- Check secret files exist: `ls /run/agenix/ | grep -E "sonarr|radarr"`
- Verify services are actually running: `curl http://127.0.0.1:8989/api/v3/health`

---

## Webhook URL Reference

| Webhook | URL | Purpose |
|---------|-----|---------|
| Notify | `POST /webhook/notify` | Send notifications to Slack |
| Health Check | `POST /webhook/health-check` | Trigger health check, get JSON |
| Error Handler | `POST /webhook/error-handler` | Report workflow errors |
| Slack Commands | `POST /webhook/slack-commands` | Slash command entry point |

All webhooks available at:
- Internal: `https://hwc.ocelot-wahoo.ts.net/webhook/*`
- Public (Funnel): `https://hwc.ocelot-wahoo.ts.net:10000/webhook/*`
- n8n Direct: `http://127.0.0.1:5678/webhook/*`

---

## Notification Payload Schema

When calling `/webhook/notify`:

```json
{
  "title": "string (required) - Notification title",
  "message": "string - Detailed message body",
  "service": "string - Source service name (e.g., 'sonarr', 'jellyfin')",
  "domain": "string - Category for routing: media|arr|download|system|surveillance|ai|finance|documents|books",
  "severity": "string - info|success|warning|error|critical",
  "channel": "string (optional) - Override channel routing",
  "dedupKey": "string (optional) - Custom deduplication key",
  "metadata": {
    "key": "value - Additional fields to display"
  }
}
```

---

## Maintenance Mode

To suppress alerts during maintenance, you can:

1. **Disable the Health Dashboard workflow** in n8n UI
2. **Or** add a maintenance flag check to the workflow

Future enhancement: Add `/sys maintenance on/off` command.
