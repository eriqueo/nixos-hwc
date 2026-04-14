# HWC n8n Workflows

Declarative workflow definitions for the HWC Server automation system.

## Foundation Workflows

| Workflow | File | Webhook Path | Purpose |
|----------|------|--------------|---------|
| Notification Router | `notification-router.json` | `/webhook/notify` | Central notification routing to Slack |
| Error Handler | `error-handler.json` | `/webhook/error-handler` | Workflow error reporting |
| Slack Command Router | `slack-command-router.json` | `/webhook/slack-commands` | Slash command parsing |
| System Health Dashboard | `system-health-dashboard.json` | `/webhook/health-check` | Service health monitoring |

## Webhook URLs

- **Internal**: `https://hwc.ocelot-wahoo.ts.net/webhook/<path>`
- **Public (Funnel)**: `https://hwc.ocelot-wahoo.ts.net:10000/webhook/<path>`
- **n8n Direct**: `https://hwc.ocelot-wahoo.ts.net:2443/webhook/<path>`

## Slack Integration

### Required Channels
- `#hwc-alerts` - Critical alerts, errors, service down
- `#hwc-system` - Infrastructure status, routine notifications
- `#hwc-media` - Media service updates

### Slash Commands
Configure in Slack App → Slash Commands with Request URL:
`https://hwc.ocelot-wahoo.ts.net:10000/webhook/slack-commands`

| Command | Description |
|---------|-------------|
| `/hwc` | Main help menu |
| `/sys` | System commands |
| `/media` | Media services |
| `/arr` | Arr stack |
| `/dl` | Downloads |
| `/cam` | Surveillance |
| `/ai` | AI services |

## Importing Workflows

```bash
# Import a workflow
N8N_USER_FOLDER=/var/lib/hwc/n8n \
  n8n import:workflow --input=docs/n8n-workflows/notification-router.json

# Or use the n8n UI: Settings → Import from File
```

## Sending Notifications

```bash
# Example: Send notification via curl
curl -X POST https://hwc.ocelot-wahoo.ts.net/webhook/notify \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Notification",
    "message": "This is a test message",
    "service": "test",
    "domain": "system",
    "severity": "info"
  }'
```

## Notification Payload Schema

```json
{
  "title": "string (required)",
  "message": "string",
  "service": "string (source service name)",
  "domain": "string (media|arr|download|system|surveillance|ai|finance|documents|books)",
  "severity": "string (info|success|warning|error|critical)",
  "channel": "string (optional, override channel)",
  "metadata": "object (additional fields to display)"
}
```

## Health Check Response

The `/webhook/health-check` endpoint returns:

```json
{
  "overallHealthy": true,
  "healthyCount": 18,
  "unhealthyCount": 0,
  "unhealthyServices": [],
  "byDomain": {
    "media": { "healthy": [...], "unhealthy": [] },
    "arr": { "healthy": [...], "unhealthy": [] }
  }
}
```
