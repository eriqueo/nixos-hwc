/**
 * hwc_mail_* tools — mail system health, sync status.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { safeExec } from "../executors/shell.js";
import { getServiceStatus, getJournalLines } from "../executors/systemd.js";

export function mailTools(): ToolDef[] {
  return [
    {
      name: "hwc_mail_health",
      description:
        "Get mail system health — Proton Bridge status, mbsync last sync, " +
        "notmuch database, and mail freshness per account.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const checks: Record<string, unknown> = {};

          // Check Proton Bridge
          try {
            const bridgeStatus = await getServiceStatus("protonmail-bridge.service");
            checks.bridge = {
              active: bridgeStatus.activeState === "active",
              state: bridgeStatus.activeState,
              uptime: bridgeStatus.uptime,
            };
          } catch {
            checks.bridge = { active: false, error: "Service not found" };
          }

          // Check mbsync timer
          try {
            const mbsyncTimer = await safeExec("systemctl", [
              "--user", "list-timers", "mbsync.timer", "--no-pager",
            ], { timeout: 5000 });
            const mbsyncService = await safeExec("systemctl", [
              "--user", "show", "mbsync.service",
              "--property=ActiveState,ExecMainStartTimestamp,ExecMainExitTimestamp,ExecMainStatus",
              "--no-pager",
            ], { timeout: 5000 });

            const props: Record<string, string> = {};
            for (const line of mbsyncService.stdout.split("\n")) {
              const idx = line.indexOf("=");
              if (idx > 0) props[line.slice(0, idx)] = line.slice(idx + 1);
            }

            checks.sync = {
              lastRun: props.ExecMainStartTimestamp,
              lastFinished: props.ExecMainExitTimestamp,
              exitStatus: props.ExecMainStatus,
              timerActive: mbsyncTimer.stdout.includes("mbsync"),
            };
          } catch {
            checks.sync = { error: "Could not check mbsync (may be user service)" };
          }

          // Check notmuch
          try {
            const notmuchResult = await safeExec("notmuch", ["count"], { timeout: 5000 });
            checks.notmuch = {
              totalMessages: parseInt(notmuchResult.stdout.trim(), 10) || 0,
            };
          } catch {
            checks.notmuch = { error: "notmuch not available" };
          }

          // Check recent journal for mail errors
          try {
            const errors = await getJournalLines("mbsync.service", 5, "24h ago", "err");
            checks.recentErrors = errors.length > 0 ? errors : "none";
          } catch {
            // User services may not be queryable
          }

          const bridgeOk = (checks.bridge as Record<string, unknown>)?.active === true;
          return {
            status: bridgeOk ? "ok" : "partial",
            message: `Bridge: ${bridgeOk ? "active" : "down"}`,
            data: checks,
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to check mail health",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },
  ];
}
