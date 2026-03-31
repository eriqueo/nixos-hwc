# Notification Taxonomy Spec v1.0

**Owner:** Eric
**Scope:** All notification routing across Slack, Gotify, n8n, Postgres, and future automation consumers
**Goal:** Unified naming, labeling, and routing taxonomy that enables coarse human triage today and machine-actionable dispatch tomorrow
**Philosophy:** The channel/app is the coarse filter (what kind of attention). Tags carry the detail (what specifically, from where, how urgent). Every emitter speaks the same vocabulary. Every consumer filters on the same dimensions.
**Date:** March 31, 2026

---

## 1. Design Principles

**One taxonomy, many transports.** Slack, Gotify, n8n, Postgres, Ollama — they all consume the same structured event. The taxonomy is transport-agnostic. Each transport renders it differently (Slack: channel + message blocks, Gotify: app + priority, Postgres: indexed columns), but the source vocabulary is identical.

**Coarse routing, granular tagging.** 8 channels/apps handle routing. Structured metadata handles everything else. This keeps the infrastructure surface small (8 tokens, 8 channels) while preserving unlimited granularity for filtering, automation, and analysis.

**Mirrors existing domain architecture.** The notification taxonomy extends the NixOS domain-driven architecture (CHARTER.md) and the Heartwood business operating system (HEARTWOOD_OPERATING_SYSTEM.md). Naming conventions are consistent across all three. A service that lives at `domains/media/frigate/` in NixOS has the canonical source slug `frigate` in notifications.

**Infrastructure is not a universe — it's a cross-cutting concern.** A failed service inherits urgency from whichever universe it serves. Heartwood MCP down is `hwc:ops` (revenue-blocking). Sabnzbd down is `home:media` (fix on Saturday). There is no standalone "infrastructure" domain.

**Emitters tag, routers route, consumers filter.** n8n workflows, Alertmanager rules, and scripts are emitters — they produce structured payloads with `source`, `category`, `severity`, and `action_hint`. The notification router sub-workflow handles fan-out to all consumers. Consumers (your phone, dashboards, Ollama) filter on whatever dimensions they need.

---

## 2. The Address Format

Every notification has a hierarchical address:

```
{universe}:{domain}:{source}:{category}
```

Different systems consume different parts:

| System | Consumes | Example |
|--------|----------|---------|
| Slack channel name | `{universe}-{domain}` | `hwc-ops` |
| Gotify app name | `{universe}:{domain}` | `hwc:ops` |
| n8n workflow name | `{universe}:{domain}:{description}` | `hwc:ops:lead-response` |
| n8n workflow tags | Individual segments | tags: `hwc`, `ops`, `lead` |
| Postgres events table | All segments as indexed columns | Full structured row |
| Ollama prompt context | Full structured payload | JSON input |

**Canonical delimiter:** Colon (`:`) in payloads, Postgres, n8n names, n8n tags, and Gotify.
**Transport substitution:** Slack does not allow colons in channel names — use hyphens (`-`) for Slack channel names only. The canonical form everywhere else is colons.

---

## 3. Controlled Vocabularies

### 3.1 Universe (2 values + 1 system namespace)

| Value | Description |
|-------|-------------|
| `hwc` | Heartwood Craft — the business |
| `home` | Personal, homelab, home life |
| `sys` | System-level workflows (router, health aggregator). Not a notification destination — only used for n8n workflow naming. |

### 3.2 Domain (4 per universe, 8 total)

**Business domains (hwc):**

| Domain | Scope | Urgency Profile |
|--------|-------|-----------------|
| `ops` | The active business. All JT, lead funnel end-to-end, voice logs, client comms, OpenPhone, active job management, estimate pipeline. Also infrastructure that directly serves ops (MCP down, lead workflow failed, JT API unreachable). | Act now (leads) to review-soon (job updates) |
| `financial` | Money movement. Stripe payments, receipt pipeline, Paperless-ngx (business docs), Firefly III, QuickBooks, tax deadlines, budget variance. | Review-soon. Own cadence, own automation future. |
| `dev` | Building the business. CMS, blog posts, portfolio uploads, SEO scrapes, marketing metrics, website deploys, brand/content work. Website management lives here — uploading photos and writing posts is development, not operations. | Batch. |
| `admin` | Business infrastructure catchall. Heartwood MCP health (when not directly blocking ops), n8n engine health (not individual workflow results), domain/hosting, email deliverability. Anything that supports the business but isn't the business itself. | Warning to info. |

**Personal domains (home):**

| Domain | Scope | Urgency Profile |
|--------|-------|-----------------|
| `security` | Physical world awareness. All Frigate. Priority varies by MQTT detection type (person unknown = critical, person known = info, animal/vehicle = debug). | Variable by detection type. |
| `media` | Entertainment and content services. Sabnzbd, Immich, Jellyfin, Navidrome, *arr stack, downloads. | Batch. |
| `social` | People and scheduling. Mail, calendar, mail-digest, social platforms. The comms layer of personal life. | Review-soon. |
| `admin` | Server infrastructure catchall. Backups, Tailscale, certs, NixOS rebuilds, Podman container health, disk, Borg status. Homelab administration. | Warning to info. |

### 3.3 Source (canonical service registry)

Every emitting service has one canonical slug. This slug is used in notification payloads, n8n workflow names, n8n tags, and Postgres records. New services must be added to this registry before emitting notifications.

**Business sources:**

| Slug | Service | Primary Domain |
|------|---------|----------------|
| `jobtread` | JobTread CRM/PM (PAVE API) | hwc:ops |
| `openphone` | OpenPhone (calls/SMS) | hwc:ops |
| `heartwood-mcp` | Heartwood MCP Server (port 6100) | hwc:ops or hwc:admin |
| `calculator` | Bathroom cost calculator (website widget) | hwc:ops |
| `website-cms` | Heartwood website CMS dashboard | hwc:dev |
| `stripe` | Stripe payment processing | hwc:financial |
| `quickbooks` | QuickBooks accounting | hwc:financial |
| `firefly` | Firefly III | hwc:financial |
| `paperless` | Paperless-ngx (business docs) | hwc:financial |
| `estimator` | Estimate assembler app | hwc:ops |

**Infrastructure sources (serve both universes — domain determined by context):**

| Slug | Service | Typical Domain |
|------|---------|----------------|
| `n8n` | n8n automation engine | hwc:admin or home:admin |
| `caddy` | Caddy reverse proxy | hwc:admin or home:admin |
| `postgres` | PostgreSQL database | hwc:admin or home:admin |
| `tailscale` | Tailscale mesh VPN | home:admin |
| `borg` | Borg backup | home:admin |
| `uptime-kuma` | Uptime Kuma monitoring | hwc:admin or home:admin |
| `nixos` | NixOS system events | home:admin |
| `podman` | Podman container runtime | home:admin |
| `alertmanager` | Prometheus Alertmanager | home:admin |
| `gotify` | Gotify notification service | home:admin |
| `ollama` | Ollama local LLM | home:admin |

**Personal sources:**

| Slug | Service | Primary Domain |
|------|---------|----------------|
| `frigate` | Frigate NVR (cameras) | home:security |
| `immich` | Immich photo management | home:media |
| `sabnzbd` | SABnzbd downloader | home:media |
| `jellyfin` | Jellyfin media server | home:media |
| `navidrome` | Navidrome music server | home:media |
| `sonarr` | Sonarr TV management | home:media |
| `radarr` | Radarr movie management | home:media |
| `protonmail` | Proton Bridge email | home:social |
| `gcal` | Google Calendar | home:social |

### 3.4 Category (event type — determines response pattern)

| Category | Description | Future Automation Pattern |
|----------|-------------|--------------------------|
| `lead` | New inbound prospect requiring human response | AI pre-draft, pre-qualify, urgency scoring |
| `client-comms` | Client communication (reply, question, update) | Context injection, draft assist |
| `job-update` | JT job phase change, task completion, milestone | Awareness, trigger next-stage tasks |
| `payment` | Money received, invoice status, financial event | Reconciliation, QB sync |
| `receipt` | Business receipt/document processed | Paperless → Firefly sync, job matching |
| `workflow` | n8n workflow result (success or failure) | Retry on failure, log on success |
| `infrastructure` | Service health (up, down, degraded) | Auto-restart, escalate if persistent |
| `content` | Content/dev asset event (deploy, SEO, blog) | Scheduling, metric tracking |
| `detection` | Physical world event (Frigate camera) | Ollama classify before alerting |
| `backup` | Backup completion, failure, verification | Retry on failure, alert on age |
| `digest` | Batched summary (daily mail, weekly metrics) | Ollama summarization |
| `reminder` | Time-triggered prompt (tax deadline, follow-up) | Escalate if not acknowledged |

### 3.5 Severity (4 levels)

| Level | Gotify Priority | Phone Behavior | Future Automation |
|-------|----------------|----------------|-------------------|
| `critical` | 8–10 | Push with sound | Auto-remediate immediately, escalate if failed |
| `warning` | 5–7 | Silent push | Auto-remediate with delay, or flag for manual review |
| `info` | 3–4 | No push, badge only | Log only |
| `debug` | 1–2 | Log only, never push | Log only, available for forensics |

### 3.6 Action Hint (optional — dispatch key for future self-healing)

| Hint | Description |
|------|-------------|
| `restart-service` | Restart the named service via systemctl or podman |
| `retry-workflow` | Re-execute the failed n8n workflow |
| `escalate` | Bump severity and re-notify |
| `classify` | Send to Ollama for classification before routing |
| `sync` | Trigger cross-system sync (e.g., Paperless → Firefly) |
| `draft-response` | Generate AI draft for human review |
| `none` | Informational only, no automated action |

---

## 4. The Notification Payload (API Contract)

Every emitter produces this JSON structure. The notification router consumes it and fans out to all consumers.

```json
{
  "universe": "hwc",
  "domain": "ops",
  "source": "jobtread",
  "category": "job-update",
  "severity": "info",
  "summary": "Job #280 Margulies Kids Bath → Phase 5: Work Start",
  "action_hint": "none",
  "timestamp": "2026-03-31T14:30:00Z",
  "metadata": {
    "job_id": "22PUXMEJnx4t",
    "job_name": "Margulies Kids Bathroom",
    "job_number": 280,
    "old_phase": "Budget Approved",
    "new_phase": "Work Start"
  }
}
```

**Required fields:** `universe`, `domain`, `source`, `category`, `severity`, `summary`, `timestamp`
**Optional fields:** `action_hint` (defaults to `none`), `metadata` (defaults to `{}`)

All values in controlled fields must come from the vocabularies in Section 3. Freeform values are only permitted in `summary`, `metadata`, and `timestamp`.

---

## 5. Routing Infrastructure

### 5.1 Slack Channels (8)

Create these channels. Archive existing channels after migration.

| Channel Name | Maps To | Phone Notification Setting |
|-------------|---------|---------------------------|
| `hwc-ops` | hwc:ops | All notifications, push enabled |
| `hwc-financial` | hwc:financial | All notifications, silent push |
| `hwc-dev` | hwc:dev | Muted, check manually |
| `hwc-admin` | hwc:admin | Warning+ push, info muted |
| `home-security` | home:security | Critical push with sound, info muted |
| `home-media` | home:media | Muted |
| `home-social` | home:social | All notifications, silent push |
| `home-admin` | home:admin | Warning+ push, info muted |

**Existing channels → disposition:**

| Current Channel | Disposition | Absorbed Into |
|----------------|-------------|---------------|
| `#all-hwc-slack` | Archive | Domain-specific channels |
| `#blogs-ads` | Archive | `hwc-dev` |
| `#frigate-other` | Archive | `home-security` (severity: debug) |
| `#frigate-person` | Archive | `home-security` (severity: critical/warning) |
| `#leads` | Archive | `hwc-ops` |
| `#nano` | Archive | `home-admin` |
| `#server-admin` | Archive | `home-admin` |
| `#server-errors` | Archive | `home-admin` (severity: critical/warning) |
| `#social` | Archive | `home-social` |

### 5.2 Gotify Apps (8)

Create these apps. Delete or archive existing apps after migration.

| App Name | Maps To | Default Priority |
|----------|---------|-----------------|
| `hwc:ops` | hwc:ops | 8 (overridden per-event by severity) |
| `hwc:financial` | hwc:financial | 5 |
| `hwc:dev` | hwc:dev | 3 |
| `hwc:admin` | hwc:admin | 5 |
| `home:security` | home:security | 8 (overridden per-event by detection type) |
| `home:media` | home:media | 2 |
| `home:social` | home:social | 4 |
| `home:admin` | home:admin | 5 |

**Existing Gotify apps → disposition:**

| Current App | Disposition | Absorbed Into |
|------------|-------------|---------------|
| `monitoring` | Delete after migration | `home:admin` |
| `alerts` | Delete after migration | `hwc:admin` or `home:admin` by source |
| `backup` | Delete after migration | `home:admin` (category: backup) |
| `mail` | Delete after migration | `home:social` |
| `leads` | Delete after migration | `hwc:ops` |
| `laptop` | Delete after migration | `home:admin` |
| `content` | Delete after migration | `hwc:dev` |

### 5.3 Postgres Events Table

```sql
CREATE TABLE IF NOT EXISTS hwc.notification_events (
  id SERIAL PRIMARY KEY,
  universe VARCHAR(10) NOT NULL,
  domain VARCHAR(20) NOT NULL,
  source VARCHAR(50) NOT NULL,
  category VARCHAR(30) NOT NULL,
  severity VARCHAR(10) NOT NULL,
  summary TEXT NOT NULL,
  action_hint VARCHAR(30) DEFAULT 'none',
  metadata JSONB DEFAULT '{}',
  event_timestamp TIMESTAMPTZ NOT NULL,
  -- routing audit
  slack_posted BOOLEAN DEFAULT FALSE,
  gotify_posted BOOLEAN DEFAULT FALSE,
  -- future self-healing
  remediation_attempted BOOLEAN DEFAULT FALSE,
  remediation_result TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_events_universe_domain ON hwc.notification_events(universe, domain);
CREATE INDEX idx_events_source ON hwc.notification_events(source);
CREATE INDEX idx_events_severity ON hwc.notification_events(severity);
CREATE INDEX idx_events_category ON hwc.notification_events(category);
CREATE INDEX idx_events_timestamp ON hwc.notification_events(event_timestamp);
```

---

## 6. The Notification Router (n8n Sub-Workflow)

**Workflow name:** `sys:router:notify`
**Trigger:** Called as sub-workflow (not webhook-triggered)
**Input:** The notification payload (Section 4)

**Processing steps:**
1. Validate required fields. Reject if any controlled-vocabulary field has an unrecognized value.
2. Map severity to Gotify priority: critical→8, warning→5, info→3, debug→1.
3. Format Slack message with structured metadata footer.
4. Post to Slack channel `{universe}-{domain}`.
5. Post to Gotify app `{universe}:{domain}` with mapped priority.
6. Insert full payload into `hwc.notification_events`.
7. If `action_hint != "none"` and auto-remediation is enabled, trigger remediation (future — stub for now).

**Error handling:** Consumer failures (Slack down, Gotify down) must not block other consumers. Postgres is the durable record. Log consumer failures as their own events (`source: n8n`, `category: infrastructure`, `severity: warning`).

---

## 7. n8n Workflow Naming and Tagging

### Naming Convention

```
{universe}:{domain}:{description}
```

Description is lowercase, hyphen-separated, descriptive of what the workflow does.

### Migration Table

| Current Name | n8n ID | New Name | Tags |
|-------------|--------|----------|------|
| `work_jt_data_provider` (#08a) | — | `hwc:ops:jt-data-provider` | `hwc`, `ops`, `jobtread` |
| `work_estimate_router` (#08b) | jbIqSwVByVnEAk7e | `hwc:ops:estimate-push` | `hwc`, `ops`, `estimator`, `jobtread` |
| `work_calculator_lead` (#09) | SoLwmxgkMILrOYbP | `hwc:ops:calculator-lead` | `hwc`, `ops`, `calculator`, `lead` |
| `work_lead_response` (#10) | lead-response-automation | `hwc:ops:lead-response` | `hwc`, `ops`, `lead` |
| `work_voice_log` (#12) | XAm7ehKjJers5NqC | `hwc:ops:voice-log` | `hwc`, `ops`, `jobtread` |
| `frigate_slack` | — | `home:security:frigate-detect` | `home`, `security`, `frigate`, `detection` |
| Notification router (new) | — | `sys:router:notify` | `sys`, `router` |

Workflows not listed require server-side inventory. Each must be renamed and tagged per this convention.

### Tag Registry

Every workflow must have at minimum a universe tag and a domain tag.

- **Universe tags:** `hwc`, `home`, `sys`
- **Domain tags:** `ops`, `financial`, `dev`, `admin`, `security`, `media`, `social`
- **Source tags:** from Section 3.3 canonical registry
- **Category tags:** from Section 3.4, when the workflow emits notifications

---

## 8. Severity Defaults

| Event Type | Default Severity |
|-----------|-----------------|
| New lead (any source) | `critical` |
| Client reply/question | `critical` |
| Lead follow-up due | `warning` |
| JT job phase change | `info` |
| Payment received | `info` |
| Estimate pushed successfully | `info` |
| Voice log processed | `info` |
| Workflow completed successfully | `debug` |
| Workflow failed | `warning` |
| Service unresponsive (business-serving) | `critical` |
| Service unresponsive (personal-serving) | `warning` |
| Backup completed | `debug` |
| Backup failed | `warning` |
| Backup missed (24hr+) | `critical` |
| Cert expiring (7+ days) | `info` |
| Cert expiring (<3 days) | `critical` |
| Disk >80% | `warning` |
| Disk >95% | `critical` |
| Frigate: unknown person | `critical` |
| Frigate: known person | `info` |
| Frigate: animal/vehicle | `debug` |
| Website deploy completed | `info` |
| SEO data scraped | `debug` |

---

## 9. Future: Self-Healing Layer

```
Event → Router → Postgres (durable log)
               → Slack + Gotify (human awareness)
               → Remediation Dispatcher
                   → Auto-fix scripts (restart, retry, sync)
                   → Ollama classification (Frigate, lead scoring)
                   → Escalation (bump severity, re-notify)
```

**Per-domain automation policies:**

| Domain + Category | Policy |
|------------------|--------|
| hwc:ops + infrastructure | Aggressive restart. Escalate after 60s if still down. |
| hwc:ops + lead | Never auto-respond. AI can draft for human review. |
| hwc:financial + payment | Log only. Human reconciliation. |
| home:security + detection | Classify first (Ollama). Notify only on unknown-person. |
| home:admin + infrastructure | Try restart once. Log. Notify if failed. |
| home:media + infrastructure | Try restart once. Log. Don't notify unless failed 3x. |

---

## 10. Implementation Phases

### Phase 1: Routing surface
Create 8 Slack channels, 8 Gotify apps, Postgres table. Do not archive old channels yet.

### Phase 2: Notification router
Build `sys:router:notify` sub-workflow. Test with manual payloads.

### Phase 3: Rename and tag workflows
Rename existing n8n workflows per Section 7. Add tags. One at a time, verify after each.

### Phase 4: Migrate to router
Replace direct Slack/Gotify posts with router calls. One workflow at a time. Archive old channels/apps when complete.

### Phase 5: Self-healing stubs
Add action_hints. Build remediation dispatcher. Wire Frigate → Ollama. Wire infra → restart scripts.

---

## Changelog

### v1.0 — 2026-03-31
- Initial spec defining 2 universes, 8 domains, canonical source registry, category/severity vocabularies, notification payload contract, routing infrastructure (Slack/Gotify/Postgres), n8n naming convention, and 5-phase implementation plan.
- Designed for compatibility with NixOS domain architecture (CHARTER.md v11.1) and Heartwood business operating system.
