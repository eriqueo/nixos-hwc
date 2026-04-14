/**
 * hwc_storage_status — combined disk usage and backup status.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { safeExec } from "../executors/shell.js";
import { catchError } from "../errors.js";

export function storageTools(): ToolDef[] {
  return [
    {
      name: "hwc_storage_status",
      description:
        "Get storage status: disk usage across tiers and/or Borg backup status. " +
        "Default returns both. Flags error if any mount exceeds 95%.",
      inputSchema: {
        type: "object",
        properties: {
          include: {
            type: "string",
            enum: ["all", "disk", "backup"],
            default: "all",
            description: "What to include (default: all)",
          },
          tier: {
            type: "string",
            enum: ["all", "hot", "media", "backup", "root"],
            default: "all",
            description: "Disk tier filter (only for disk usage)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const include = (args.include as string) || "all";
          const tier = (args.tier as string) || "all";
          const data: Record<string, unknown> = {};
          const parts: string[] = [];
          let hasError = false;

          // Disk usage
          if (include === "all" || include === "disk") {
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
                  const p = lines[0].trim().split(/\s+/);
                  results.push({
                    tier: name,
                    mount: path,
                    device: p[0],
                    size: p[1],
                    used: p[2],
                    available: p[3],
                    percentUsed: parseInt(p[4], 10),
                  });
                }
              } catch {
                results.push({ tier: name, mount: path, error: "Mount not available" });
              }
            }

            const worstPercent = Math.max(...results.map((r) => r.percentUsed || 0));
            if (worstPercent >= 95) hasError = true;
            data.disk = { mounts: results, worstPercent };
            parts.push(`Disk: worst ${worstPercent}%`);
          }

          // Backup status
          if (include === "all" || include === "backup") {
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

            const timerLines = timerResult.stdout.split("\n");
            let nextRun: string | undefined;
            for (const line of timerLines) {
              if (line.includes("borgbackup")) {
                const p = line.trim().split(/\s{2,}/);
                nextRun = p[0];
                break;
              }
            }

            let lastArchive: Record<string, unknown> | undefined;
            const journalLines = journalResult.stdout.split("\n").filter(Boolean);
            for (const line of journalLines.reverse()) {
              const archiveMatch = line.match(/Archive name: (.+)/);
              if (archiveMatch) {
                lastArchive = { name: archiveMatch[1] };
                break;
              }
            }

            const stats: Record<string, string> = {};
            for (const line of journalLines) {
              const sizeMatch = line.match(/(Original size|Compressed size|Deduplicated size|This archive):\s*(.+)/);
              if (sizeMatch) stats[sizeMatch[1]] = sizeMatch[2].trim();
              const durationMatch = line.match(/Duration:\s*(.+)/);
              if (durationMatch) stats["Duration"] = durationMatch[1].trim();
            }

            data.backup = {
              serviceState: props.ActiveState,
              lastStarted: props.ExecMainStartTimestamp,
              lastFinished: props.ExecMainExitTimestamp,
              exitStatus: props.ExecMainStatus,
              nextScheduled: nextRun,
              lastArchive,
              archiveStats: Object.keys(stats).length > 0 ? stats : undefined,
            };
            parts.push(`Backup: ${props.ActiveState || "unknown"}`);
          }

          return {
            status: hasError ? "error" : "ok",
            message: parts.join(", "),
            data,
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to check storage status", err);
        }
      },
    },
  ];
}
