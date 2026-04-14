# n8n Workflows: Step-by-Step Implementation Guide

**Created:** 2025-12-08
**Purpose:** Detailed, error-free instructions for implementing all 6 n8n workflows

---

## Critical Fixes Applied

### 1. Jellyfin API Authentication (FIXED)

**Problem:** Wrong headers, wrong endpoints, 401/500 errors

**Solution:**
- ✅ Correct header: `X-Emby-Token` (not `X-MediaBrowser-Token`, not `jellyfin_api_key`)
- ✅ Correct search endpoint: `GET /Items?SearchTerm=...&Recursive=true`
- ✅ Correct refresh endpoint: `POST /Items/{ItemId}/Refresh?Recursive=true`
- ✅ Always use `http://127.0.0.1:8096` (never Caddy proxy)
- ✅ Access API key via `{{ $env.JELLYFIN_API_KEY }}` in headers
- ✅ No n8n credentials - raw headers only

### 2. Workflow Node Connections (FIXED)

**Problem:** Broken node references, missing connections, wrong execution order

**Solution:**
- ✅ All nodes properly connected in sequence
- ✅ Proper branching (music vs video, success vs failure)
- ✅ Fallback paths for empty results
- ✅ No duplicate execution logic

### 3. Environment Variables (FIXED)

**Problem:** Confusion about credentials vs env vars

**Solution:**
- ✅ Set in n8n systemd service: `JELLYFIN_API_KEY`, `SLACK_WEBHOOK_URL`, `IMMICH_API_KEY`
- ✅ Access in workflows: `{{ $env.JELLYFIN_API_KEY }}`
- ✅ NO use of n8n "Credentials" feature for Jellyfin
- ✅ Headers manually specified in every HTTP Request node

### 4. URL Encoding (FIXED)

**Problem:** Search terms with parentheses/special chars broke

**Solution:**
- ✅ Use `{{ encodeURIComponent($json.searchTerm) }}` everywhere
- ✅ Proper path extraction and filename parsing

### 5. Error Handling (FIXED)

**Problem:** No failure notifications, silent errors

**Solution:**
- ✅ IF nodes check for empty results
- ✅ Failure notification paths
- ✅ Meaningful error messages with context

---

## Prerequisites

### 1. Verify n8n Environment Variables

Check that n8n service has access to secrets:

```bash
# Check if environment variables are set
sudo systemctl show n8n | grep -i environment

# Should see:
# Environment=JELLYFIN_API_KEY=<key>
# Environment=SLACK_WEBHOOK_URL=<url>
# Environment=IMMICH_API_KEY=<key>
```

**If missing**, add to `/home/eric/.nixos/domains/server/n8n/index.nix`:

```nix
environment = n8nEnv // {
  JELLYFIN_API_KEY = "$(<${config.age.secrets.jellyfin-api-key.path})";
  IMMICH_API_KEY = "$(<${config.age.secrets.immich-api-key.path})";
  SLACK_WEBHOOK_URL = "$(<${config.age.secrets.slack-webhook-url.path})";
};
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake /home/eric/.nixos#hwc-server
sudo systemctl restart n8n
```

### 2. Verify API Keys Are Readable

```bash
# Jellyfin API key (should be ~40 chars, no trailing %)
sudo head -c 512 /run/agenix/jellyfin-api-key | wc -c

# Should output: 40-50 (not 512)

# Test Jellyfin API
curl -s -H "X-Emby-Token: $(sudo cat /run/agenix/jellyfin-api-key)" \
  http://127.0.0.1:8096/System/Info | jq '.ServerName'

# Should output: your server name, not error
```

### 3. Create Script Wrappers (If Not Exist)

```bash
# Create directory
mkdir -p /home/eric/.local/bin

# Create run-claude-skill wrapper
cat > /home/eric/.local/bin/run-claude-skill <<'EOF'
#!/usr/bin/env bash
SKILL_NAME="$1"
shift
claude skill "$SKILL_NAME" "$@" 2>&1
EOF

# Create n8n-beets-import wrapper
cat > /home/eric/.local/bin/n8n-beets-import <<'EOF'
#!/usr/bin/env bash
IMPORT_PATH="$1"
beet import -q "$IMPORT_PATH" 2>&1
EOF

# Create n8n-jellyfin-scan (optional, not used in fixed workflow)
cat > /home/eric/.local/bin/n8n-jellyfin-scan <<'EOF'
#!/usr/bin/env bash
curl -s -X POST "http://127.0.0.1:8096/Library/Refresh" \
  -H "X-Emby-Token: $(cat /run/agenix/jellyfin-api-key)"
EOF

# Make executable
chmod +x /home/eric/.local/bin/{run-claude-skill,n8n-beets-import,n8n-jellyfin-scan}
```

---

## Workflow 1: Media Pipeline Orchestration (FIXED)

### Import Fixed Workflow

```bash
# File location
/home/eric/.nixos/domains/server/n8n/parts/workflows/01-media-pipeline-orchestration-FIXED.json
```

### Step-by-Step Node Configuration

#### Node 1: Webhook Trigger
- **Type:** Webhook
- **HTTP Method:** POST
- **Path:** `media-pipeline`
- **Response Mode:** Immediately
- **Authentication:** None

**Test URL:** `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr`

---

#### Node 2: Normalize Payload
- **Type:** Code (Function)
- **Purpose:** Extract title, year, path from Radarr/Sonarr/Lidarr webhook

**Key Logic:**
- Extracts `source` from query param
- Normalizes different webhook schemas
- Creates `searchTerm` for Jellyfin lookup
- Handles missing fields gracefully

**Outputs:**
- `source` (radarr/sonarr/lidarr)
- `mediaType` (movie/episode/audio)
- `title`, `year`, `path`, `filename`, `quality`
- `searchTerm` (title + year for search)

---

#### Node 3: Wait for File Settlement
- **Type:** Wait
- **Duration:** 30 seconds
- **Purpose:** Ensure file is fully written before Jellyfin scans

---

#### Node 4: Is Music?
- **Type:** IF
- **Condition:** `{{ $json.mediaType }}` equals `audio`
- **True Branch:** Call Beets Import (music processing)
- **False Branch:** Search Jellyfin (video processing)

---

#### Node 5a: Call Beets Import (Music Branch)
- **Type:** HTTP Request
- **Method:** POST
- **URL:** `https://hwc.ocelot-wahoo.ts.net:2443/webhook/script-executor`
- **Body:**
  ```json
  {
    "script_name": "beets-import",
    "args": ["{{ $json.path }}"],
    "async": true,
    "requester": "workflow-1-media-pipeline"
  }
  ```

---

#### Node 5b: Search Jellyfin Item (Video Branch)
- **Type:** HTTP Request
- **Method:** GET
- **URL:**
  ```
  http://127.0.0.1:8096/Items?SearchTerm={{ encodeURIComponent($json.searchTerm) }}&Recursive=true&IncludeItemTypes={{ $json.mediaType === 'movie' ? 'Movie' : 'Episode' }}
  ```
- **Headers:**
  ```
  X-Emby-Token: {{ $env.JELLYFIN_API_KEY }}
  ```
- **Authentication:** None (manual headers only)

**CRITICAL:**
- Use `X-Emby-Token` header (NOT `X-MediaBrowser-Token`)
- Use `{{ $env.JELLYFIN_API_KEY }}` (NOT credentials)
- Use `encodeURIComponent()` for search term
- Call `127.0.0.1:8096` (NOT Caddy proxy)

---

#### Node 6: Extract Item ID
- **Type:** Code (Function)
- **Purpose:** Parse Jellyfin search results, extract first item's ID

**Logic:**
- Check if `searchResults.Items` array exists and has items
- If empty → set `itemFound: false`
- If found → extract `item.Id`, `item.Name`, `item.Path`

**Outputs:**
- `itemFound` (boolean)
- `itemId` (string or null)
- `itemName`, `itemPath`

---

#### Node 7: Item Found?
- **Type:** IF
- **Condition:** `{{ $json.itemFound }}` is true
- **True Branch:** Refresh Jellyfin Item
- **False Branch:** Failure Notification

---

#### Node 8a: Refresh Jellyfin Item (Success Path)
- **Type:** HTTP Request
- **Method:** POST
- **URL:**
  ```
  http://127.0.0.1:8096/Items/{{ $json.itemId }}/Refresh?Recursive=true&ImageRefreshMode=Default&MetadataRefreshMode=Default&ReplaceAllImages=false&ReplaceAllMetadata=false
  ```
- **Headers:**
  ```
  X-Emby-Token: {{ $env.JELLYFIN_API_KEY }}
  ```

**CRITICAL:**
- Use correct endpoint: `/Items/{ItemId}/Refresh`
- Include query params: `Recursive=true`
- Use `X-Emby-Token` header

---

#### Node 8b: Failure Notification (Not Found Path)
- **Type:** Code (Function)
- **Purpose:** Generate error notification when item not found in Jellyfin

**Outputs:**
- `title`: "⚠️ Media Pipeline: Item Not Found"
- `message`: Details about what wasn't found
- `topic`: `hwc-alerts`
- `priority`: 4

---

#### Node 9a: Success Notification
- **Type:** Code (Function)
- **Purpose:** Generate success message with emoji

**Outputs:**
- `title`: "🎬 Movie Title" or "📺 Show Title"
- `message`: Quality, path, status
- `topic`: `hwc-media`
- `priority`: 2

---

#### Node 9b: Music Notification
- **Type:** Code (Function)
- **Purpose:** Generate music import notification

**Outputs:**
- `title`: "🎵 Album Title"
- `message`: Beets import status
- `topic`: `hwc-media`
- `priority`: 2

---

#### Node 10: Send to ntfy
- **Type:** HTTP Request
- **Method:** POST
- **URL:** `https://hwc.ocelot-wahoo.ts.net/{{ $json.topic }}`
- **Headers:**
  ```
  Title: {{ $json.title }}
  Tags: {{ $json.tags }}
  Priority: {{ $json.priority }}
  ```
- **Body:** `{{ $json.message }}`

**CRITICAL:**
- ntfy URL must NOT have `/notify/` prefix (fixed in workflow)
- Use topic from previous node dynamically

---

### Testing Workflow 1

#### Test 1: Radarr Movie Download

```bash
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "Download",
    "movie": {
      "title": "The Matrix",
      "year": 1999,
      "path": "/mnt/media/movies/The Matrix (1999)"
    },
    "movieFile": {
      "relativePath": "The Matrix (1999)/The Matrix (1999) - 1080p.mkv",
      "path": "/mnt/media/movies/The Matrix (1999)/The Matrix (1999) - 1080p.mkv",
      "quality": {
        "quality": {
          "name": "Bluray-1080p"
        }
      }
    }
  }'
```

**Expected Behavior:**
1. Webhook receives request
2. Normalizes to: `title="The Matrix"`, `year="1999"`, `mediaType="movie"`
3. Waits 30 seconds
4. Searches Jellyfin for "The Matrix (1999)"
5. Extracts ItemId from search results
6. Calls `/Items/{ItemId}/Refresh`
7. Sends ntfy notification: "🎬 The Matrix"

**Check n8n Execution:**
- Go to n8n → Executions
- Find the workflow run
- Verify each node shows green checkmark
- Check "Search Jellyfin Item" node output has `Items` array

---

#### Test 2: Sonarr TV Episode

```bash
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=sonarr" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "Download",
    "series": {
      "title": "Breaking Bad",
      "year": 2008,
      "path": "/mnt/media/tv/Breaking Bad"
    },
    "episodes": [{
      "seasonNumber": 1,
      "episodeNumber": 1
    }],
    "episodeFile": {
      "relativePath": "Season 01/Breaking Bad - S01E01 - Pilot.mkv",
      "path": "/mnt/media/tv/Breaking Bad/Season 01/Breaking Bad - S01E01 - Pilot.mkv",
      "quality": {
        "quality": {
          "name": "WEBDL-1080p"
        }
      }
    }
  }'
```

---

#### Test 3: Lidarr Music Album

```bash
curl -X POST "https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=lidarr" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "Download",
    "artist": {
      "name": "Pink Floyd"
    },
    "album": {
      "title": "Dark Side of the Moon",
      "releaseDate": "1973-03-01",
      "path": "/mnt/media/music/Pink Floyd/Dark Side of the Moon"
    },
    "trackFiles": [{
      "relativePath": "01 - Speak to Me.flac",
      "path": "/mnt/media/music/Pink Floyd/Dark Side of the Moon/01 - Speak to Me.flac",
      "quality": {
        "quality": {
          "name": "FLAC"
        }
      }
    }]
  }'
```

**Expected Behavior:**
1. Detects `mediaType="audio"`
2. Branches to Beets import
3. Calls Script Executor with `beets-import` script
4. Sends ntfy: "🎵 Dark Side of the Moon"

---

### Troubleshooting Workflow 1

#### Problem: "401 Unauthorized" from Jellyfin

**Diagnosis:**
```bash
# Check if env var is set in n8n
sudo systemctl show n8n | grep JELLYFIN_API_KEY

# Should show: Environment=JELLYFIN_API_KEY=<40-char-key>
```

**Fix:**
1. Verify `/run/agenix/jellyfin-api-key` exists and has correct permissions
2. Restart n8n: `sudo systemctl restart n8n`
3. In n8n workflow, verify header is: `X-Emby-Token: {{ $env.JELLYFIN_API_KEY }}`

---

#### Problem: "Item not found" but item exists in Jellyfin

**Diagnosis:**
- Check n8n execution log → "Search Jellyfin Item" node
- Look at Response Data → `Items` array should have entries

**Fix:**
1. Verify search term encoding: should use `encodeURIComponent()`
2. Check IncludeItemTypes parameter matches media type
3. Try manual search:
   ```bash
   curl -s -H "X-Emby-Token: $(sudo cat /run/agenix/jellyfin-api-key)" \
     "http://127.0.0.1:8096/Items?SearchTerm=The%20Matrix%20(1999)&Recursive=true&IncludeItemTypes=Movie" | jq '.Items[0].Name'
   ```

---

#### Problem: "500 Internal Server Error" from Jellyfin

**Diagnosis:**
- Check Jellyfin logs: `sudo journalctl -u jellyfin -n 50`
- Look for exceptions or stack traces

**Common Causes:**
1. Using wrong endpoint (e.g., `/Library/Refresh` instead of `/Items/{Id}/Refresh`)
2. Missing required query parameters
3. Invalid ItemId format

**Fix:**
- Verify workflow uses: `POST /Items/{{ $json.itemId }}/Refresh?Recursive=true`
- Check that `itemId` is a valid GUID format

---

#### Problem: ntfy notification not received

**Diagnosis:**
```bash
# Test ntfy directly
curl -X POST "https://hwc.ocelot-wahoo.ts.net/hwc-media" \
  -H "Title: Test" \
  -H "Priority: 3" \
  -d "Test message"
```

**Fix:**
1. Check ntfy service: `systemctl status ntfy`
2. Verify ntfy URL in workflow: `https://hwc.ocelot-wahoo.ts.net/{{ $json.topic }}`
3. Ensure topic name matches subscription in mobile app

---

### Configure Radarr/Sonarr/Lidarr Webhooks

#### Radarr

1. Open Radarr UI: `https://hwc.ocelot-wahoo.ts.net/radarr`
2. Go to: **Settings → Connect**
3. Click: **+ Add Connection → Webhook**
4. Configure:
   - **Name:** n8n Media Pipeline
   - **Webhook URL:** `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=radarr`
   - **Method:** POST
   - **Triggers:** ✅ On Download, ✅ On Upgrade, ✅ On Rename
5. Click: **Test** → should see green checkmark
6. Click: **Save**

#### Sonarr

Same steps, but use:
- **Webhook URL:** `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=sonarr`

#### Lidarr

Same steps, but use:
- **Webhook URL:** `https://hwc.ocelot-wahoo.ts.net:2443/webhook/media-pipeline?source=lidarr`

---

## Summary: Workflow 1 Checklist

- [ ] Import `01-media-pipeline-orchestration-FIXED.json` into n8n
- [ ] Verify `JELLYFIN_API_KEY` environment variable in n8n service
- [ ] Test Jellyfin API manually with curl
- [ ] Activate workflow in n8n
- [ ] Test with curl (Radarr/Sonarr/Lidarr payloads)
- [ ] Verify ntfy notifications received
- [ ] Configure webhooks in Radarr UI
- [ ] Configure webhooks in Sonarr UI
- [ ] Configure webhooks in Lidarr UI
- [ ] Monitor first real download for success

---

## Next: Workflow 2-6 Detailed Guides

(To be continued with similarly detailed step-by-step guides for remaining workflows...)

---

**Related Files:**
- Fixed Workflow JSON: `/home/eric/.nixos/domains/server/n8n/parts/workflows/01-media-pipeline-orchestration-FIXED.json`
- Original Plan: `/home/eric/.claude/plans/cozy-pondering-fog.md`
- n8n Module: `/home/eric/.nixos/domains/server/n8n/index.nix`
