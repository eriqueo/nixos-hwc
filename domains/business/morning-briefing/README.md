# Morning Briefing

Daily automated briefing for Heartwood Craft ops. Runs as a systemd timer at 6am MT, compiles data from MCP servers and mail into a single JSON file served by Caddy.

Dashboard: `https://hwc.ocelot-wahoo.ts.net:16443`

## Structure

```
index.nix              # NixOS module: systemd service + timer
run.sh                 # 4-step pipeline (see below)
CLAUDE.md              # Agent prompt: data schema, alert rules, MCP sources
prompts/
  mail-triage.txt      # Mail triage prompt: bucket rules, known senders
dashboard/
  index.html           # Static SPA dashboard (dark theme, pull-to-refresh)
  briefing.json        # Symlink → ../output/briefing.json
output/
  briefing.json        # Final merged output (main + mail triage)
  mail-triage.json     # Step 2 output before merge
logs/
  run.log              # Rolling log (last 100 lines)
```

## Pipeline

| Step | What | How |
|------|------|-----|
| 0 | Pre-flight | Check claude binary exists at expected path |
| 1 | Main briefing | `claude --print` queries Calendar, JobTread, system health, backup, weather via MCP |
| 2 | Mail triage | `notmuch search` → `claude --print` classifies into urgent/review/noise |
| 3 | Merge | `jq` injects mail_triage into briefing.json |
| 4 | Publish | Dashboard reads via symlink; no-op if symlink exists |

Post-step-1: `generated_at` is stamped by `jq` from `date -Iseconds` (not Claude's timestamp). Validation checks for `sections.calendar` and `sections.jobs` keys. Steps 1 and 2 log elapsed seconds for performance tracking.

## Sections

| Section | Data Source | MCP Tool | Dashboard Location |
|---------|------------|----------|-------------------|
| Calendar | iCloud via khal | `hwc_calendar_list` (range=week) | Top |
| Weather | Web search | N/A (web search) | After Calendar |
| Tasks | JobTread | `jt_get_tasks` | After Weather |
| Jobs | JobTread | `jt_search_jobs` | After Tasks |
| Weekly Snapshot | JobTread (aggregated) | `jt_search_jobs`, `jt_get_documents` | After Jobs |
| Leads | JobTread | `jt_search_jobs` (filtered) | After Snapshot |
| Overdue Docs | JobTread | `jt_get_overdue_documents` | After Leads |
| Recent Documents | JobTread | `jt_get_documents` | After Overdue |
| System Health | HWC server | `hwc_monitoring_health_check` | After Recent Docs |
| Backup | Borg via HWC | `hwc_storage_status` | After System |
| Mail Triage | notmuch + Claude | Step 2 pipeline | After Backup |
| Comms | Quo/OpenPhone | Placeholder (future) | After Mail |

## NixOS Options

- `hwc.business.morningBriefing.enable` — enable the service + timer
- `hwc.business.morningBriefing.onCalendar` — systemd calendar expression (default: `*-*-* 06:00:00`)

Service runs as `eric`, hardened with `ProtectSystem=strict`, 300s timeout.

## Manual Run

```bash
sudo systemctl start morning-briefing.service
journalctl -u morning-briefing.service -f
```

## MCP Tools Used

The briefing relies on tools from two MCP backends (both via `hwc-sys-mcp` gateway):

**HWC-JT (heartwood-mcp)** — JobTread data at `/opt/business/heartwood-mcp/`
- `jt_search_jobs` — list all open jobs (`status: "open"`, searchTerm optional)
- `jt_get_overdue_documents` — docs past due with outstanding balances
- `jt_get_tasks` — tasks due today/this week/overdue for active jobs
- `jt_get_documents` — estimates, invoices, change orders (last 48h)

**HWC-SYS** — server health
- `hwc_monitoring_health_check` — services, containers, storage
- `hwc_mail_health` — mail system status
- `hwc_storage_status` — Borg backup and disk usage
- `hwc_calendar_list` (range=week) — iCloud calendar via khal

## Troubleshooting

**Claude CLI not found**: Step 0 pre-flight checks for the binary at `/etc/profiles/per-user/eric/bin/claude`. If missing, the service logs `FATAL` and writes an error briefing.json. Ensure `claude-code` is in the NixOS user packages.

**MCP server unreachable**: The agent adds an alert for any data source that fails. Check `hwc-sys-mcp` gateway status with `systemctl status hwc-sys-mcp`. Individual tool failures produce partial briefings (other sections still render).

**jq parse failures**: Step 3 merge can fail if briefing.json or mail-triage.json contains invalid JSON. Check `logs/run.log` for the specific jq error. The mail triage step includes a JSON extraction fallback (sed range) to handle markdown fences in Claude output.

**Stale briefing**: Dashboard shows "stale" in red if briefing is >2h old. Check timer status with `systemctl list-timers morning-briefing.timer`. Manual trigger: `sudo systemctl start morning-briefing.service`.

**Mail triage empty**: If notmuch returns 0 threads, an empty triage is written (not an error). Check `notmuch count tag:inbox AND tag:unread` to verify mail state. Mail sync issues: check `systemctl status mbsync-eric.timer`.

## Changelog

- **2026-04-09** — Add backup status, tasks due, and recent documents sections. Expand mail triage with known noise senders (nextdoor, quora, zillow, angi, thumbtack, yelp) and review senders (Quo, Stripe, QuickBooks, JobTread). Add reasoning rules for 'sent' tag and flagged+work threads. Dashboard: add backup row, collapsible tasks view, recent docs with type badges, footer with section count, keyboard 'r' refresh, fade-in animation, prominent day-of-week header. Pipeline: add pre-flight check, post-step-1 validation, per-step timing. New alert rules: backup errors, stale backups, overdue tasks, incomplete tasks after 3pm
- **2026-04-07** — Upgrade dashboard with mail triage UI (expandable thread cards, action buttons, urgent/review/noise buckets). Add `jt_get_overdue_documents` tool to heartwood-mcp. Make `jt_search_jobs` searchTerm optional (allows listing all open jobs). Fix stale paths (routes.nix + old systemd unit), fix mail triage JSON parsing (remove `--output=threads`, extract JSON with sed range instead of fence strip), fix `cp` same-file error on dashboard symlink, stamp `generated_at` from shell, pass explicit date in prompt, increase timeout to 300s, reduce thread limit to 30, add debug logging on triage parse failure
