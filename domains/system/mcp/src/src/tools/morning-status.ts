/**
 * hwc_morning_status — composite morning briefing tool.
 *
 * Combines: health_check + journal_errors(1h) + mail_health + storage_status(disk) + calendar_list(today)
 * Returns compact text briefing. Sub-call failures show "unavailable" rather than failing the whole tool.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { executeHealthCheck } from "./monitoring.js";
import { executeMailHealth } from "./mail.js";
import { khalList } from "./calendar.js";
import { safeExec } from "../executors/shell.js";

export function morningStatusTool(): ToolDef {
  return {
    name: "hwc_morning_status",
    description:
      "Combined morning briefing. Runs health_check + journal_errors(1h) + mail_health + storage + calendar(today) in one call. " +
      "Returns compact text summary. Sub-call failures show 'unavailable' rather than failing the whole tool.",
    inputSchema: {
      type: "object",
      properties: {
        timezone: {
          type: "string",
          description: "IANA timezone for calendar date (default: America/Denver)",
        },
      },
    },
    handler: async (args): Promise<ToolResult> => {
      const tz = (args.timezone as string) || "America/Denver";
      const lines: string[] = [];
      const today = new Date().toLocaleDateString("en-CA", { timeZone: tz });

      lines.push(`=== HWC Morning Status — ${today} ===`);

      // ── Services health ──────────────────────────────────────
      try {
        const health = await executeHealthCheck(["services", "containers"]);
        const data = health.data as Record<string, unknown> | undefined;
        const components = data?.components as Array<{ name: string; status: string; message: string }> | undefined;
        if (components) {
          const services = components.find((c) => c.name === "services");
          const containers = components.find((c) => c.name === "containers");
          const svcLine = services ? `${services.status === "green" ? "OK" : "WARN"} ${services.message}` : "unavailable";
          const ctrLine = containers ? `${containers.status === "green" ? "OK" : "WARN"} ${containers.message}` : "unavailable";
          lines.push(`Services: ${svcLine}`);
          lines.push(`Containers: ${ctrLine}`);
        } else {
          lines.push(`Health: ${health.message}`);
        }
      } catch {
        lines.push("Services: unavailable");
      }

      // ── Journal errors (1h) ──────────────────────────────────
      try {
        const result = await safeExec("journalctl", [
          "--since", "1h ago",
          "-p", "err",
          "--no-pager",
          "-n", "50",
          "-o", "short",
        ], { timeout: 10000 });
        const errorLines = result.stdout.split("\n").filter(Boolean);
        if (errorLines.length === 0) {
          lines.push("Errors (1h): none");
        } else {
          lines.push(`Errors (1h): ${errorLines.length} journal errors — check hwc_monitoring action=errors for details`);
        }
      } catch {
        lines.push("Errors (1h): unavailable");
      }

      // ── Mail health ──────────────────────────────────────────
      try {
        const mail = await executeMailHealth();
        const mailData = mail.data as Record<string, unknown> | undefined;
        const notmuch = mailData?.notmuch as Record<string, unknown> | undefined;
        const unread = notmuch?.unread;
        const bridgeOk = (mailData?.bridge as Record<string, unknown>)?.active === true;
        const syncOk = (mailData?.sync as Record<string, unknown>)?.healthy === true;
        const mailStatus = bridgeOk && syncOk ? "healthy" : "degraded";
        lines.push(`Mail: ${mailStatus}${unread !== undefined ? ` | ${unread} unread` : ""}`);
      } catch {
        lines.push("Mail: unavailable");
      }

      // ── Storage ──────────────────────────────────────────────
      try {
        const dfResult = await safeExec("df", [
          "-h", "--output=target,pcent",
          "/", "/mnt/hot", "/mnt/media",
        ], { timeout: 5000 });
        const dfLines = dfResult.stdout.split("\n").filter(Boolean).slice(1);
        const mounts = dfLines.map((line) => {
          const parts = line.trim().split(/\s+/);
          return `${parts[0]} ${parts[1]}`;
        }).filter(Boolean);
        lines.push(`Storage: ${mounts.join(" | ")}`);
      } catch {
        try {
          const dfResult = await safeExec("df", ["-h", "--output=target,pcent", "/"], { timeout: 5000 });
          const dfLines = dfResult.stdout.split("\n").filter(Boolean).slice(1);
          const parts = dfLines[0]?.trim().split(/\s+/) || [];
          lines.push(`Storage: / ${parts[1] || "unavailable"}`);
        } catch {
          lines.push("Storage: unavailable");
        }
      }

      // ── Calendar today ───────────────────────────────────────
      try {
        const events = await khalList(today, today);
        if (events.length === 0) {
          lines.push("Calendar today: no events");
        } else {
          const eventSummaries = events
            .slice(0, 5)
            .map((e) => `${e.startTime || "all-day"} ${e.summary}`)
            .join(", ");
          lines.push(`Calendar today: ${events.length} event${events.length !== 1 ? "s" : ""} — ${eventSummaries}${events.length > 5 ? "..." : ""}`);
        }
      } catch {
        lines.push("Calendar today: unavailable");
      }

      const briefing = lines.join("\n");

      return {
        status: "ok",
        message: `Morning status for ${today}`,
        data: { briefing, date: today },
      };
    },
  };
}
