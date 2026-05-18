/**
 * hwc_monitoring — consolidated monitoring tool (health, errors, gpu, prometheus).
 */

import type { ToolDef, ToolResult } from "../types.js";
import { safeExec } from "../executors/shell.js";
import { listServices } from "../executors/systemd.js";
import { listContainers } from "../executors/podman.js";
import { instantQuery, rangeQuery } from "../executors/prometheus.js";
import { mcpError, catchError } from "../errors.js";

interface HealthComponent {
  name: string;
  status: "green" | "yellow" | "red";
  message: string;
  details?: unknown;
}

export async function executeHealthCheck(components?: string[]): Promise<ToolResult> {
  try {
    const requested = components || ["all"];
    const checkAll = requested.includes("all");
    const result: HealthComponent[] = [];

    if (checkAll || requested.includes("services")) {
      result.push(await checkServices());
    }
    if (checkAll || requested.includes("storage")) {
      result.push(await checkStorage());
    }
    if (checkAll || requested.includes("containers")) {
      result.push(await checkContainers());
    }

    const hasRed = result.some((c) => c.status === "red");
    const hasYellow = result.some((c) => c.status === "yellow");
    const overall = hasRed ? "red" : hasYellow ? "yellow" : "green";

    return {
      status: hasRed ? "partial" : "ok",
      message: `Overall: ${overall} — ${result.length} components checked`,
      data: { overall, components: result },
    };
  } catch (err) {
    return catchError("INTERNAL_ERROR", "Health check failed", err);
  }
}

export function monitoringTools(): ToolDef[] {
  return [
    {
      name: "hwc_monitoring",
      description:
        "System monitoring. action=health returns compact status. " +
        "Actions: health, errors, gpu, prometheus.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["health", "errors", "gpu", "prometheus"],
            description: "Action to perform",
          },
          // [health] params
          components: {
            type: "array",
            items: {
              type: "string",
              enum: ["services", "storage", "containers", "all"],
            },
            description: "[health] Which components to check (default: all)",
          },
          // [errors] params
          since: {
            type: "string",
            description: "[errors] Time filter, e.g. '24h ago', '1h ago', 'today' (default: 24h ago)",
          },
          limit: {
            type: "integer",
            description: "[errors] Maximum number of error lines to return (default: 100)",
          },
          // [prometheus] params
          query: {
            type: "string",
            description: "[prometheus] PromQL query expression",
          },
          query_type: {
            type: "string",
            enum: ["instant", "range"],
            description: "[prometheus] Query type (default: instant)",
          },
          start: {
            type: "string",
            description: "[prometheus] Range query start (ISO8601 or relative like '-1h')",
          },
          end: {
            type: "string",
            description: "[prometheus] Range query end time",
          },
          step: {
            type: "string",
            description: "[prometheus] Range query step size (default: 60s)",
          },
        },
        required: ["action"],
      },
      handler: async (args): Promise<ToolResult> => {
        const action = args.action as string;

        // ── health ───────────────────────────────────────────────
        if (action === "health") {
          const components = args.components as string[] | undefined;
          return executeHealthCheck(components);
        }

        // ── errors ───────────────────────────────────────────────
        if (action === "errors") {
          try {
            const since = (args.since as string) || "24h ago";
            const lim = Math.min((args.limit as number) || 100, 500);

            const result = await safeExec("journalctl", [
              "--since", since,
              "-p", "err",
              "--no-pager",
              "-n", String(lim),
              "-o", "short",
            ], { timeout: 15000 });

            const lines = result.stdout.split("\n").filter(Boolean);

            const byUnit: Record<string, string[]> = {};
            for (const line of lines) {
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
              data: { totalErrors: lines.length, unitCount: Object.keys(byUnit).length, byUnit: unitSummary },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to query journal errors", err, "Is journalctl accessible?");
          }
        }

        // ── gpu ──────────────────────────────────────────────────
        if (action === "gpu") {
          try {
            let nvidiaSmi = "nvidia-smi";
            const testRun = await safeExec("nvidia-smi", ["--version"], { timeout: 3000 });
            if (testRun.exitCode !== 0) {
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
              return mcpError({ type: "NOT_FOUND", message: "nvidia-smi not available", error: gpuResult.stderr, suggestion: "nvidia-smi not in service PATH or /run/current-system/sw/bin/. This host may not have an NVIDIA GPU." });
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
        }

        // ── prometheus ───────────────────────────────────────────
        if (action === "prometheus") {
          try {
            const query = args.query as string;
            if (!query) {
              return mcpError({ type: "VALIDATION_ERROR", message: "query is required for action=prometheus" });
            }
            const type = (args.query_type as string) || "instant";

            if (type === "range") {
              const start = args.start as string;
              const end = args.end as string;
              const step = (args.step as string) || "60s";
              if (!start || !end) {
                return mcpError({ type: "VALIDATION_ERROR", message: "Range query requires 'start' and 'end' parameters", suggestion: "Provide start and end as ISO8601 timestamps or relative values like '-1h'" });
              }
              const result = await rangeQuery(query, start, end, step);
              return { status: "ok", message: `Range query: ${result.data.result.length} series`, data: result.data };
            }

            const result = await instantQuery(query);
            return { status: "ok", message: `${result.data.result.length} results`, data: result.data };
          } catch (err) {
            return catchError("UNAVAILABLE", "Prometheus query failed (is Prometheus running?)", err, "Check that Prometheus is running on localhost:9090");
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
      },
    },
  ];
}

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

async function checkStorage(): Promise<HealthComponent> {
  try {
    const result = await safeExec("df", ["-h", "--output=target,pcent,avail", "/", "/mnt/hot", "/mnt/media"], { timeout: 5000 });
    const lines = result.stdout.split("\n").filter(Boolean).slice(1);
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
    return { name: "storage", status, message: `Worst: ${worstPercent}% used`, details: mounts };
  } catch (err) {
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
