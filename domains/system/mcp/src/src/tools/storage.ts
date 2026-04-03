/**
 * hwc_storage_* tools — disk usage, backup status.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { safeExec } from "../executors/shell.js";
import { TtlCache } from "../cache.js";

const cache = new TtlCache();

export function storageTools(runtimeTtl: number): ToolDef[] {
  return [
    {
      name: "hwc_storage_disk_usage",
      description:
        "Get disk usage across storage tiers: root (/), hot (/mnt/hot), " +
        "media (/mnt/media), backup (/mnt/backup). Shows size, used, available, percent.",
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
          return {
            status: "error",
            message: "Failed to check disk usage",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    {
      name: "hwc_storage_backup_status",
      description:
        "Get Borg backup status — last run, next scheduled, recent archives. " +
        "Checks borgbackup-job-hwc systemd timer.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const [timerResult, serviceResult] = await Promise.all([
            safeExec("systemctl", ["list-timers", "borgbackup-job-hwc.timer", "--no-pager"], { timeout: 5000 }),
            safeExec("systemctl", ["show", "borgbackup-job-hwc.service",
              "--property=ActiveState,SubState,ExecMainStatus,ExecMainStartTimestamp,ExecMainExitTimestamp",
              "--no-pager"], { timeout: 5000 }),
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

          return {
            status: "ok",
            message: `Backup service: ${props.ActiveState || "unknown"}`,
            data: {
              serviceState: props.ActiveState,
              lastStarted: props.ExecMainStartTimestamp,
              lastFinished: props.ExecMainExitTimestamp,
              exitStatus: props.ExecMainStatus,
              nextScheduled: nextRun,
            },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to check backup status",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },
  ];
}
