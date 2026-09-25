# n8n Workflow Definitions

## Source of truth

**Live n8n is the source of truth for workflow behaviour.** The JSON in this
directory is a **deterministic, redacted, derived export** of a live workflow —
kept in git so changes are reviewable and so a lost instance can be rebuilt.

It is not a second place to edit. The old instruction here ("edit in the UI,
then export back to keep in sync") made this directory a second producer of the
same fact, and it drifted exactly as you would expect: the frigate export
predated a snapshot-upload rewrite by months, while the live workflow still
held a raw Discord webhook URL that every future export had to scrub correctly.

**Never hand-edit a file here to change behaviour.** Change the live workflow,
export it, and regenerate:

```bash
# 1. export from n8n (UI: … → Download, or the n8n CLI) to a scratch path
# 2. canonicalize into this directory — writes NOTHING if a secret survives
python3 workspace/automation/n8n-workflow-export.py canonicalize \
  --in /tmp/live-export.json \
  --out domains/automation/n8n/parts/workflows/<file>.json
```

The tool drops volatile fields (`updatedAt`, `versionId`, `activeVersion`,
`staticData`, `shared`, …), sorts deterministically, and **fails closed** on any
Discord/Slack webhook, bearer token, API key, or unrecognised credential-shaped
literal. `--redact` replaces *known* shapes with a placeholder and still fails on
anything it does not recognise — silently concealing a new secret is the failure
it exists to prevent. Each generated file carries an `_hwc` block with the source
workflow id/name and its own rebuild command (no timestamp, so regeneration is
byte-stable). The scan is wired into `nix flake check` as
`n8n-workflow-secret-literals`.

Secrets belong in the container env, referenced from the workflow as
`={{ $env.NAME }}` — see `domains/automation/n8n/index.nix` (`secrets.*`) and
`sys.nix`. Adding a secret option there is what makes `$env.NAME` resolve.

### Regeneration status

`01-media-pipeline-orchestration.json` is a canonical export of live workflow
`home:media:jellyfin-alert` (`n14heZ9wzJ8Uyemo`). It carries the `_hwc` marker and
was regenerated after the 2026-09-07 production exercise.

Every other JSON predates the canonicalizer and is hand-maintained, of unknown
fidelity to live: none carries an `_hwc` block, and several still hold volatile
fields (`updatedAt`, `versionId`) the tool drops. They are scanned (clean) but
not canonical.

`02-frigate-surveillance-intelligence.json` was regenerated from the published
live workflow on 2026-09-24. It uses the configured timezone explicitly, checks
the HLS manifest before offering clip links, gives a clear pending/unavailable
message, and bounds HTTP requests without retrying Discord POSTs. Successful
delivery responses (including message IDs) and failures stay in n8n execution
history. A temporary workflow using local HTTP sinks exercised snapshot upload,
snapshot fallback, ready/pending clips, animal routing, cooldown and update
filtering without sending external messages. The temporary workflow was deleted.

Regenerate opportunistically, one live export at a time. Do **not** run the tool
over a tracked file to make it look canonical: canonicalizing a stale artifact
launders the drift into a generated-looking one and stamps it with an `_hwc`
provenance block that live never produced. `--in` takes a fresh export from n8n,
always.

**Completed expand/contract: the duplicate media pipeline.** On 2026-09-07 the
live workflow was backed up, repaired, replayed, exported, and canonicalized to
`01-media-pipeline-orchestration.json`. The replay finished successfully with
switch outputs `[0,1,0]` for the Sonarr event and one hwc-notify audit row. The
superseded `01-media-pipeline-orchestration-FIXED.json` was then deleted. Git
history is the rollback for that stale artifact; the WAL-safe live database and
workflow backups were the rollback for the production edit.

---

The files below can be imported directly into the n8n UI.

> **Retired 2026-07-09** — the three monitoring/alert workflows below were removed
> as redundant with the Prometheus/Alertmanager → hwc-notify stack:
> - `03-system-monitoring-alertmanager-router` — superseded by Alertmanager's
>   native routing (fan-out to hwc-notify). Was already inactive; deleted.
> - `05-cross-service-health-monitor` — HTTP health checks now covered by the
>   blackbox exporter + Grafana "Service Health" dashboard; its ntfy/Slack notify
>   targets were stale (ntfy/gotify decommissioned). Deleted. **Note:** it also
>   had an SSH auto-restart self-heal — if that's wanted back, do it declaratively
>   as systemd `Restart=`/`OnFailure=` policies, not n8n-over-SSH.
> - `11-mail-health-alert-router` — the mail-health checker (`domains/mail/health`)
>   now posts straight to hwc-notify; the n8n hop was pure forwarding middleware.
>   Repointed + orphaned; delete the empty shell in the n8n UI.

## Workflows

> **Retired 2026-09-25 (service split wave 4 audit)** — `04-ai-ml-service-orchestration`,
> `06-universal-script-executor`, `07-transcript-orchestrator`, `09-calculator-lead` and
> `10-lead-response` were deleted from live n8n (inactive or no successful run in 90+ days;
> the site posts calculator leads to crm `/hooks` since 2026-09-18) together with the other
> inactive workflows. Exports live on hwc-server `/var/lib/backups/service-split-wave4/n8n-retired/`.


### 01-media-pipeline-orchestration.json
**Purpose:** Refresh and verify Jellyfin after Radarr or Sonarr downloads, then
send one result through hwc-notify.

**Trigger:** Webhook `/webhook/media-pipeline?source={radarr|sonarr}`

**Features:**
- Handles Radarr movies and Sonarr TV episodes; unknown sources take one warning branch
- 30-second file settlement delay
- Triggers Jellyfin library refresh for movies/TV
- Waits for indexing, then verifies the title through Jellyfin's item search
- Routes each event to exactly one media-type branch; the switch does not emit
  empty items on nonmatching outputs
- Sends the success or workflow error through hwc-notify, not ntfy or Slack

**Service Configuration Required:**
- Radarr: Settings → Connect → Webhook
- Sonarr: Settings → Connect → Webhook

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
- Posts to Discord's camera channel via `={{ $env.DISCORD_WEBHOOK_FRIGATE_URL }}`
  (`hwc.automation.n8n.secrets.discordWebhookFrigateFile` → agenix
  `discord-webhook-frigate`, the same secret hwc-notify's `discord-frigate`
  channel reads). Three nodes post directly rather than through hwc-notify
  because the person-detection post is a **multipart/form-data snapshot
  upload** and the hwc-notify dispatcher carries no attachment. Rotating the
  secret restarts `podman-n8n` via `restartTriggers`.

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

### 08a-jt-data-provider.json
**Purpose:** Provide JobTread customer and job data for the Heartwood Estimator app dropdowns

**Triggers:**
- Webhook `GET /webhook/jt-customers` (Fetch all customers)
- Webhook `GET /webhook/jt-jobs?customerId={id}` (Fetch jobs for customer)

**Features:**
- API key authentication via `x-api-key` header
- GraphQL queries to JobTread API
- Filters jobs by Phase custom field (1-3 = estimating stages)
- Returns formatted dropdown data with IDs, names, addresses

**Request Headers:**
```
x-api-key: {ESTIMATOR_API_KEY}
```

**Response (Customers):**
```json
{
  "customers": [
    { "id": "uuid", "name": "John Smith", "address": "123 Main St, City, ST 12345" }
  ],
  "count": 42
}
```

**Response (Jobs):**
```json
{
  "jobs": [
    { "id": "uuid", "number": "281", "name": "Smith Bathroom", "displayName": "#281 - Smith Bathroom" }
  ],
  "count": 5
}
```

**Credentials Required:**
- `ESTIMATOR_API_KEY`: Shared secret for webhook authentication
- JobTread API credential (Bearer token)

---

### 08b-estimate-router.json (work_estimate_router)
**Purpose:** Route estimates from Heartwood Estimator to JobTread, Postgres archive, and Slack notifications

**Trigger:** Webhook `POST /webhook/estimate-push`

**Request Headers:**
```
Content-Type: application/json
x-api-key: {ESTIMATOR_API_KEY}
```

**Request Schema:**
```json
{
  "action": "push_estimate",
  "mode": "existing",
  "projectType": "bathroom",
  "jobId": "uuid",
  "jobNumber": "281",
  "jobName": "Smith Bathroom",
  "customerId": "uuid",
  "customerName": "John Smith",
  "newJob": null,
  "projectState": { },
  "jtPayload": [ ],
  "totals": {
    "cost": 15000,
    "price": 22500,
    "items": 47,
    "laborHrs": 120,
    "margin": 33.3
  },
  "timestamp": "2026-03-19T..."
}
```

**Features:**
- API key authentication
- Creates new JobTread job if `mode: "new_job"`
- Pushes budget line items to JobTread via GraphQL
- Archives estimate to Postgres (always, even on JT failure)
- Notifies Slack with job link and totals
- Returns detailed result with success/failure status

**Response:**
```json
{
  "success": true,
  "jtPushSuccess": true,
  "jtPushError": null,
  "jobId": "uuid",
  "jobNumber": "281",
  "jobCreated": false,
  "itemsPushed": 47,
  "archived": true,
  "requestId": "est-1710859200000-abc123"
}
```

**Postgres Schema:** See `/home/eric/.nixos/domains/automation/n8n/parts/migrations/001-estimates-table.sql`

**Slack Message Format:**
- Success: Job link, customer, type, items, labor, total with margin
- Failure: Warning with error details, note that estimate is archived

**Credentials Required:**
- `ESTIMATOR_API_KEY`: Shared secret for webhook authentication
- `SLACK_WEBHOOK_URL`: Slack incoming webhook for #hwc-estimates
- `POSTGRES_REST_URL`: PostgREST endpoint for estimates table
- JobTread API credential (Bearer token)

**Test Command:**
```bash
curl -X POST https://hwc-server.ocelot-wahoo.ts.net:2443/webhook/estimate-push \
  -H "Content-Type: application/json" \
  -H "x-api-key: {secret}" \
  -d '{
    "action": "push_estimate",
    "mode": "existing",
    "jobId": "22XXX...",
    "jobNumber": "281",
    "jobName": "Test Job",
    "customerId": "22YYY...",
    "customerName": "Test Customer",
    "projectType": "bathroom",
    "projectState": {},
    "jtPayload": [],
    "totals": { "cost": 1000, "price": 1500, "items": 10, "laborHrs": 8, "margin": 33.3 }
  }'
```

---

### Event workflows superseded by Event Scout

Event discovery, curation, Discord review and calendar actions now belong to
`scout/apps/event-scout`. The former 11/13 exports are removed; restore from git
history only for rollback, with Event Scout publishing disabled first.

## Import Instructions

1. Access n8n: `https://hwc-server.ocelot-wahoo.ts.net:2443`
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
- `ESTIMATOR_API_KEY`: Shared secret for estimator webhook authentication
- `POSTGRES_REST_URL`: PostgREST endpoint (e.g., `http://127.0.0.1:3001`)
- JobTread API Bearer token (configured as HTTP Header Auth credential)

Credentials are accessed via environment variables in workflows:
- `{{ $env.JELLYFIN_API_KEY }}`
- `{{ $env.IMMICH_API_KEY }}`
- `{{ $env.SLACK_WEBHOOK_URL }}`

## Testing

See the main implementation guide for curl test commands for each workflow.

## Maintenance

**Version Control:** These JSON files are tracked in git as deterministic
redacted exports — see [Source of truth](#source-of-truth) above for the one
supported update path. Editing a file here changes nothing in n8n.

**Backup:** the n8n SQLite DB (`/var/lib/hwc/n8n`) is the real backup surface;
these exports are review artifacts, not a restore mechanism for credentials.

**Checks:** `python3 workspace/automation/n8n-workflow-export.py scan --dir
domains/automation/n8n/parts/workflows` (wired as the `n8n-workflow-secret-literals`
flake check); unit tests at `workspace/automation/test_n8n_workflow_export.py`.

---

## Related Documentation

- **Full Implementation Guide:** `/home/eric/.nixos/docs/automation/n8n-workflows-implementation-guide.md`
- **Master Plan:** `/home/eric/.claude/plans/cozy-pondering-fog.md`
- **n8n Module:** `/home/eric/.nixos/domains/server/n8n/index.nix`
- **Script Wrappers:** `/home/eric/.local/bin/`

---

**Last Updated:** 2026-03-24
**Author:** Eric (with Claude assistance)
