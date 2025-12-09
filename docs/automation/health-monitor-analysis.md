# Health Monitor Workflow Analysis

**Date:** 2025-12-08
**Workflow ID:** KaGqsviVtFGp5d7l
**Status:** ✅ Active (running every 5 minutes)
**Last 5 Executions:** All successful

---

## Current Configuration

**Schedule:** `*/5 * * * *` (every 5 minutes)

**Services Monitored:**
- HTTP Checks: Jellyfin, Immich, Frigate, ntfy, n8n, Prometheus, Alertmanager
- Systemd Checks: Caddy, Tailscale

**Total Nodes:** 17

---

## Issues Found

### Issue 1: ntfy URL Incorrect ⚠️

**Current:**
```
URL: https://hwc.ocelot-wahoo.ts.net/notify/={{ $json.topic }}
```

**Should be:**
```
URL: https://hwc.ocelot-wahoo.ts.net/={{ $json.topic }}
```

**Impact:** Notifications are likely being sent to wrong endpoint (404 or incorrect topic)

**Fix:** Update "Send to ntfy" node URL parameter

---

### Issue 2: Notification Body Format

**Current:** Using `bodyParameters` which may not work correctly for ntfy

**Should be:** Use raw body with the message text directly

**Impact:** Message content might not be delivered correctly

---

### Recommended Fixes

#### Fix 1: Update ntfy Node

```json
{
  "name": "Send to ntfy",
  "parameters": {
    "method": "POST",
    "url": "=https://hwc.ocelot-wahoo.ts.net/{{ $json.topic }}",
    "sendHeaders": true,
    "headerParameters": {
      "parameters": [
        {
          "name": "Title",
          "value": "={{ $json.title }}"
        },
        {
          "name": "Tags",
          "value": "={{ $json.tags }}"
        },
        {
          "name": "Priority",
          "value": "={{ $json.priority }}"
        }
      ]
    },
    "sendBody": true,
    "specifyBody": "string",
    "body": "={{ $json.message }}",
    "options": {}
  }
}
```

#### Fix 2: Test ntfy Manually

```bash
# Test correct endpoint
curl -X POST "https://hwc.ocelot-wahoo.ts.net/hwc-monitoring" \
  -H "Title: Health Monitor Test" \
  -H "Tags: test,health" \
  -H "Priority: 3" \
  -d "This is a test message from Health Monitor workflow"
```

---

## Verification Steps

After applying fixes:

1. **Manual Test:**
   ```bash
   # Trigger workflow manually in n8n UI
   # Check ntfy app for notification
   ```

2. **Check Execution Logs:**
   - Verify "Send to ntfy" node shows 200 status code
   - Check response body for confirmation

3. **Wait for Next Scheduled Run:**
   - Monitor ntfy app at next 5-minute mark
   - Should receive notification if any service fails

---

## Additional Recommendations

### Add Error Trigger Node

Currently missing error handling for workflow failures. Add:

- **Error Trigger** node
- Connected to notification that sends to `hwc-critical` topic
- Message: "Health Monitor workflow failed - check n8n logs"

### Add Health Check for More Services

Consider adding:
- Radarr (`http://127.0.0.1:7878/ping`)
- Sonarr (`http://127.0.0.1:8989/ping`)
- Lidarr (`http://127.0.0.1:8686/ping`)

### Improve Notification Logic

Current logic only notifies on failures. Consider:
- Weekly summary of all checks (even if passing)
- Notification when service recovers after failure
- Track failure count to avoid spam

---

## Next Steps

1. Update ntfy node URL via n8n API
2. Test with manual execution
3. Monitor for 30 minutes to ensure notifications work
4. Add error handling
5. Document final configuration

