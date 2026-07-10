# Morning Briefing

Daily automated briefing for Heartwood Craft ops. Runs as a systemd timer at 6am MT, gathers data into a single JSON file served by Caddy and read by the workbench `brief` hub (via the `hwc_morning_brief` MCP tool).

**Data gathering is local CLI, not MCP.** The 6am run is headless, and `~/.claude`
runs `defaultMode=acceptEdits` — which does NOT auto-approve Bash or MCP tool
calls. So an agent asked to gather via MCP gets every call *permission-denied*
(this produced briefings full of bogus `[CRITICAL] … permission denied` alerts).
`run.sh` therefore gathers system/mail/calendar directly in bash (`systemctl`,
`df`, `notmuch`, `khal`) as `eric`, who has full file/CLI access. Claude is used
ONLY for the mail-triage *reasoning* in Step 2 (no tool calls). **JobTread
sections (jobs/leads/tasks/overdue/docs) are placeholders** pending a local data
source — see "JobTread follow-up" below.

Dashboard: `https://hwc-server.ocelot-wahoo.ts.net:16443`

## Structure

```
index.nix              # NixOS module: systemd service + timer
run.sh                 # 5-step pipeline (see below)
gather-live.mjs        # Step 1b: JobTread jobs/leads/overdue + CalDAV tasks via
                       #   the local MCP gateway (:6200/mcp, StreamableHTTP)
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
  mail-triage-raw.log  # Full raw Claude output from the last FAILED triage parse
```

## Pipeline

| Step | What | How |
|------|------|-----|
| 0 | Pre-flight | Check claude binary exists (still needed for Step 2 mail triage) |
| 1 | Local gather | bash assembles `briefing.json` directly: `systemctl` (services incl. failed unit NAMES, podman-* container count, borg backup unit), `df` (storage), `notmuch` (mail), `khal`→`jq` (calendar, 7-day window), `curl` open-meteo (weather). Alerts computed locally. **No Claude, no MCP.** |
| 1b | Live gather | `node gather-live.mjs` → local MCP gateway (`:6200/mcp`, plain JSON-RPC, no permissions): `jt_jobs` (jobs + leads + weekly snapshot), `jt_documents list_overdue` (overdue invoices), `hwc_tasks_list` (CalDAV tasks). Best-effort: per-section failures become dashboard alerts, placeholders kept. |
| 2 | Mail triage | `notmuch search` → `claude --print` classifies into urgent/review/noise (pure reasoning, no tool calls). JSON extracted with node (direct → fenced → brace-span); full raw saved to `logs/mail-triage-raw.log` on parse failure. |
| 2b | Persist buckets | `notmuch tag` stamps each classified thread with `triage/<bucket>` (removes other `triage/*`) |
| 3 | Merge | `jq` injects mail_triage into briefing.json |
| 4 | Publish | Dashboard reads via symlink; no-op if symlink exists |
| 5 | Email | Plain-text render (alerts, calendar, tasks, leads, overdue invoices, jobs, mail triage w/ summaries, website) via msmtp from office@. **Only sent on the pre-9am run** — midday/evening timer firings refresh the dashboard without re-emailing (`FORCE_EMAIL=1` overrides). |

Step 1 builds `briefing.json` atomically (`.tmp` → validate with `jq empty` → `mv`); on any failure the previous briefing is kept. `generated_at` is stamped from `date -Iseconds`. The calendar is parsed with `jq` (NOT `python3`, which is not on the unit PATH — the old `python3` injector silently failed).

### JobTread / tasks data (Step 1b)

Done 2026-07-08 — `gather-live.mjs` implements the follow-up this section used
to describe: it speaks StreamableHTTP JSON-RPC to the local gateway and fills
`sections.{jobs,leads,overdue,tasks,weekly_snapshot}`. Notes:

- **tasks** come from `hwc_tasks_list` (Radicale CalDAV — Eric's real
  reminders), NOT JobTread: JT tasks for this org are template groups with no
  due dates, while the CalDAV store is what todui/Apple Reminders show.
- `weekly_snapshot.estimates_sent_this_week` stays `null` (renders "—"):
  `jt_documents list` has no created-since filter and returns oldest-first, so
  a cheap "this week" query isn't available.
- `recent_documents` stays empty for the same reason.
- Every job/lead/invoice carries a `url` → `https://app.jobtread.com/jobs/<id>`
  so the dashboard can deep-link.

### Tag-backed triage buckets (persisted moves)

The triage bucket (urgent/review/noise) is a **notmuch tag** `triage/<bucket>`, not
just a position in the cached JSON. This is what lets the workbench Mail-triage
kanban "move between columns" PERSIST across a refresh:

- **Step 2b** (this pipeline) writes the daily baseline: each classified thread is
  tagged `triage/<bucket>` (other `triage/*` removed first).
- The **workbench** moves a card by calling `hwc_mail action=tag tag_action=set-triage
  triage=<bucket>` on the gateway, which replaces the `triage/*` tag set.
- **`hwc_mail_triage`** re-buckets the cached threads by their *live* `triage/*` tag at
  read time, so a move shows up on the next board refresh without re-running the briefing.

The bucket→tag mapping is owned in **one place**: `TRIAGE_BUCKETS` / `triageTag()` in
`domains/system/mcp/src/src/tools/mail.ts`. The bucket names here (`urgent review noise`
in Step 2b) and in `mail-triage.ts` must stay in lockstep with it.

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

**HWC-JT (jt-mcp)** — JobTread data at `/opt/business/jt-mcp/`
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

- **2026-07-09b** — **HTML email with per-section deep links.** Step 5 now
  sends multipart/alternative: a styled HTML part (cards, colored alert boxes)
  where every section header links to the system it reports on — System→
  Grafana, Overnight Ops→Uptime Kuma, Leads/Invoices/Jobs→JobTread (each item
  deep-links to its job), Website→Umami, Mail/Tasks→dashboard, alerts carry a
  per-section "view" link — plus a footer link row. The plain-text render
  rides along as the fallback part (and stays notmuch-searchable). Degrades
  to plain-only with a logged WARN if the jq HTML render fails. Gotchas hit:
  `label` is a reserved jq keyword; jq array literals take commas not
  semicolons; no single quotes inside the bash-single-quoted jq program.
- **2026-07-09** — **Overnight-ops digest + alert-fatigue pass.** New
  `sections.ops` gathered in Step 1 from data already on the box, windowed
  to "since yesterday 17:00": **(1)** service-failure EVENTS from
  `/var/log/hwc/notifications/service-failures.log` (a 2am crash→auto-restart
  is invisible to the live `systemctl --failed` snapshot); **(2)** Uptime Kuma
  probe failures deduped per monitor (journal `SYSLOG_IDENTIFIER=uptime-kuma`);
  **(3)** top-5 journal error sources (catches silent crash-loops like the
  vdirsyncer every-15-min failure); **(4)** Prometheus `up==0` targets +
  disk days-to-full forecast (`deriv` over 24h); **(5)** nightly-builds cards
  landed in `_finished/` overnight. Each feeds a dashboard "Overnight Ops"
  tile, email section, and warning alerts (critical if a disk fills <14d).
  Also: **postgres backup** unit status next to borg (+critical alert on
  failure); **mail unread delta** vs previous run via `output/.state.json`
  (absolute "1374 unread" is invisible; the movement isn't); **config-drift
  alert grace** — only fires once HEAD↔deployed divergence has persisted 12h
  (script-only commits no longer cry wolf until the next rebuild); **subject
  slot-stamped** (Morning/Midday/Evening); **lead alerts split** — 2–14d leads
  named as "needs first touch", >14d collapsed to one backlog line suggesting
  Closed Lost review (naming the same four people every morning trains the
  alert to be ignored). `estimates_sent_this_week` stays null: jt_documents
  has no created-since filter or sort, and jt-mcp at /opt/business is a
  deployed copy, not a repo — needs an upstream jt-mcp change. Comms stays
  parked: no Quo/OpenPhone API secret exists on the box. Unit PATH gains
  `findutils` (nightly-builds mtime scan). — unit PATH: added `gawk` + `gnugrep` (run.sh:78 uses `awk`,
  :143 uses `grep`; neither is in coreutils — the first post-deploy timer run
  died with "awk: command not found").
- **2026-07-08b** — **Deploy fixes from live verification.** (1) `jt_jobs`
  search `limit: 100` → `50`: JobTread's Pave API rejects the query above
  ~size 50 with the nested JOB_FIELDS as `HTTP 413` (query complexity, not
  body bytes) — this killed both jobs AND leads sections. (2) `gatherTasks`
  read `data.items[].label` but `hwc_tasks_list` returns `data.tasks[].summary`
  — overdue tasks were always empty. (3) `is_test` now also matches the
  account name and a `TT-` job prefix ("TT-Full Kitchen Remodel" / "Token Test
  Client"), and leads exclude test jobs.
- **2026-07-08** — **Usability pass: real data + drill-down.** The dashboard was
  rendering placeholders as if they were data (0 jobs, 0 leads, $0 outstanding,
  "No tasks", weather "not gathered", backup UNKNOWN, containers literally
  "undefined") while $9.3k of overdue invoices, 2 stale leads, 3 overdue tasks
  and a week of calendar events existed in the sources. Changes: **(1) Step 1b**
  `gather-live.mjs` fills jobs/leads/overdue/tasks/weekly-snapshot from the
  local MCP gateway; **(2) Step 1** now also gathers weather (open-meteo),
  borg backup unit status, podman container count, failed service *names*, and
  a 7-day calendar window; **(3) mail triage** JSON extraction rewritten (node:
  direct → fenced → brace-span; the old sed line-range was the recurring
  "invalid JSON from claude") with full raw output saved on failure; **(4)
  email** fixed — `.mail_triage.urgent` → `.buckets.urgent` (the reason the
  email lost its mail summary), calendar fields fixed, tasks/leads/overdue/jobs
  sections added, only sends on the pre-9am run; **(5) dashboard** — day-grouped
  week calendar, JobTread deep links on jobs/leads/invoices, Grafana link,
  failed-unit names, honest empty states ("Nothing overdue" vs silent absence),
  comms tile hidden while sourceless, null-safe containers/estimates; **(6)
  timer** — profiles/business adds 12:00/17:00 dashboard-refresh runs
  (`onCalendar` now accepts a list), service timeout 300→420s.
- **2026-06-27** — **Step 1 no longer uses Claude/MCP.** The headless 6am run can't get tool-permission approvals (`~/.claude` `defaultMode=acceptEdits` doesn't cover Bash/MCP), so every MCP gather was auto-denied → briefings full of bogus `[CRITICAL] permission denied` alerts. Rewrote Step 1 to gather system/mail/calendar directly in bash (`systemctl`/`df`/`notmuch`/`khal`→`jq`), compute alerts locally, and assemble `briefing.json` atomically. Fixed the calendar injector (`python3` → `jq`; python3 isn't on the unit PATH). JobTread sections are placeholders pending a local source (see "JobTread follow-up"). Claude is kept only for Step 2 mail-triage reasoning. Deploy = `git pull` on the server + a manual run (run.sh is read from the live repo path; no nixos rebuild).
- **2026-04-12** — Update tool references for MCP consolidation: `hwc_calendar_week`→`hwc_calendar_list` (range=week), `hwc_storage_backup_status`→`hwc_storage_status`. Rename heartwood-mcp→jt-mcp in docs.
- **2026-04-09** — Add backup status, tasks due, and recent documents sections. Expand mail triage with known noise senders (nextdoor, quora, zillow, angi, thumbtack, yelp) and review senders (Quo, Stripe, QuickBooks, JobTread). Add reasoning rules for 'sent' tag and flagged+work threads. Dashboard: add backup row, collapsible tasks view, recent docs with type badges, footer with section count, keyboard 'r' refresh, fade-in animation, prominent day-of-week header. Pipeline: add pre-flight check, post-step-1 validation, per-step timing. New alert rules: backup errors, stale backups, overdue tasks, incomplete tasks after 3pm
- **2026-04-07** — Upgrade dashboard with mail triage UI (expandable thread cards, action buttons, urgent/review/noise buckets). Add `jt_get_overdue_documents` tool to heartwood-mcp. Make `jt_search_jobs` searchTerm optional (allows listing all open jobs). Fix stale paths (routes.nix + old systemd unit), fix mail triage JSON parsing (remove `--output=threads`, extract JSON with sed range instead of fence strip), fix `cp` same-file error on dashboard symlink, stamp `generated_at` from shell, pass explicit date in prompt, increase timeout to 300s, reduce thread limit to 30, add debug logging on triage parse failure
