/**
 * hwc_services_* tools — query and manage live service state.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { listServices, getServiceStatus, getJournalLines } from "../executors/systemd.js";
import { getContainerStats, listContainers } from "../executors/podman.js";
import { TtlCache } from "../cache.js";

const cache = new TtlCache();

export function servicesTools(runtimeTtl: number): ToolDef[] {
  return [
    {
      name: "hwc_services_status",
      description:
        "Get the runtime status of a specific service or all services. " +
        "Returns systemd state, uptime, memory usage, and recent log lines. " +
        "Pass a service name (e.g. 'jellyfin', 'caddy', 'tailscaled') or omit for overview.",
      inputSchema: {
        type: "object",
        properties: {
          service: {
            type: "string",
            description:
              "Service name (e.g. 'jellyfin', 'n8n', 'caddy', 'tailscaled'). " +
              "For containers, the podman- prefix is added automatically. Omit for overview of all.",
          },
          type: {
            type: "string",
            enum: ["all", "container", "native"],
            default: "all",
            description: "Filter by service type",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const serviceName = args.service as string | undefined;
          const filterType = (args.type as string) || "all";

          if (serviceName) {
            // Try exact name first, then with podman- prefix, then with .service suffix
            const candidates = [
              serviceName,
              `podman-${serviceName}`,
              `${serviceName}.service`,
              `podman-${serviceName}.service`,
            ];

            for (const candidate of candidates) {
              try {
                const status = await getServiceStatus(candidate);
                if (status.activeState !== "unknown" && status.activeState !== "inactive") {
                  // Get recent logs for this service
                  const logs = await getJournalLines(candidate, 10);
                  return {
                    status: "ok",
                    message: `Status for ${candidate}`,
                    data: { ...status, recentLogs: logs },
                  };
                }
              } catch {
                continue;
              }
            }

            return {
              status: "error",
              message: `Service not found: ${serviceName}`,
              error: `Could not find active service matching '${serviceName}'. Tried: ${candidates.join(", ")}`,
            };
          }

          // List all services
          const services = await cache.getOrCompute(
            "services:list",
            runtimeTtl,
            () => listServices()
          );

          const filtered =
            filterType === "all"
              ? services
              : services.filter((s) => s.type === filterType);

          const active = filtered.filter((s) => s.activeState === "active");
          const failed = filtered.filter((s) => s.activeState === "failed");
          const other = filtered.filter(
            (s) => s.activeState !== "active" && s.activeState !== "failed"
          );

          return {
            status: failed.length > 0 ? "partial" : "ok",
            message: `${active.length} active, ${failed.length} failed, ${other.length} other`,
            data: {
              summary: {
                total: filtered.length,
                active: active.length,
                failed: failed.length,
                other: other.length,
              },
              services: filtered,
            },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to query services",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_services_logs ─────────────────────────────────────────────
    {
      name: "hwc_services_logs",
      description:
        "Get recent log output for a service. Supports time range and severity filtering.",
      inputSchema: {
        type: "object",
        properties: {
          service: {
            type: "string",
            description: "Service or container name",
          },
          lines: {
            type: "integer",
            default: 50,
            description: "Number of recent lines (max 500)",
          },
          since: {
            type: "string",
            default: "1h ago",
            description: "Time filter, e.g. '1h ago', '2025-04-01', 'today'",
          },
          priority: {
            type: "string",
            enum: ["emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"],
            description: "Minimum severity level",
          },
          grep: {
            type: "string",
            description: "Filter log lines containing this string",
          },
        },
        required: ["service"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const service = args.service as string;
          const lines = Math.min((args.lines as number) || 50, 500);
          const since = args.since as string | undefined;
          const priority = args.priority as string | undefined;
          const grep = args.grep as string | undefined;

          // Try multiple unit name patterns
          const candidates = [
            service,
            `podman-${service}`,
            `${service}.service`,
            `podman-${service}.service`,
          ];

          for (const unit of candidates) {
            const logLines = await getJournalLines(unit, lines, since, priority, grep);
            if (logLines.length > 0 || logLines.length === 0) {
              return {
                status: "ok",
                message: `${logLines.length} lines from ${unit}`,
                data: { service: unit, lineCount: logLines.length, lines: logLines },
              };
            }
          }

          return {
            status: "error",
            message: `No logs found for ${service}`,
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to get logs",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_services_container_stats ───────────────────────────────────
    {
      name: "hwc_services_container_stats",
      description:
        "Get real-time resource usage for running containers — CPU, memory, net/block I/O.",
      inputSchema: {
        type: "object",
        properties: {
          container: {
            type: "string",
            description: "Container name. Omit for all running containers.",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const container = args.container as string | undefined;
          const stats = await getContainerStats(container);

          return {
            status: "ok",
            message: `${stats.length} container(s)`,
            data: { stats },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to get container stats",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_services_compare_declared_vs_running ──────────────────────
    {
      name: "hwc_services_compare_declared_vs_running",
      description:
        "Compare what SHOULD be running (from systemd) vs what IS running. " +
        "Finds services that are enabled but down, or running but unexpected.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const [services, containers] = await Promise.all([
            listServices(),
            listContainers(),
          ]);

          const healthy = services.filter((s) => s.activeState === "active");
          const declaredButStopped = services.filter(
            (s) => s.activeState === "failed" || s.activeState === "inactive"
          );

          // Check for containers not tracked as systemd services
          const serviceNames = new Set(services.map((s) => s.name.replace("podman-", "").replace(".service", "")));
          const containerNames = containers.map((c) => {
            return c.Names?.[0] || "unknown";
          });
          const runningButUndeclared = containerNames.filter(
            (name: string) => !serviceNames.has(name)
          );

          return {
            status: declaredButStopped.length > 0 ? "partial" : "ok",
            message: `${healthy.length} healthy, ${declaredButStopped.length} stopped, ${runningButUndeclared.length} undeclared`,
            data: {
              healthy: healthy.map((s) => s.name),
              declaredButStopped: declaredButStopped.map((s) => ({
                name: s.name,
                state: s.activeState,
              })),
              runningButUndeclared,
            },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to compare services",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },
  ];
}
