/**
 * hwc_morning_brief — rich morning briefing tool.
 *
 * Reads the structured briefing.json written daily (6am MT) by the
 * morning-briefing.service Claude-CLI agent and reshapes it for the workbench
 * "brief" tile (greeting+summary+highlights inline) and detail modal (body).
 *
 * Coded defensively: the agent's output may drift from its documented schema,
 * so every section is optional — missing/malformed → skipped, never throws.
 * Mirrors the sibling tools' "unavailable" style rather than failing.
 */

import { readFile } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";

const BRIEFING_PATH =
  "/home/eric/.nixos/domains/business/morning-briefing/output/briefing.json";

/** ~26h: a briefing older than this means the 6am timer likely didn't run. */
const STALE_AFTER_MS = 26 * 60 * 60 * 1000;

// ── tiny defensive helpers ────────────────────────────────────────────────
function asObj(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}
function asArr(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}
function asStr(v: unknown): string {
  return v == null ? "" : String(v);
}
function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}
/** First non-empty string among the given keys of an object. */
function pick(o: Record<string, unknown>, ...keys: string[]): string {
  for (const k of keys) {
    const s = asStr(o[k]).trim();
    if (s) return s;
  }
  return "";
}

/** Render an unknown list item into a one-line label, trying common field names. */
function itemLine(item: unknown): string {
  if (item == null) return "";
  if (typeof item === "string") return item.trim();
  if (typeof item !== "object") return String(item);
  const o = item as Record<string, unknown>;
  const title = pick(o, "summary", "title", "subject", "name", "description", "message");
  const when = pick(o, "startTime", "start", "time", "due", "date", "date_relative");
  const who = pick(o, "from_name", "company", "client", "customer", "source");
  const amount = num(o["amount"] ?? o["total_amount"] ?? o["value"]);
  const parts: string[] = [];
  if (when) parts.push(when);
  if (title) parts.push(title);
  if (who && who !== title) parts.push(`(${who})`);
  if (amount != null) parts.push(`$${amount.toLocaleString()}`);
  const line = parts.join(" ").trim();
  return line || JSON.stringify(o);
}

function bullets(items: unknown[], max = 50): string[] {
  return items.slice(0, max).map(itemLine).filter(Boolean);
}

export function morningBriefTool(): ToolDef {
  return {
    name: "hwc_morning_brief",
    description:
      "Rich morning briefing. Reads the structured briefing.json produced daily at 6am MT " +
      "(calendar, jobs, leads, overdue, system, mail, weather, comms, weekly snapshot, backup, " +
      "tasks, recent documents, plus alerts and mail triage) and returns it shaped for the " +
      "workbench brief tile (greeting/summary/highlights inline) and detail modal (full body). " +
      "Every section is optional; a missing or stale briefing is flagged rather than failing.",
    inputSchema: { type: "object", properties: {} },
    handler: async (): Promise<ToolResult> => {
      let raw: string;
      try {
        raw = await readFile(BRIEFING_PATH, "utf8");
      } catch {
        return {
          status: "error",
          message: "Morning briefing unavailable — briefing.json not found",
          error: `Could not read ${BRIEFING_PATH}`,
          error_type: "NOT_FOUND",
          suggestion: "Check the morning-briefing.service timer ran; it writes briefing.json at 6am MT.",
          view: contract("text", "Morning Briefing", {
            greeting: "Morning Briefing — unavailable",
            summary: "briefing.json not found — the 6am briefing may not have run yet.",
            highlights: [],
            body: "No briefing data is available. The `morning-briefing.service` timer writes the briefing each morning at 6am MT.",
          }, { source: "hwc_morning_brief" }),
        };
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(raw);
      } catch {
        return {
          status: "error",
          message: "Morning briefing unavailable — briefing.json is not valid JSON",
          error: "JSON parse failed",
          error_type: "INTERNAL_ERROR",
          view: contract("text", "Morning Briefing", {
            greeting: "Morning Briefing — unavailable",
            summary: "briefing.json could not be parsed.",
            highlights: [],
            body: "The briefing file exists but is not valid JSON.",
          }, { source: "hwc_morning_brief" }),
        };
      }

      const root = asObj(parsed);
      const generated_at = asStr(root["generated_at"]);
      const sections = asObj(root["sections"]);
      const alerts = asArr(root["alerts"]);
      const mailTriage = asObj(root["mail_triage"]);

      // ── date + freshness ────────────────────────────────────────────────
      let dateLabel = "today";
      let staleNote = "";
      if (generated_at) {
        const ts = Date.parse(generated_at);
        if (!Number.isNaN(ts)) {
          dateLabel = new Date(ts).toLocaleDateString("en-US", {
            weekday: "long", month: "long", day: "numeric", timeZone: "America/Denver",
          });
          const age = Date.now() - ts;
          if (age > STALE_AFTER_MS) {
            const hours = Math.round(age / 3_600_000);
            staleNote = ` ⚠ STALE briefing (${hours}h old)`;
          }
        }
      }

      // ── pull section shapes ─────────────────────────────────────────────
      const calendar = asObj(sections["calendar"]);
      const jobs = asObj(sections["jobs"]);
      const leads = asObj(sections["leads"]);
      const overdue = asObj(sections["overdue"]);
      const system = asObj(sections["system"]);
      const mail = asObj(sections["mail"]);
      const weather = asObj(sections["weather"]);
      const comms = asObj(sections["comms"]);
      const weekly = asObj(sections["weekly_snapshot"]);
      const backup = asObj(sections["backup"]);
      const tasks = asObj(sections["tasks"]);
      const recentDocs = asObj(sections["recent_documents"]);

      const events = asArr(calendar["events"]);
      const dueToday = asArr(tasks["due_today"]);
      const dueWeek = asArr(tasks["due_this_week"]);
      const overdueTasks = asArr(tasks["overdue"]);
      const newLeads = num(leads["new_count"]) ?? asArr(leads["items"]).length;

      // ── summary (one-line TL;DR) ────────────────────────────────────────
      const summaryBits = [
        `${events.length} event${events.length !== 1 ? "s" : ""} today`,
        `${dueToday.length} task${dueToday.length !== 1 ? "s" : ""} due`,
        `${newLeads} new lead${newLeads !== 1 ? "s" : ""}`,
      ];
      if (alerts.length) summaryBits.push(`${alerts.length} alert${alerts.length !== 1 ? "s" : ""}`);
      const summary = `${summaryBits.join(" · ")}${staleNote}`;

      // ── highlights (most actionable, inline on the tile) ────────────────
      const highlights: string[] = [];
      for (const a of alerts.slice(0, 8)) {
        const ao = asObj(a);
        const level = (pick(ao, "level") || "info").toUpperCase();
        const msg = pick(ao, "message", "summary") || itemLine(a);
        const sec = pick(ao, "section");
        if (msg) highlights.push(`[${level}]${sec ? ` ${sec}:` : ""} ${msg}`);
      }
      for (const e of bullets(events, 5)) highlights.push(`📅 ${e}`);
      for (const t of bullets(dueToday, 5)) highlights.push(`✓ due: ${t}`);
      for (const l of bullets(asArr(leads["items"]), 3)) highlights.push(`★ lead: ${l}`);
      if (Object.keys(weather).length) {
        const ok = weather["outdoor_work_ok"];
        if (ok === true) highlights.push("🌤 outdoor work OK");
        else if (ok === false) highlights.push("🌧 outdoor work NOT recommended");
      }
      const backupStatus = pick(backup, "exit_status");
      if (backupStatus && backupStatus !== "unknown") {
        highlights.push(`💾 backup: ${backupStatus}${backup["last_run"] ? ` (${asStr(backup["last_run"])})` : ""}`);
      }

      // ── body (full markdown for the detail modal) ───────────────────────
      const md: string[] = [];
      md.push(`# Morning Briefing — ${dateLabel}${staleNote}`);
      if (generated_at) md.push(`_Generated: ${generated_at}_`);
      md.push("");

      const section = (title: string, lines: string[]) => {
        if (!lines.length) return;
        md.push(`## ${title}`);
        for (const l of lines) md.push(l);
        md.push("");
      };

      // Alerts
      section("Alerts", alerts.map((a) => {
        const ao = asObj(a);
        const level = (pick(ao, "level") || "info").toUpperCase();
        const sec = pick(ao, "section");
        const msg = pick(ao, "message", "summary") || itemLine(a);
        return `- **[${level}]**${sec ? ` _${sec}_:` : ""} ${msg}`;
      }));

      // Calendar
      section("Calendar", events.length
        ? bullets(events).map((e) => `- ${e}`)
        : (Object.keys(calendar).length ? ["- No events today."] : []));

      // Tasks
      const taskLines: string[] = [];
      if (dueToday.length) { taskLines.push("**Due today:**"); taskLines.push(...bullets(dueToday).map((t) => `- ${t}`)); }
      if (overdueTasks.length) { taskLines.push("**Overdue:**"); taskLines.push(...bullets(overdueTasks).map((t) => `- ${t}`)); }
      if (dueWeek.length) { taskLines.push("**Due this week:**"); taskLines.push(...bullets(dueWeek).map((t) => `- ${t}`)); }
      section("Tasks", taskLines);

      // Jobs
      section("Active Jobs", bullets(asArr(jobs["active"])).map((j) => `- ${j}`));

      // Leads
      const leadLines: string[] = [];
      if (num(leads["new_count"]) != null) leadLines.push(`New leads: **${num(leads["new_count"])}**`);
      leadLines.push(...bullets(asArr(leads["items"])).map((l) => `- ${l}`));
      section("Leads", leadLines);

      // Overdue invoices
      const overdueLines: string[] = [];
      const oc = num(overdue["count"]);
      const ot = num(overdue["total_amount"]);
      if (oc != null) overdueLines.push(`Overdue invoices: **${oc}**${ot != null ? ` — $${ot.toLocaleString()}` : ""}`);
      overdueLines.push(...bullets(asArr(overdue["items"])).map((i) => `- ${i}`));
      section("Overdue Invoices", overdueLines);

      // Weekly snapshot
      const weeklyLines = Object.entries(weekly)
        .filter(([, v]) => v != null && v !== "")
        .map(([k, v]) => `- ${k.replace(/_/g, " ")}: **${asStr(v)}**`);
      section("Weekly Snapshot", weeklyLines);

      // Comms
      const commsLines: string[] = [];
      const commsFields = ["calls_yesterday", "texts_yesterday", "missed_calls", "unread_texts"];
      const commsStats = commsFields
        .filter((k) => num(comms[k]) != null)
        .map((k) => `${k.replace(/_/g, " ")}: ${num(comms[k])}`);
      if (commsStats.length) commsLines.push(`- ${commsStats.join(" · ")}`);
      commsLines.push(...bullets(asArr(comms["items"])).map((c) => `- ${c}`));
      section("Comms", commsLines);

      // Weather
      const weatherLines: string[] = [];
      if (Object.keys(weather).length) {
        const loc = pick(weather, "location");
        const cur = num(weather["current_temp_f"]);
        const hi = num(weather["high_f"]);
        const lo = num(weather["low_f"]);
        const cond = pick(weather, "conditions");
        const head = [
          loc,
          cur != null ? `${cur}°F now` : "",
          (hi != null || lo != null) ? `H${hi ?? "?"}/L${lo ?? "?"}` : "",
          cond,
        ].filter(Boolean).join(" · ");
        if (head) weatherLines.push(`- ${head}`);
        const ok = weather["outdoor_work_ok"];
        if (ok === true) weatherLines.push("- Outdoor work: **OK**");
        else if (ok === false) weatherLines.push("- Outdoor work: **not recommended**");
        const notes = pick(weather, "notes");
        if (notes) weatherLines.push(`- _${notes}_`);
      }
      section("Weather", weatherLines);

      // System
      const sysLines: string[] = [];
      if (Object.keys(system).length) {
        const overall = pick(system, "overall");
        if (overall) sysLines.push(`- Overall: **${overall}**`);
        const sa = num(system["services_active"]); const sf = num(system["services_failed"]);
        if (sa != null || sf != null) sysLines.push(`- Services: ${sa ?? "?"} active, ${sf ?? "?"} failed`);
        const cr = num(system["containers_running"]); const cs = num(system["containers_stopped"]);
        if (cr != null || cs != null) sysLines.push(`- Containers: ${cr ?? "?"} running, ${cs ?? "?"} stopped`);
        sysLines.push(...bullets(asArr(system["storage"])).map((s) => `- ${s}`));
      }
      section("System", sysLines);

      // Mail
      const mailLines: string[] = [];
      if (Object.keys(mail).length) {
        const healthy = mail["healthy"];
        mailLines.push(`- Health: ${healthy === true ? "healthy" : healthy === false ? "degraded" : "unknown"}`);
        const lastSync = pick(mail, "last_sync");
        if (lastSync) mailLines.push(`- Last sync: ${lastSync}`);
        const sum = pick(mail, "summary");
        if (sum) mailLines.push(`- ${sum}`);
      }
      // Mail triage rollup (separate top-level key)
      if (Object.keys(mailTriage).length) {
        const stats = asObj(mailTriage["stats"]);
        const total = num(mailTriage["total_unread"]);
        const u = num(stats["urgent_count"]); const r = num(stats["review_count"]); const n = num(stats["noise_count"]);
        if (total != null || u != null) {
          mailLines.push(`- Triage: ${total ?? "?"} unread — ${u ?? 0} urgent, ${r ?? 0} review, ${n ?? 0} noise`);
        }
        const urgent = bullets(asArr(asObj(mailTriage["buckets"])["urgent"]), 5);
        for (const item of urgent) mailLines.push(`  - 🔴 ${item}`);
      }
      section("Mail", mailLines);

      // Recent documents
      section("Recent Documents", bullets(asArr(recentDocs["items"])).map((d) => `- ${d}`));

      const body = md.join("\n").trim();

      return {
        status: "ok",
        message: `Morning briefing for ${dateLabel}`,
        data: { generated_at, date: dateLabel, stale: Boolean(staleNote) },
        view: contract("text", "Morning Briefing", {
          greeting: `Morning Briefing — ${dateLabel}`,
          summary,
          highlights,
          body,
        }, { date: dateLabel, source: "hwc_morning_brief", generated_at }),
      };
    },
  };
}
