/**
 * hwc_mail_* tools — mail system health, sync status.
 *
 * Proton Bridge is a system service (queryable via systemctl).
 * mbsync/notmuch are user services — we check file-based markers
 * instead of systemctl --user (which doesn't work from a system service).
 */

import { readFile, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { safeExec } from "../executors/shell.js";
import { getServiceStatus } from "../executors/systemd.js";

const HOME = homedir();
const MBSYNC_SUCCESS_MARKER = join(HOME, ".cache/mbsync-last-success");
const MAIL_HEALTH_STATE = join(HOME, ".local/state/mail-health");
const MAILDIR = join(HOME, "400_mail/Maildir");

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

          // Check Proton Bridge (system service)
          try {
            const bridgeStatus = await getServiceStatus("protonmail-bridge.service");
            checks.bridge = {
              active: bridgeStatus.activeState === "active",
              state: bridgeStatus.activeState,
              uptime: bridgeStatus.uptime,
              memoryUsage: bridgeStatus.memoryUsage,
            };
          } catch {
            checks.bridge = { active: false, error: "Service not found" };
          }

          // Check mbsync last sync via file marker (user service, can't use systemctl --user)
          try {
            const markerStat = await stat(MBSYNC_SUCCESS_MARKER);
            const lastSync = markerStat.mtime;
            const ageMinutes = Math.round((Date.now() - lastSync.getTime()) / 60000);

            checks.sync = {
              lastSuccess: lastSync.toISOString(),
              ageMinutes,
              healthy: ageMinutes < 30, // timer runs every 10m, 30m = 3 missed cycles
            };
          } catch {
            checks.sync = { error: "No sync marker found — mbsync may not have run yet" };
          }

          // Check mail-health state (written by the dedicated health timer)
          try {
            const healthFile = join(MAIL_HEALTH_STATE, "status.json");
            const content = await readFile(healthFile, "utf-8");
            const healthState = JSON.parse(content);
            checks.healthCheck = healthState;
          } catch {
            // Health state may not exist yet or use a different format
            // Try reading individual state files
            try {
              const lastCheckFile = join(MAIL_HEALTH_STATE, "last-check");
              const lastCheck = await readFile(lastCheckFile, "utf-8");
              checks.healthCheck = { lastCheck: lastCheck.trim() };
            } catch {
              // No health state available
            }
          }

          // Check notmuch database
          try {
            const notmuchResult = await safeExec("notmuch", ["count"], { timeout: 5000 });
            if (notmuchResult.exitCode === 0) {
              const total = parseInt(notmuchResult.stdout.trim(), 10) || 0;

              // Also get unread count
              let unread = 0;
              try {
                const unreadResult = await safeExec("notmuch", ["count", "tag:unread"], { timeout: 5000 });
                if (unreadResult.exitCode === 0) {
                  unread = parseInt(unreadResult.stdout.trim(), 10) || 0;
                }
              } catch {
                // fine
              }

              checks.notmuch = { totalMessages: total, unread };
            } else {
              checks.notmuch = { error: "notmuch count failed", stderr: notmuchResult.stderr.slice(0, 200) };
            }
          } catch {
            checks.notmuch = { error: "notmuch not available" };
          }

          // Check Maildir exists
          try {
            const maildirStat = await stat(MAILDIR);
            checks.maildir = { exists: maildirStat.isDirectory(), path: MAILDIR };
          } catch {
            checks.maildir = { exists: false, path: MAILDIR };
          }

          const bridgeOk = (checks.bridge as Record<string, unknown>)?.active === true;
          const syncHealthy = (checks.sync as Record<string, unknown>)?.healthy === true;
          const overall = bridgeOk && syncHealthy ? "ok" : bridgeOk || syncHealthy ? "partial" : "error";

          return {
            status: overall as "ok" | "partial" | "error",
            message: `Bridge: ${bridgeOk ? "active" : "down"}, Sync: ${syncHealthy ? "healthy" : "stale/unknown"}`,
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
