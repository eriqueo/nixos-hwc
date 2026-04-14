# Estimator Integration: Deployment Progress

## Status: Workflows Imported, Needs Credentials + Activation

---

## Completed

### Phase 1: Database Setup
- [x] Created `estimates` table in hwc database
- [x] All indexes created

### Phase 2: Secrets & Credentials
- [x] Generated API key: `T8SLQ1N8wxg9tlwRa8FG1p17ZDUj3w1NwBKVVwQVxWQ=`
- [x] Added ESTIMATOR_API_KEY to n8n config (`profiles/monitoring.nix`)

### Phase 3: Import Workflows
- [x] Imported `08a` → ID: `7JRWiYxyZeppoVE0`
- [x] Imported `08b` → ID: `jbIqSwVByVnEAk7e`
- [ ] Configure JobTread credential in n8n UI
- [ ] Configure SLACK_WEBHOOK_URL env var in n8n
- [ ] Activate both workflows

### Phase 4: App Configuration & Build
- [x] Created `.env` file with VITE_WEBHOOK_URL and VITE_API_KEY
- [x] App built successfully

---

## Remaining Steps

### 1. Rebuild NixOS (apply ESTIMATOR_API_KEY)
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

### 2. Configure Credentials in n8n UI
Access: https://hwc.ocelot-wahoo.ts.net:2443

**JobTread API Credential:**
1. Settings → Credentials → Add Credential
2. Type: "Header Auth"
3. Name: `JobTread API`
4. Header Name: `Authorization`
5. Header Value: `Bearer {your-jobtread-api-key}`

**Environment Variables:**
1. Settings → Credentials → Add Credential
2. Type: "Environment Variable"
3. Add `SLACK_WEBHOOK_URL` with your Slack webhook

### 3. Link Credentials to Workflows
1. Open workflow `7JRWiYxyZeppoVE0` (JT Data Provider)
2. Click each HTTP Request node → select JobTread credential
3. Save workflow
4. Repeat for workflow `jbIqSwVByVnEAk7e` (Estimate Router)

### 4. Activate Workflows
1. Toggle both workflows to "Active"

### 5. Test Endpoints
```bash
# Test customers endpoint
curl -H "x-api-key: T8SLQ1N8wxg9tlwRa8FG1p17ZDUj3w1NwBKVVwQVxWQ=" \
  https://hwc.ocelot-wahoo.ts.net:2443/webhook/jt-customers

# Test jobs endpoint
curl -H "x-api-key: T8SLQ1N8wxg9tlwRa8FG1p17ZDUj3w1NwBKVVwQVxWQ=" \
  "https://hwc.ocelot-wahoo.ts.net:2443/webhook/jt-jobs?customerId={uuid}"

# Test estimate push
curl -X POST https://hwc.ocelot-wahoo.ts.net:2443/webhook/estimate-push \
  -H "Content-Type: application/json" \
  -H "x-api-key: T8SLQ1N8wxg9tlwRa8FG1p17ZDUj3w1NwBKVVwQVxWQ=" \
  -d '{"action":"push_estimate","mode":"existing","jobId":"xxx","jtPayload":[],"totals":{}}'
```

---

## Workflow IDs

| Workflow | n8n ID |
|----------|--------|
| JT Data Provider | `7JRWiYxyZeppoVE0` |
| Estimate Router | `jbIqSwVByVnEAk7e` |

---

## Quick Commands

```bash
# Rebuild server
sudo nixos-rebuild switch --flake .#hwc-server

# Check n8n container
podman logs n8n

# Test database
psql -U eric -d hwc -c "SELECT COUNT(*) FROM estimates;"

# Rebuild app
cd ~/.nixos/workspace/projects/react/heartwood-assembler && npm run build
```
