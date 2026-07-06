/**
 * hwc_morning_status — reader over the morning briefing (one producer per fact).
 *
 * 2026-07-06 (audit 2.1): this tool no longer computes anything. The bash
 * pipeline in domains/business/morning-briefing/run.sh is the SOLE producer
 * of briefing.json; this tool (like hwc_morning_brief and the dashboard) is
 * a consumer that renders the same file. Duplicate producers drift.
 */

import { readFile, stat } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { contract } from "../result.js";

const BRIEFING_PATH =
  "/home/eric/.nixos/domains/business/morning-briefing/output/briefing.json";
const STALE_HOURS = 26;

export function morningStatusTool(): ToolDef {
  return {
    name: "hwc_morning_status",
    description:
      "Compact text summary of the daily morning briefing (briefing.json, produced 06:00 by the " +
      "morning-briefing pipeline). Reader only — same data as hwc_morning_brief and the dashboard. " +
      "Flags staleness if the briefing is older than 26h.",
    inputSchema: { type: "object", properties: {} },
    handler: async (): Promise<ToolResult> => {
      let raw: string;
      let mtime: Date | null = null;
      try {
        raw = await readFile(BRIEFING_PATH, "utf-8");
        mtime = (await stat(BRIEFING_PATH)).mtime;
      } catch {
        return {
          status: "error",
          message:
            "briefing.json not found — the morning-briefing pipeline has not produced output " +
            `(expected at ${BRIEFING_PATH}; timer runs 06:00).`,
        };
      }

      let b: Record<string, any>;
      try {
        b = JSON.parse(raw);
      } catch {
        return { status: "error", message: "briefing.json exists but is not valid JSON." };
      }

      const lines: string[] = [];
      const generated = b.generated_at ?? "unknown";
      lines.push(`=== HWC Morning Status — generated ${generated} ===`);

      const ageHours = mtime ? (Date.now() - mtime.getTime()) / 3_600_000 : null;
      if (ageHours !== null && ageHours > STALE_HOURS) {
        lines.push(`STALE: briefing is ${ageHours.toFixed(0)}h old — pipeline may have failed.`);
      }

      const alerts: Array<{ level: string; section: string; message: string }> = b.alerts ?? [];
      lines.push(
        alerts.length === 0
          ? "Alerts: none"
          : `Alerts (${alerts.length}): ` +
              alerts.map((a) => `[${a.level}] ${a.section}: ${a.message}`).join(" · ")
      );

      const sys = b.sections?.system;
      if (sys) {
        const storage = (sys.storage ?? [])
          .map((s: any) => `${s.mount} ${s.percent}%`)
          .join(" | ");
        lines.push(
          `Services: ${sys.services_active ?? "?"} active / ${sys.services_failed ?? "?"} failed · ` +
            `Containers: ${sys.containers_running ?? "?"} running` +
            (storage ? ` · Storage: ${storage}` : "")
        );
      }

      const drift = b.sections?.config_drift;
      if (drift) {
        lines.push(
          `Drift: reboot_pending=${drift.reboot_pending ?? "?"} unpushed=${drift.unpushed_commits ?? "?"} ` +
            `dirty=${drift.dirty_files ?? "?"} generations=${drift.generation_count ?? "?"} ` +
            `coredumps_24h=${drift.coredumps_24h ?? "?"}`
        );
      }

      const mail = b.sections?.mail;
      const triage = b.mail_triage;
      if (mail || triage) {
        const t = triage
          ? ` · triage: ${(triage.urgent ?? []).length} urgent / ${(triage.review ?? []).length} review / ${(triage.noise ?? []).length} noise`
          : "";
        lines.push(`Mail: ${mail?.healthy === false ? "DEGRADED" : "healthy"} · ${mail?.inbox_unread ?? mail?.unread ?? "?"} unread${t}`);
      }

      const events: any[] = b.sections?.calendar?.events ?? [];
      lines.push(
        events.length === 0
          ? "Calendar: no events"
          : `Calendar (${events.length}): ` +
              events
                .slice(0, 5)
                .map((e) => `${e.date ?? ""} ${e.startTime ?? "all-day"} ${e.summary ?? ""}`.trim())
                .join(", ") + (events.length > 5 ? "…" : "")
      );

      const briefing = lines.join("\n");
      const [header, ...sections] = lines;
      return {
        status: "ok",
        message: `Morning status (briefing generated ${generated})`,
        data: { briefing, generated_at: generated, alerts_count: alerts.length },
        view: contract("text", "Morning Briefing", {
          greeting: header ?? "HWC Morning Status",
          summary: `${sections.length} section${sections.length !== 1 ? "s" : ""}`,
          highlights: sections,
        }, { generated_at: generated, source: "briefing.json" }),
      };
    },
  };
}
