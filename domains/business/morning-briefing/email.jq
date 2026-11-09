def watchlist:
  ((.sections.today.items // []) | map($policy[0].sourceSections[.source] // .source) | unique) as $represented
  | ((.alerts // []) | map(select(.section as $section | ($represented | index($section)) == null)));

def plain:
    def sec(x): "\n== " + x + " ==\n";
    watchlist as $watch |
    "Morning Briefing — " + (.generated_at // "unknown")
    + (if ((.sections.today.items // []) | length) > 0 then
        sec("NEEDS YOU — top " + ([.sections.today.items[:5][]] | length | tostring))
        + ([.sections.today.items[:5][] |
            (if .severity == "red" then "[!] " else "[ ] " end)
            + .title + " — " + .why + " (~" + ((.effort_min // 10) | tostring) + " min)"
            + (if .url then "\n      Explore: " + .url else "" end)
            + (if .report then "\n      report ready: " + .report else "" end)]
           | join("\n"))
        + (if ((.sections.today.items | length) - 5 + (.sections.today.spillover // 0)) > 0 then
            "\n\nExplore " + (((.sections.today.items | length) - 5 + (.sections.today.spillover // 0)) | tostring)
            + " more: " + $policy[0].links.dashboard else "" end)
      else "" end)
    + (if ($watch | length) > 0 then
        sec("WATCHLIST (" + (($watch | length) | tostring) + ")")
        + ([$watch[] | "[" + .level + "] " + .message + "\n      Explore: " + $policy[0].links.dashboard] | join("\n"))
      else "\n\nNo additional watch items." end)
    + (if .sections.config_drift then
        sec("CONFIG DRIFT")
        + "reboot pending: " + ((.sections.config_drift.reboot_pending // false) | tostring)
        + " · unpushed: " + ((.sections.config_drift.unpushed_commits // 0) | tostring)
        + " · dirty: " + ((.sections.config_drift.dirty_files // 0) | tostring)
        + " · generations: " + ((.sections.config_drift.generations // 0) | tostring)
        + " · coredumps 24h: " + ((.sections.config_drift.coredumps_24h // 0) | tostring)
      else "" end)
    + (if .sections.system then
        sec("SYSTEM")
        + "services: " + ((.sections.system.services_active // 0) | tostring) + " active / "
        + ((.sections.system.services_failed // 0) | tostring) + " failed · containers: "
        + ((.sections.system.containers_running // 0) | tostring) + " running"
        + ((.sections.system.storage // []) | map("\n  " + .mount + ": " + ((.percent // 0) | tostring) + "% used, " + (.available // "?") + " free") | join(""))
        + (if .sections.backup.exit_status then
            "\n  backup: borg " + .sections.backup.exit_status
            + (if .sections.backup.postgres then " · postgres " + .sections.backup.postgres.exit_status else "" end)
          else "" end)
      else "" end)
    + (if .sections.ops then
        (.sections.ops as $o |
        (if (($o.service_failures // []) | length) > 0
          or (($o.services_down // []) | length) > 0
          or (($o.prometheus_targets_down // []) | length) > 0
          or (($o.journal_errors_top // []) | length) > 0
          or (($o.disk_forecast // []) | length) > 0 then
          sec("OVERNIGHT OPS (since " + ($o.since // "?") + ")")
          + (($o.service_failures // []) | map("\n  ! service failed: " + .service + " @ " + .time) | join(""))
          + (($o.services_down // []) | map("\n  ~ probe: " + .service + (if .down_now then " DOWN NOW" else " (" + ((.downtime_pct_24h // 0) | tostring) + "% downtime 24h)" end)) | join(""))
          + (($o.prometheus_targets_down // []) | map("\n  ~ target down: " + .job + " @ " + .instance) | join(""))
          + (($o.journal_errors_top // []) | map("\n  · journal errors: " + .unit + " ×" + (.errors | tostring)) | join(""))
          + (($o.disk_forecast // [])[:3] | map("\n  · " + .mount + " full in ~" + (.days_to_full | tostring) + "d at current growth") | join(""))
        else "" end)
        + (if (($o.nightly_builds_finished // []) | length) > 0 then
            sec("BUILT OVERNIGHT")
            + (($o.nightly_builds_finished // []) | map("  · " + .) | join("\n"))
          else "" end))
      else "" end)
    + (if (.sections.calendar.events // []) | length > 0 then
        sec("THIS WEEK")
        + ([.sections.calendar.events[] | "  " + (.date // ((.start // "") | split("T")[0]) // "")
            + " " + (if .allDay then "all-day" else ((.start // "") | split("T")[1] // "") end)
            + "  " + (.summary // "")
            + (if .location then " — " + .location else "" end)] | join("\n"))
      else "" end)
    + (if (.sections.tasks // {}) | ((.overdue // []) + (.due_today // []) + (.due_this_week // [])) | length > 0 then
        sec("TASKS")
        + ((((.sections.tasks.overdue // []) | map("  ! OVERDUE " + (.due_date // "") + "  " + .name))
          + ((.sections.tasks.due_today // []) | map("  · today  " + .name))
          + ((.sections.tasks.due_this_week // []) | map("  · " + (.due_date // "") + "  " + .name))) | join("\n"))
      else "" end)
    + (if (.sections.mail_proposals.items // []) | length > 0 then
        sec("FROM YOUR MAIL — " + ((.sections.mail_proposals.items | length) | tostring) + " proposed task(s) in list " + (.sections.mail_proposals.list // "Mail"))
        + ((.sections.mail_proposals.items | map("  ? " + (.due_date // "no date") + "  " + .name)) | join("\n"))
        + "\n  keep, move to a real list, or delete to deny (todui or tasks.hwc.iheartwoodcraft.com)"
      else "" end)
    + (if (.sections.leads.items // []) | length > 0 then
        sec("LEADS (" + ((.sections.leads.items | length) | tostring) + ")")
        + ([.sections.leads.items[] | "  " + .name
            + (if (.job_type // "") != "" then " — " + .job_type else "" end)
            + " (" + (.days_old | tostring) + "d old)"] | join("\n"))
      else "" end)
    + (if (.sections.overdue.count // 0) > 0 then
        sec("OVERDUE INVOICES — $" + ((.sections.overdue.total_amount // 0) | round | tostring))
        + ([.sections.overdue.items[] | "  $" + ((.amount // 0) | round | tostring) + "  " + (.job_name // .name)
            + (if .days_past_due then " (" + (.days_past_due | tostring) + "d past due)" else "" end)] | join("\n"))
      else "" end)
    + (if (.sections.jobs.active // []) | length > 0 then
        sec("ACTIVE JOBS (" + ((.sections.jobs.active | length) | tostring) + ")")
        + ([.sections.jobs.active[] | "  #" + (.number // "?") + " " + .name + " — " + (.phase // "?") + " / " + (.status // "?")] | join("\n"))
      else "" end)
    + (if .mail_triage then
        sec("MAIL")
        + (.mail_triage as $triage | ($triage.states // ["do", "did", "look", "junk"])
          | map(. as $state | ($triage.state_display_names[$state] // ($state | ascii_upcase))
            + ": " + (($triage.stats[$state + "_count"] // 0) | tostring)) | join(" · "))
        + (if .sections.mail.summary then " · " + .sections.mail.summary else "" end)
        + (if .mail_triage.error then "\n  triage error: " + .mail_triage.error else "" end)
        + (if ((.mail_triage.routing_rules // []) | length) > 0 then
            "\n  routing rules: " + (((.mail_triage.routing_rules | length)) | tostring) + " active"
            + (.mail_triage as $triage | ($triage.routing_rules // []) | map("\n    " + .sender + " + ‘" + .subject_contains + "’ → " + ($triage.state_display_names[.state] // (.state | ascii_upcase)) + " · " + (.domain | ascii_upcase)) | join(""))
          else "" end)
        + ((((.mail_triage | .threads_by_state).do // [])[:5]) | map("\n  ! " + (.sender // "?") + ": " + (.subject // "?") + (if .summary then "\n      " + .summary else "" end)) | join(""))
        + ((((.mail_triage | .threads_by_state).look // [])[:5]) | map("\n  · " + (.sender // "?") + ": " + (.subject // "?") + (if .summary then "\n      " + .summary else "" end)) | join(""))
      else "" end)
    + (if (.sections.refinery.counts.total // 0) > 0 then
        sec("REFINERY")
        + "action: " + ((.sections.refinery.counts.action // 0) | tostring)
        + " · active: " + ((.sections.refinery.counts.active // 0) | tostring)
        + " · hopper: " + ((.sections.refinery.counts.hopper // 0) | tostring)
        + ((((.sections.refinery | .stages).action // [])[:6]) | map("\n  ! " + (.title // .id)
            + " [" + (.label // .state // "?") + (if .pipeline and .pipeline != "untriaged" then " · " + .pipeline else "" end) + "]"
            + (if .reason then "\n      " + .reason else "" end)) | join(""))
        + ((((.sections.refinery | .stages).active // [])[:5]) | map("\n  · " + (.title // .id)
            + " [" + (.pipeline // "?") + (if .step then " · " + .step else "" end) + "]") | join(""))
      else "" end)
    + (if (.sections.agents.line // "") != "" then sec("AGENTS") + .sections.agents.line else "" end)
    + (if ((.sections.research.counts.awaiting // 0) > 0
           or ((.sections.research.lessons.themes // []) | length) > 0
           or (.sections.research.health.staleIngest // false)) then
        sec("RESEARCH")
        + (if (.sections.research.health.staleIngest // false) then
            "!! INGEST STALE — last completed run "
            + (if .sections.research.health.ingestAgeHours
               then ((.sections.research.health.ingestAgeHours | floor) | tostring) + "h ago"
               else "never" end)
            + " (expected daily). Check research-scout-arxiv.service.\n"
          else "" end)
        + ((.sections.research.counts.awaiting // 0) | tostring) + " article(s) waiting to be read"
        + (((.sections.research.queue // [])[:3]) | map("\n  · " + (.title // "?")
            + (if .tier then " [" + .tier + "]" else "" end)
            + (if .url then "\n      " + .url else "" end)) | join(""))
        + (if .sections.research.lessons then
            "\nlessons: " + ((.sections.research.lessons.kept // 0) | tostring) + " kept / "
            + ((.sections.research.lessons.skipped // 0) | tostring) + " skipped"
            + (if .sections.research.lessons.status == "below_floor"
               then " · not enough yet for themes"
               else ((.sections.research.lessons.themes // []) | map("\n  ~ " + .) | join("")) end)
          else "" end)
        + "\nreview: " + (.sections.research.url // $policy[0].links.research)
      else "" end)
    + (if .sections.website and (.sections.website | length > 0) then
        sec("WEBSITE")
        + "visitors 24h: " + ((.sections.website.visitors_24h // 0) | tostring)
        + " · pageviews 24h: " + ((.sections.website.pageviews_24h // 0) | tostring)
        + " · 7d: " + ((.sections.website.visitors_7d // 0) | tostring) + " visitors / "
        + ((.sections.website.pageviews_7d // 0) | tostring) + " views"
        + "\ncalculator leads: " + ((.sections.website.leads_24h // 0) | tostring) + " today · "
        + ((.sections.website.leads_7d // 0) | tostring) + " this week"
        + ((.sections.website.top_pages_7d // [])[:3] | map("\n  " + .url + " (" + (.views | tostring) + ")") | join(""))
        + "\nfull analytics: " + $policy[0].links.stats
      else "" end)
    + "\n\nDashboard: " + $policy[0].links.dashboard + "\n";

def html:
    # Theme = the dashboard palette verbatim (dashboard/index.html :root):
    #   bg #1d2021 · surface #282828 · border #32373c · text #d5c4a1
    #   dim #a7aaad · amber #cf995f (links) · amber-dim #b0814d
    #   red #bf616a (bg #2d2426, alert text #d08080) · warning text #fcbb74
    # Section order mirrors the dashboard grid.
    def h: tostring | @html;
    def link(u; t): "<a href=\"" + u + "\" style=\"color:#cf995f;text-decoration:none\">" + t + "</a>";
    def card(title; url; linktext; body):
      "<div style=\"background:#282828;border:1px solid #32373c;border-radius:6px;padding:14px 18px;margin:0 0 12px\">"
      + "<div style=\"font-size:11px;letter-spacing:1.5px;text-transform:uppercase;color:#a7aaad;padding-bottom:8px;border-bottom:1px solid #32373c;margin-bottom:10px\">"
      + title
      + (if url != "" then "<span style=\"float:right;text-transform:none;letter-spacing:0\">" + link(url; linktext + " &rarr;") + "</span>" else "" end)
      + "</div>" + body + "</div>";
    def item(s): "<div style=\"padding:3px 0;font-size:14px;line-height:1.45;color:#d5c4a1\">" + s + "</div>";
    def meta(s): "<span style=\"color:#a7aaad;font-size:13px\">" + s + "</span>";
    def red(s): "<span style=\"color:#bf616a;font-weight:600\">" + s + "</span>";
    def aurl(s): $policy[0].links[$policy[0].alertLinks[s] // "dashboard"] // $policy[0].links.dashboard;

    .sections as $s |
    watchlist as $watch |
    "<div style=\"margin:0;padding:18px 10px;background:#1d2021\">"
    + "<div style=\"max-width:640px;margin:0 auto;font-family:-apple-system,BlinkMacSystemFont,Roboto,Helvetica,Arial,sans-serif\">"

    + "<div style=\"padding:6px 2px 16px;text-align:center;border-bottom:1px solid #32373c;margin-bottom:14px\">"
    + "<div style=\"font-size:12px;letter-spacing:3px;text-transform:uppercase;color:#b0814d\">Heartwood Briefing</div>"
    + "<div style=\"font-size:22px;font-weight:700;color:#cf995f;margin-top:4px\">" + ($slot|h) + " &middot; " + ((.generated_at // "" | split("T")[0])|h) + "</div>"
    + "<div style=\"font-size:13px;color:#a7aaad;margin-top:4px\">" + link($policy[0].links.dashboard; "open dashboard") + "</div></div>"

    + (if ($s.today.items // []) | length > 0 then
        card("Needs you &middot; top " + (([$s.today.items[:5][]] | length | tostring)|h); $policy[0].links.dashboard; "explore all";
          ($s.today.items[:5] | map(
            item((if .severity == "red" then red("!") else meta("&middot;") end) + " "
              + (if .url then link(.url; ((.title // "item")|h)) else ((.title // "item")|h) end)
              + "<br><span style=\"color:#a7aaad;font-size:13px;padding-left:14px\">" + ((.why // "")|h) + "</span>")) | join(""))
          + (if (($s.today.items | length) - 5 + ($s.today.spillover // 0)) > 0 then
              item(link($policy[0].links.dashboard; "Explore " + ((($s.today.items | length) - 5 + ($s.today.spillover // 0))|tostring) + " more &rarr;")) else "" end))
      else card("Needs you"; $policy[0].links.dashboard; "dashboard"; item("No action needed.")) end)

    + (if ($watch | length) > 0 then
        ($watch | map(
          (if .level == "critical" then ["#2d2426", "#bf616a", "#d08080"] else ["#2d2a24", "#cf995f", "#fcbb74"] end) as $c |
          "<div style=\"background:" + $c[0] + ";border:1px solid " + $c[1] + ";color:" + $c[2] + ";border-radius:6px;padding:9px 12px;margin:0 0 8px;font-size:13.5px;line-height:1.4\">"
          + "<strong>" + ((.section // "")|h) + "</strong> &middot; " + ((.message // "")|h)
          + " &nbsp;" + link(aurl(.section // ""); "view &rarr;")
          + "</div>") | join(""))
      else "" end)

    + (if ($s.calendar.events // []) | length > 0 then
        card("Calendar"; ""; "";
          ($s.calendar.events | map(
            item(meta(((.date // ((.start // "") | split("T")[0]))|h)
                + " " + (if .allDay then "all-day" else (((.start // "") | split("T")[1] // "")|h) end)) + " &nbsp;"
              + (.summary|h)
              + (if (.location // "") | startswith("http") then " &middot; " + link(.location; "join link &rarr;")
                 elif (.location // "") != "" then " " + meta((.location|h)) else "" end))) | join("")))
      else "" end)

    + (if .mail_triage then
        card("Mail"; $policy[0].links.dashboard; "workflow";
          item((.mail_triage as $triage | ($triage.states // ["do", "did", "look", "junk"])
            | map(. as $state | (($triage.state_display_names[$state] // ($state | ascii_upcase)) | h)
              + " " + (($triage.stats[$state + "_count"] // 0) | tostring)) | join(" &middot; "))
            + (if $s.mail.summary then " &middot; " + meta(($s.mail.summary|h)) else "" end))
          + (if .mail_triage.error then item(red("triage error: " + (.mail_triage.error|h))) else "" end)
          + (if ((.mail_triage.routing_rules // []) | length) > 0 then
              item(meta((((.mail_triage.routing_rules | length)) | tostring) + " active routing rule(s)"))
              + (.mail_triage as $triage | ($triage.routing_rules // []) | map(
                  item(meta((.sender|h) + " + &lsquo;" + (.subject_contains|h) + "&rsquo; &rarr; " + (($triage.state_display_names[.state] // (.state | ascii_upcase))|h) + " &middot; " + ((.domain | ascii_upcase)|h)))) | join(""))
            else "" end)
          + ((((.mail_triage | .threads_by_state).do // [])[:5]) | map(
              item(red("!") + " " + ((.sender // "?")|h) + ": " + ((.subject // "?")|h)
                + (if .summary then "<br>" + meta((.summary|h)) else "" end))) | join(""))
          + ((((.mail_triage | .threads_by_state).look // [])[:5]) | map(
              item(meta("&middot;") + " " + ((.sender // "?")|h) + ": " + ((.subject // "?")|h)
                + (if .summary then "<br>" + meta((.summary|h)) else "" end))) | join("")))
      else "" end)

    + (if ($s.refinery.counts.total // 0) > 0 then
        card("Refinery"; ($s.refinery.url // $policy[0].links.refinery); "board";
          item("action " + ((($s.refinery.counts.action // 0)|tostring)|h)
            + " &middot; active " + ((($s.refinery.counts.active // 0)|tostring)|h)
            + " &middot; hopper " + ((($s.refinery.counts.hopper // 0)|tostring)|h))
          + ((($s.refinery | .stages).action // [])[:6] | map(
              item((if .state == "failed" then red("&#10007;") else red("!") end) + " "
                + (if .url then link(.url; ((.title // .id)|h)) else ((.title // .id)|h) end)
                + " " + meta("[" + ((.label // .state // "?")|h) + (if .pipeline and .pipeline != "untriaged" then " &middot; " + (.pipeline|h) else "" end) + "]")
                + (if .reason then "<br><span style=\"color:#a7aaad;font-size:13px;padding-left:14px\">" + (.reason|h) + "</span>" else "" end))) | join(""))
          + ((($s.refinery | .stages).active // [])[:5] | map(
              item(meta("&middot;") + " "
                + (if .url then link(.url; ((.title // .id)|h)) else ((.title // .id)|h) end)
                + " " + meta("[" + ((.pipeline // "?")|h) + (if .step then " &middot; " + (.step|h) else "" end) + "]"))) | join("")))
      else "" end)

    + (if ($s.tasks // {}) | ((.overdue // []) + (.due_today // []) + (.due_this_week // [])) | length > 0 then
        card("Tasks"; $policy[0].links.dashboard; "dashboard";
          (($s.tasks.overdue // []) | map(item(red("OVERDUE") + " " + meta(((.due_date // "")|h)) + " &nbsp;" + (.name|h))) | join(""))
          + (($s.tasks.due_today // []) | map(item("<strong>today</strong> &nbsp;" + (.name|h))) | join(""))
          + (($s.tasks.due_this_week // []) | map(item(meta(((.due_date // "")|h)) + " &nbsp;" + (.name|h))) | join("")))
      else "" end)

    + (if ($s.leads.items // []) | length > 0 then
        card("New Leads (" + (($s.leads.items | length | tostring)|h) + ")"; $policy[0].links.jobtread; "JobTread";
          ($s.leads.items | map(
            item((if .url then link(.url; (.name|h)) else (.name|h) end)
              + (if (.job_type // "") != "" then " " + meta((.job_type|h)) else "" end)
              + " " + meta(((.days_old|tostring)|h) + "d old"))) | join("")))
      else "" end)

    + (if ($s.overdue.count // 0) > 0 then
        card("Overdue Invoices &middot; $" + ((($s.overdue.total_amount // 0) | round | tostring)|h); $policy[0].links.jobtread; "JobTread";
          ($s.overdue.items | map(
            item("<strong style=\"color:#fcbb74\">$" + (((.amount // 0) | round | tostring)|h) + "</strong> &nbsp;"
              + (if .url then link(.url; ((.job_name // .name)|h)) else ((.job_name // .name)|h) end)
              + (if .days_past_due then " " + meta(((.days_past_due|tostring)|h) + "d past due") else "" end))) | join("")))
      else "" end)

    + (if ($s.jobs.active // []) | length > 0 then
        card("Active Jobs (" + (($s.jobs.active | length | tostring)|h) + ")"; $policy[0].links.jobtread; "JobTread";
          ($s.jobs.active | map(
            item(meta("#" + ((.number // "?")|h)) + " &nbsp;"
              + (if .url then link(.url; (.name|h)) else (.name|h) end)
              + " " + meta(((.phase // "?")|h) + " / " + ((.status // "?")|h)))) | join("")))
      else "" end)

    + (if $s.system then
        card("System"; $policy[0].links.grafana; "Grafana";
          item(((($s.system.services_active // 0)|tostring)|h) + " services &middot; "
            + ((($s.system.services_failed // 0)|tostring)|h) + " failed &middot; "
            + ((($s.system.containers_running // 0)|tostring)|h) + " containers")
          + (($s.system.failed_units // []) | map(item(red("&#10007; " + (.|h)))) | join(""))
          + (($s.system.storage // []) | map(item((.mount|h) + " " + meta(((.percent // 0)|tostring) + "% used"))) | join(""))
          + (if $s.backup.exit_status then
              item("backup: borg " + (($s.backup.exit_status // "?")|h)
                + (if $s.backup.postgres then " &middot; postgres " + (($s.backup.postgres.exit_status // "?")|h) else "" end))
            else "" end))
      else "" end)

    + (if $s.ops then ($s.ops as $o |
        (($o.service_failures // []) | length) as $nsvc |
        (($o.services_down // []) | length) as $nkuma |
        (($o.journal_errors_top // []) | length) as $nerr |
        (($o.prometheus_targets_down // []) | length) as $ndown |
        (($o.nightly_builds_finished // []) | length) as $nnb |
        card("Overnight Ops &middot; since " + ((($o.since // "")[5:16])|h); $policy[0].links.serviceHealth; "Service Health";
          (if ($nsvc + $nkuma + $nerr + $ndown + $nnb) == 0 then item(meta("Quiet night — no failures, no probe drops, no errors")) else
            (($o.service_failures // []) | map(item(red("&#10007; " + (.service|h)) + " " + meta("failed @ " + ((.time // "")[11:16])))) | join(""))
            + (($o.services_down // []) | map(item(
                (if .down_now then red("&#10007; " + (.service|h)) + " " + meta("down now")
                 else "~ " + (.service|h) + " " + meta(((.downtime_pct_24h // 0)|tostring) + "% downtime 24h") end))) | join(""))
            + (($o.prometheus_targets_down // []) | map(item("~ target down: " + (.job|h) + " " + meta((.instance // "")|h))) | join(""))
            + (($o.journal_errors_top // []) | map(item((.unit|h) + " " + meta(((.errors|tostring)|h) + " journal errors"))) | join(""))
            + (if $nnb > 0 then item("<strong>Built overnight:</strong> " + (($o.nightly_builds_finished // []) | map(h) | join(", "))) else "" end)
          end)
          + (($o.disk_forecast // [])[:3] | map(item((.mount|h) + " " + meta("full in ~" + ((.days_to_full|tostring)|h) + "d at current growth"))) | join(""))))
      else "" end)

    + (if $s.weather and $s.weather.current_temp_f != null then
        card("Weather"; ""; "";
          item(((($s.weather.current_temp_f | round | tostring))|h) + "&deg; now &middot; "
            + (if $s.weather.high_f != null and $s.weather.low_f != null then
                ((($s.weather.high_f | round | tostring))|h) + "&deg;/" + ((($s.weather.low_f | round | tostring))|h) + "&deg; &middot; " else "" end)
            + (($s.weather.conditions // "")|h)
            + " &middot; " + meta(((($s.weather.precipitation_chance // 0)|tostring)|h) + "% precip &middot; "
              + ((($s.weather.wind_mph // 0)|tostring)|h) + " mph wind"))
          + (if $s.weather.outdoor_work_ok == false then item(red("&#9888; not ideal for outdoor work")) else "" end))
      else "" end)

    + (if $s.weekly_snapshot and ($s.weekly_snapshot | length) > 0 then
        card("Weekly Snapshot"; ""; "";
          item("active jobs " + (($s.weekly_snapshot.active_job_count // "&mdash;")|tostring)
            + " &middot; leads this week " + (($s.weekly_snapshot.leads_received_this_week // "&mdash;")|tostring)
            + " &middot; outstanding $" + ((($s.weekly_snapshot.invoices_outstanding_amount // 0) | round | tostring)|h)
            + " (" + (($s.weekly_snapshot.invoices_outstanding // 0)|tostring) + ")"))
      else "" end)

    + (if $s.website and ($s.website | length > 0) then
        card("Website"; $policy[0].links.stats; "Umami";
          item(((($s.website.visitors_24h // 0)|tostring)|h) + " visitors 24h &middot; "
            + ((($s.website.visitors_7d // 0)|tostring)|h) + " visitors / "
            + ((($s.website.pageviews_7d // 0)|tostring)|h) + " views 7d")
          + item("calculator leads: " + ((($s.website.leads_24h // 0)|tostring)|h) + " today &middot; "
            + ((($s.website.leads_7d // 0)|tostring)|h) + " this week")
          + (($s.website.top_pages_7d // [])[:3] | map(item(meta((.url|h) + " — " + ((.views|tostring)|h) + " views"))) | join("")))
      else "" end)

    + "<div style=\"text-align:center;padding:10px 0 4px;font-size:12px;color:#a7aaad\">"
    + link($policy[0].links.dashboard; "dashboard") + " &nbsp;&middot;&nbsp; " + link($policy[0].links.grafana; "grafana")
    + " &nbsp;&middot;&nbsp; " + link($policy[0].links.serviceHealth; "service health") + " &nbsp;&middot;&nbsp; " + link($policy[0].links.jobtread; "jobtread")
    + " &nbsp;&middot;&nbsp; " + link($policy[0].links.stats; "analytics") + " &nbsp;&middot;&nbsp; " + link($policy[0].links.refinery; "refinery")
    + "</div></div></div>";

if $policy[0].schemaVersion != 1 then error("unsupported briefing view policy")
elif $format == "plain" then plain elif $format == "html" then html else error("unknown email format") end
