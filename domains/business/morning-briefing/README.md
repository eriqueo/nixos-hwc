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
| 1 | Main briefing | `claude --print` queries Calendar, JobTread, system health via MCP |
| 2 | Mail triage | `notmuch search` → `claude --print` classifies into urgent/review/noise |
| 3 | Merge | `jq` injects mail_triage into briefing.json |
| 4 | Publish | Dashboard reads via symlink; no-op if symlink exists |

Post-step-1: `generated_at` is stamped by `jq` from `date -Iseconds` (not Claude's timestamp).

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
- Google Calendar MCP — today's events

**HWC-SYS** — server health
- `hwc_monitoring_health_check` — services, containers, storage
- `hwc_mail_health` — mail system status

## Changelog

- **2026-04-07** — Upgrade dashboard with mail triage UI (expandable thread cards, action buttons, urgent/review/noise buckets). Add `jt_get_overdue_documents` tool to heartwood-mcp. Make `jt_search_jobs` searchTerm optional (allows listing all open jobs). Fix stale paths (routes.nix + old systemd unit), fix mail triage JSON parsing (remove `--output=threads`, extract JSON with sed range instead of fence strip), fix `cp` same-file error on dashboard symlink, stamp `generated_at` from shell, pass explicit date in prompt, increase timeout to 300s, reduce thread limit to 30, add debug logging on triage parse failure
