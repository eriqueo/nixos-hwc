# Health Monitor Workflow - Fixes Applied

**Date:** 2025-12-08 16:36 MST
**Workflow ID:** KaGqsviVtFGp5d7l
**Status:** ✅ Updated and Active

---

## Changes Applied

### 1. Fixed ntfy Notification URL ✅

**Before:**
```
https://hwc.ocelot-wahoo.ts.net/notify/={{ $json.topic }}
```

**After:**
```
https://hwc.ocelot-wahoo.ts.net/={{ $json.topic }}
```

**Impact:** Notifications will now correctly reach ntfy topics (hwc-critical, hwc-alerts, hwc-monitoring)

---

### 2. Fixed Message Body Format ✅

**Before:**
```json
{
  "bodyParameters": {
    "parameters": [
      {"name": "body", "value": "={{ $json.message }}"}
    ]
  }
}
```

**After:**
```json
{
  "specifyBody": "string",
  "body": "={{ $json.message }}"
}
```

**Impact:** Message content will now be properly sent to ntfy

---

### 3. Enabled Slack for ALL Notifications ✅

**Before:** Only sent to Slack when `sendToSlack: true` (critical alerts only)

**After:** ALL health notifications sent to both ntfy AND Slack

**Node Removed:** "Check if Slack needed" IF node

**Connection Updated:**
```
Generate Notification → [Send to ntfy, Send to Slack]
```

**Impact:** You'll receive health alerts on BOTH platforms while deciding which to use

---

## Testing Results

### Manual ntfy Test ✅
```bash
curl -X POST "https://hwc.ocelot-wahoo.ts.net/hwc-monitoring" \
  -H "Title: ✅ Health Monitor Fixed!" \
  -H "Tags: test,health,fixed" \
  -H "Priority: 3" \
  -d "ntfy URL has been corrected..."
```

**Result:** HTTP 200 OK

**Question for user:** Did you receive this notification on your ntfy app?

---

## Next Automated Run

**Schedule:** Every 5 minutes (`*/5 * * * *`)
**Next Run:** 4:40 PM MST (in ~4 minutes from time of fix)

**What to Expect:**
- If all services are healthy: No notifications
- If any service fails: Notifications sent to BOTH ntfy and Slack

---

## Services Monitored

**HTTP Endpoints:**
1. Jellyfin - `http://127.0.0.1:8096/health`
2. Immich - `http://127.0.0.1:2283/api/server/ping`
3. Frigate - `http://127.0.0.1:5000/api/config`
4. ntfy - `http://127.0.0.1:2586/v1/health`
5. n8n - `http://127.0.0.1:5678/healthz`
6. Prometheus - `http://127.0.0.1:9090/-/healthy`
7. Alertmanager - `http://127.0.0.1:9093/-/healthy`

**Systemd Services:**
8. Caddy
9. Tailscale

---

## Notification Topics

| Service Status | ntfy Topic | Slack | Priority |
|---------------|------------|-------|----------|
| Critical service down (Caddy, SSH, Tailscale) | hwc-critical | ✅ Yes | P5 |
| Service down - auto-restart failed | hwc-alerts | ✅ Yes | P4 |
| Service down - attempting restart | hwc-alerts | ✅ Yes | P4 |
| Service recovered | hwc-monitoring | ✅ Yes | P3 |

---

## Auto-Restart Logic

**Protected Services (NO auto-restart):**
- Caddy
- SSH
- Tailscale

**Auto-restart Enabled:**
- All other services will trigger Script Executor for restart attempt
- Wait 15 seconds after restart
- Re-check health
- Notify based on outcome

---

## Verification Steps

### Step 1: Check ntfy App ✅
- [ ] Received test notification at 4:35 PM MST
- [ ] Title: "✅ Health Monitor Fixed!"
- [ ] Tags: test, health, fixed

### Step 2: Check Slack ⏳
- [ ] Verify Slack webhook is configured
- [ ] Check for health notifications
- [ ] Verify message formatting (blocks)

### Step 3: Wait for Next Scheduled Run (4:40 PM MST) ⏳
- [ ] Workflow executes successfully
- [ ] If services healthy: No notifications
- [ ] If service fails: Notifications on both platforms

### Step 4: Monitor Execution Log ⏳
```bash
# Check recent executions
curl -H "X-N8N-API-KEY: <key>" \
  "https://hwc.ocelot-wahoo.ts.net:2443/api/v1/executions?workflowId=KaGqsviVtFGp5d7l&limit=5"
```

---

## Rollback Instructions (if needed)

If notifications are too noisy or causing issues:

1. **Disable Slack notifications:**
   - Re-add "Check if Slack needed" IF node
   - Route: Generate Notification → Check if Slack needed → [ntfy + Slack | ntfy only]

2. **Revert ntfy URL:**
   - Edit "Send to ntfy" node
   - Change URL back to: `https://hwc.ocelot-wahoo.ts.net/notify/={{ $json.topic }}`

3. **Disable workflow:**
   - Toggle "Active" off in n8n UI
   - Or via API: Update workflow with `"active": false`

---

## Future Improvements

### Short Term:
- [ ] Add error handling (Error Trigger node)
- [ ] Test actual service failure scenarios
- [ ] Verify Slack formatting looks good

### Medium Term:
- [ ] Add more services to monitor (Radarr, Sonarr, Lidarr)
- [ ] Implement deduplication (don't spam on repeated failures)
- [ ] Add weekly health summary (all services passing)

### Long Term:
- [ ] Track failure history
- [ ] Alert on service recovery after failure
- [ ] Integration with external monitoring (UptimeRobot, etc.)

---

## Related Files

- Workflow JSON (backup): `/tmp/health-monitor-fixed.json`
- Analysis Doc: `/home/eric/.nixos/docs/automation/health-monitor-analysis.md`
- Original Workflow: n8n workflow ID `KaGqsviVtFGp5d7l`
- Implementation Guide: `/home/eric/.nixos/docs/automation/n8n-step-by-step-implementation.md`

---

**Status:** ✅ Changes applied successfully via n8n API at 4:34 PM MST
**Next Check:** 4:40 PM MST (automated run)
**Action Required:** Monitor ntfy and Slack for health notifications
