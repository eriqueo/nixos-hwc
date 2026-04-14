/**
 * hwc_monitoring_* tools — health checks, journal errors, GPU status.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { safeExec } from "../executors/shell.js";
import { listServices } from "../executors/systemd.js";
import { listContainers } from "../executors/podman.js";
import { instantQuery, rangeQuery } from "../executors/prometheus.js";
import { TtlCache } from "../cache.js";
import { mcpError, catchError } from "../errors.js";

const cache = new TtlCache();

interface HealthComponent {
  name: string;
  status: "green" | "yellow" | "red";
  message: string;
  details?: unknown;
}

export function monitoringTools(
  workspace: string,
  runtimeTtl: number
): ToolDef[] {
  return [
    {
      name: "hwc_monitoring_health_check",
      description:
        "Run a comprehensive health check across services, storage, and containers. " +
        "Returns traffic-light summary (green/yellow/red) per component.",
      inputSchema: {
        type: "object",
        properties: {
          components: {
            type: "array",
            items: {
              type: "string",
              enum: [
                "services",
                "storage",
                "containers",
                "all",
              ],
            },
            default: ["all"],
            description: "Which components to check. Default: all.",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const requested = (args.components as string[]) || ["all"];
          const checkAll = requested.includes("all");
          const components: HealthComponent[] = [];

          // Services check
          if (checkAll || requested.includes("services")) {
            components.push(await checkServices());
          }

          // Storage check
          if (checkAll || requested.includes("storage")) {
            components.push(await checkStorage());
          }

          // Container check
          if (checkAll || requested.includes("containers")) {
            components.push(await checkContainers());
          }

          // Determine overall status
          const hasRed = components.some((c) => c.status === "red");
          const hasYellow = components.some((c) => c.status === "yellow");
          const overall = hasRed ? "red" : hasYellow ? "yellow" : "green";

          return {
            status: hasRed ? "partial" : "ok",
            message: `Overall: ${overall} — ${components.length} components checked`,
            data: { overall, components },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Health check failed", err);
        }
      },
    },

    {
      name: "hwc_monitoring_journal_errors",
      description:
        "Get recent error-level journal entries grouped by unit. " +
        "Returns error counts and most recent messages per service.",
      inputSchema: {
        type: "object",
        properties: {
          since: {
            type: "string",
            default: "24h ago",
            description: "Time filter, e.g. '24h ago', '1h ago', 'today'",
          },
          limit: {
            type: "integer",
            default: 100,
            description: "Maximum number of error lines to return",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const since = (args.since as string) || "24h ago";
          const limit = Math.min((args.limit as number) || 100, 500);

          const result = await safeExec("journalctl", [
            "--since",
            since,
            "-p",
            "err",
            "--no-pager",
            "-n",
            String(limit),
            "-o",
            "short",
          ], { timeout: 15000 });

          const lines = result.stdout.split("\n").filter(Boolean);

          // Group by unit
          const byUnit: Record<string, string[]> = {};
          for (const line of lines) {
            // Journal format: "Apr 02 10:30:00 hostname unit[pid]: message"
            const match = line.match(/\S+\s+\S+\s+\S+\s+\S+\s+(\S+?)(?:\[\d+\])?:/);
            const unit = match?.[1] || "unknown";
            if (!byUnit[unit]) byUnit[unit] = [];
            byUnit[unit].push(line);
          }

          const unitSummary = Object.entries(byUnit)
            .map(([unit, msgs]) => ({
              unit,
              count: msgs.length,
              recentMessages: msgs.slice(-3),
            }))
            .sort((a, b) => b.count - a.count);

          return {
            status: "ok",
            message: `${lines.length} errors from ${Object.keys(byUnit).length} units since ${since}`,
            data: {
              totalErrors: lines.length,
              unitCount: Object.keys(byUnit).length,
              byUnit: unitSummary,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to query journal errors", err, "Is journalctl accessible?");
        }
      },
    },

    // ── hwc_monitoring_prometheus_query ──────────────────────────────────
    {
      name: "hwc_monitoring_prometheus_query",
      description:
        "Execute a PromQL query against local Prometheus. Supports instant and range queries. " +
        "Examples: 'up', 'rate(node_cpu_seconds_total[5m])'. Requires Prometheus on localhost:9090.",
      inputSchema: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "PromQL query expression",
          },
          type: {
            type: "string",
            enum: ["instant", "range"],
            default: "instant",
          },
          start: {
            type: "string",
            description: "Range query start (ISO8601 or relative like '-1h')",
          },
          end: {
            type: "string",
            description: "Range query end time",
          },
          step: {
            type: "string",
            default: "60s",
            description: "Range query step size",
          },
        },
        required: ["query"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const query = args.query as string;
          const type = (args.type as string) || "instant";

          if (type === "range") {
            const start = args.start as string;
            const end = args.end as string;
            const step = (args.step as string) || "60s";
            if (!start || !end) {
              return mcpError({
                type: "VALIDATION_ERROR",
                message: "Range query requires 'start' and 'end' parameters",
                suggestion: "Provide start and end as ISO8601 timestamps or relative values like '-1h'",
              });
            }
            const result = await rangeQuery(query, start, end, step);
            return {
              status: "ok",
              message: `Range query: ${result.data.result.length} series`,
              data: result.data,
            };
          }

          const result = await instantQuery(query);
          return {
            status: "ok",
            message: `${result.data.result.length} results`,
            data: result.data,
          };
        } catch (err) {
          return catchError("UNAVAILABLE", "Prometheus query failed (is Prometheus running?)", err, "Check that Prometheus is running on localhost:9090");
        }
      },
    },

    // ── hwc_monitoring_gpu_status ───────────────────────────────────────
    {
      name: "hwc_monitoring_gpu_status",
      description:
        "Get NVIDIA GPU utilization, memory, temperature, power draw, and running processes. " +
        "Requires nvidia-smi. Only available on hosts with NVIDIA GPUs.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          // Try nvidia-smi from PATH, then NixOS system profile fallback
          let nvidiaSmi = "nvidia-smi";
          const testRun = await safeExec("nvidia-smi", ["--version"], { timeout: 3000 });
          if (testRun.exitCode !== 0) {
            // Not in service PATH; try NixOS system profile
            const fallback = "/run/current-system/sw/bin/nvidia-smi";
            const fallbackTest = await safeExec(fallback, ["--version"], { timeout: 3000 });
            if (fallbackTest.exitCode === 0) nvidiaSmi = fallback;
          }

          const [gpuResult, procResult] = await Promise.all([
            safeExec(nvidiaSmi, [
              "--query-gpu=name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw",
              "--format=csv,noheader,nounits",
            ], { timeout: 5000 }),
            safeExec(nvidiaSmi, [
              "--query-compute-apps=pid,name,used_memory",
              "--format=csv,noheader,nounits",
            ], { timeout: 5000 }),
          ]);

          if (gpuResult.exitCode !== 0) {
            return mcpError({
              type: "NOT_FOUND",
              message: "nvidia-smi not available",
              error: gpuResult.stderr,
              suggestion: "nvidia-smi not in service PATH or /run/current-system/sw/bin/. This host may not have an NVIDIA GPU.",
            });
          }

          const gpuLine = gpuResult.stdout.trim().split(",").map((s) => s.trim());
          const gpu = {
            name: gpuLine[0],
            tempC: parseInt(gpuLine[1], 10),
            gpuUtil: `${gpuLine[2]}%`,
            memUtil: `${gpuLine[3]}%`,
            memUsedMB: parseInt(gpuLine[4], 10),
            memTotalMB: parseInt(gpuLine[5], 10),
            powerW: parseFloat(gpuLine[6]),
          };

          const processes = procResult.stdout
            .split("\n")
            .filter(Boolean)
            .map((line) => {
              const parts = line.split(",").map((s) => s.trim());
              return { pid: parts[0], name: parts[1], memMB: parseInt(parts[2], 10) };
            });

          return {
            status: "ok",
            message: `${gpu.name}: ${gpu.gpuUtil} GPU, ${gpu.memUsedMB}/${gpu.memTotalMB}MB, ${gpu.tempC}°C`,
            data: { gpu, processes },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to query GPU status", err);
        }
      },
    },
  ];
}

/** Check systemd services health */
async function checkServices(): Promise<HealthComponent> {
  try {
    const services = await listServices();
    const failed = services.filter((s) => s.activeState === "failed");
    const active = services.filter((s) => s.activeState === "active");

    if (failed.length > 0) {
      return {
        name: "services",
        status: "red",
        message: `${failed.length} failed services: ${failed.map((s) => s.name).join(", ")}`,
        details: { active: active.length, failed: failed.length, failedNames: failed.map((s) => s.name) },
      };
    }
    return {
      name: "services",
      status: "green",
      message: `${active.length} services active`,
      details: { active: active.length, failed: 0 },
    };
  } catch (err) {
    return {
      name: "services",
      status: "red",
      message: `Failed to check services: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}

/** Check disk space */
async function checkStorage(): Promise<HealthComponent> {
  try {
    const result = await safeExec("df", [
      "-h",
      "--output=target,pcent,avail",
      "/",
      "/mnt/hot",
      "/mnt/media",
    ], { timeout: 5000 });

    const lines = result.stdout.split("\n").filter(Boolean).slice(1); // skip header
    const mounts: { mount: string; percent: number; available: string }[] = [];
    let worstPercent = 0;

    for (const line of lines) {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 3) {
        const percent = parseInt(parts[1], 10);
        mounts.push({ mount: parts[0], percent, available: parts[2] });
        if (percent > worstPercent) worstPercent = percent;
      }
    }

    const status = worstPercent >= 95 ? "red" : worstPercent >= 85 ? "yellow" : "green";
    return {
      name: "storage",
      status,
      message: `Worst: ${worstPercent}% used`,
      details: mounts,
    };
  } catch (err) {
    // Some mounts may not exist (e.g., on laptop)
    try {
      const result = await safeExec("df", ["-h", "--output=target,pcent,avail", "/"], { timeout: 5000 });
      const lines = result.stdout.split("\n").filter(Boolean).slice(1);
      const parts = lines[0]?.trim().split(/\s+/) || [];
      const percent = parseInt(parts[1] || "0", 10);
      return {
        name: "storage",
        status: percent >= 95 ? "red" : percent >= 85 ? "yellow" : "green",
        message: `Root: ${percent}% used (other mounts unavailable)`,
      };
    } catch {
      return { name: "storage", status: "yellow", message: "Could not check disk space" };
    }
  }
}

/** Check podman containers — tries podman ps, falls back to systemd service list */
async function checkContainers(): Promise<HealthComponent> {
  try {
    const containers = await listContainers();
    let running: string[] = [];
    let stopped: string[] = [];

    if (containers.length > 0) {
      for (const c of containers) {
        const name = c.Names?.[0] || "unknown";
        if (c.State === "running") {
          running.push(name);
        } else {
          stopped.push(name);
        }
      }
    } else {
      // Fallback: count podman-* systemd services (podman ps may not see rootful containers)
      const services = await listServices();
      const containerServices = services.filter((s) => s.type === "container");
      running = containerServices
        .filter((s) => s.activeState === "active")
        .map((s) => s.name.replace("podman-", "").replace(".service", ""));
      stopped = containerServices
        .filter((s) => s.activeState !== "active")
        .map((s) => s.name.replace("podman-", "").replace(".service", ""));

      if (running.length === 0 && stopped.length === 0) {
        return {
          name: "containers",
          status: "green",
          message: "No container services detected",
          details: { running: [], stopped: [], source: "systemd-fallback" },
        };
      }
    }

    if (stopped.length > 0) {
      return {
        name: "containers",
        status: "yellow",
        message: `${running.length} running, ${stopped.length} stopped: ${stopped.join(", ")}`,
        details: { running, stopped },
      };
    }
    return {
      name: "containers",
      status: "green",
      message: `${running.length} containers running`,
      details: { running, stopped: [] },
    };
  } catch (err) {
    return {
      name: "containers",
      status: "yellow",
      message: `Could not check containers: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}
