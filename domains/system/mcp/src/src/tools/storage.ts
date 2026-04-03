/**
 * hwc_storage_* tools — disk usage, backup status.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { safeExec } from "../executors/shell.js";
import { TtlCache } from "../cache.js";
import { catchError } from "../errors.js";

const cache = new TtlCache();

export function storageTools(runtimeTtl: number): ToolDef[] {
  return [
    {
      name: "hwc_storage_disk_usage",
      description:
        "Get disk usage across storage tiers: root (/), hot (/mnt/hot), media (/mnt/media), " +
        "backup (/mnt/backup). Returns size, used, available, and percent for each mount. " +
        "Flags error if any mount exceeds 95%.",
      inputSchema: {
        type: "object",
        properties: {
          tier: {
            type: "string",
            enum: ["all", "hot", "media", "backup", "root"],
            default: "all",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const tier = (args.tier as string) || "all";
          const mountMap: Record<string, string> = {
            root: "/",
            hot: "/mnt/hot",
            media: "/mnt/media",
            backup: "/mnt/backup",
          };

          const mounts = tier === "all"
            ? Object.entries(mountMap)
            : [[tier, mountMap[tier] || "/"]];

          const results: Array<{
            tier: string;
            mount: string;
            device?: string;
            size?: string;
            used?: string;
            available?: string;
            percentUsed?: number;
            error?: string;
          }> = [];

          for (const [name, path] of mounts) {
            try {
              const r = await safeExec("df", ["-h", path], { timeout: 5000 });
              const lines = r.stdout.split("\n").filter(Boolean).slice(1);
              if (lines.length > 0) {
                const parts = lines[0].trim().split(/\s+/);
                results.push({
                  tier: name,
                  mount: path,
                  device: parts[0],
                  size: parts[1],
                  used: parts[2],
                  available: parts[3],
                  percentUsed: parseInt(parts[4], 10),
                });
              }
            } catch {
              results.push({ tier: name, mount: path, error: "Mount not available" });
            }
          }

          const worstPercent = Math.max(...results.map((r) => r.percentUsed || 0));
          return {
            status: worstPercent >= 95 ? "error" : "ok",
            message: `Worst: ${worstPercent}% used across ${results.length} mounts`,
            data: { mounts: results },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to check disk usage", err);
        }
      },
    },

    {
      name: "hwc_storage_backup_status",
      description:
        "Get Borg backup status — last run time, next scheduled, exit status, archive stats. " +
        "Reads from borgbackup-job-hwc-backup systemd timer and journal.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const serviceName = "borgbackup-job-hwc-backup";

          const [timerResult, serviceResult, journalResult] = await Promise.all([
            safeExec("systemctl", [
              "list-timers", `${serviceName}.timer`, "--no-pager",
            ], { timeout: 5000 }),
            safeExec("systemctl", [
              "show", `${serviceName}.service`,
              "--property=ActiveState,SubState,ExecMainStatus,ExecMainStartTimestamp,ExecMainExitTimestamp",
              "--no-pager",
            ], { timeout: 5000 }),
            // Get recent borg journal output for archive summary
            safeExec("journalctl", [
              "-u", `${serviceName}.service`,
              "--no-pager",
              "-n", "30",
              "--since", "7 days ago",
              "-o", "cat",
            ], { timeout: 10000 }),
          ]);

          const props: Record<string, string> = {};
          for (const line of serviceResult.stdout.split("\n")) {
            const idx = line.indexOf("=");
            if (idx > 0) props[line.slice(0, idx)] = line.slice(idx + 1);
          }

          // Parse timer output for next run
          const timerLines = timerResult.stdout.split("\n");
          let nextRun: string | undefined;
          for (const line of timerLines) {
            if (line.includes("borgbackup")) {
              const parts = line.trim().split(/\s{2,}/);
              nextRun = parts[0];
              break;
            }
          }

          // Extract archive summary from journal (borg logs archive stats)
          let lastArchive: Record<string, unknown> | undefined;
          const journalLines = journalResult.stdout.split("\n").filter(Boolean);
          for (const line of journalLines.reverse()) {
            // Look for borg archive creation summary lines
            const archiveMatch = line.match(/Archive name: (.+)/);
            if (archiveMatch) {
              lastArchive = { name: archiveMatch[1] };
              break;
            }
          }

          // Extract stats from journal
          const stats: Record<string, string> = {};
          for (const line of journalLines) {
            const sizeMatch = line.match(/(Original size|Compressed size|Deduplicated size|This archive):\s*(.+)/);
            if (sizeMatch) stats[sizeMatch[1]] = sizeMatch[2].trim();
            const durationMatch = line.match(/Duration:\s*(.+)/);
            if (durationMatch) stats["Duration"] = durationMatch[1].trim();
          }

          return {
            status: "ok",
            message: `Backup service: ${props.ActiveState || "unknown"}`,
            data: {
              serviceState: props.ActiveState,
              lastStarted: props.ExecMainStartTimestamp,
              lastFinished: props.ExecMainExitTimestamp,
              exitStatus: props.ExecMainStatus,
              nextScheduled: nextRun,
              lastArchive,
              archiveStats: Object.keys(stats).length > 0 ? stats : undefined,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to check backup status", err, "Is borgbackup-job-hwc-backup configured?");
        }
      },
    },
  ];
}
