/**
 * hwc_services — consolidated services tool (status, logs, show, by_domain, compare, container_stats).
 */

import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { listServices, getServiceStatus, getJournalLines } from "../executors/systemd.js";
import { getContainerStats, listContainers } from "../executors/podman.js";
import { safeExec } from "../executors/shell.js";
import { TtlCache } from "../cache.js";
import { mcpError, catchError } from "../errors.js";

const cache = new TtlCache();

export function servicesTools(runtimeTtl: number, nixosConfigPath?: string): ToolDef[] {
  return [
    {
      name: "hwc_services",
      description:
        "Service management. action=status with no params returns compact overview. " +
        "Actions: status, logs, show, by_domain, compare, container_stats.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["status", "logs", "show", "by_domain", "compare", "container_stats"],
            description: "Action to perform",
          },
          // [status/logs/show] params
          service: {
            type: "string",
            description:
              "[status/logs/show] Service name (e.g. 'jellyfin', 'n8n', 'caddy'). " +
              "For containers, podman- prefix is added automatically. Omit for overview.",
          },
          type: {
            type: "string",
            enum: ["all", "container", "native"],
            description: "[status] Filter by service type (default: all)",
          },
          // [logs] params
          lines: {
            type: "integer",
            description: "[logs] Number of recent lines (max 500, default 50)",
          },
          since: {
            type: "string",
            description: "[logs] Time filter, e.g. '1h ago', '2025-04-01', 'today' (default: 1h ago)",
          },
          priority: {
            type: "string",
            enum: ["emerg", "alert", "crit", "err", "warning", "notice", "info", "debug"],
            description: "[logs] Minimum severity level",
          },
          grep: {
            type: "string",
            description: "[logs] Filter log lines containing this string",
          },
          // [show] params
          properties: {
            type: "array",
            items: { type: "string" },
            description: "[show] Specific properties to query (default: security + resource). Pass ['all'] for everything.",
          },
          // [by_domain] params
          domain: {
            type: "string",
            description: "[by_domain] Domain name (e.g. 'media', 'monitoring'). Omit for all.",
          },
          // [container_stats] params
          container: {
            type: "string",
            description: "[container_stats] Container name. Omit for all running containers.",
          },
        },
        required: ["action"],
      },
      handler: async (args): Promise<ToolResult> => {
        const action = args.action as string;

        // ── status ───────────────────────────────────────────────
        if (action === "status") {
          try {
            const serviceName = args.service as string | undefined;
            const filterType = (args.type as string) || "all";

            if (serviceName) {
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

              return mcpError({
                type: "NOT_FOUND",
                message: `Service not found: ${serviceName}`,
                suggestion: "Use hwc_services action=status without a name to list all services",
                context: { searched: serviceName, tried: candidates },
              });
            }

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

            const unhealthy = [...failed, ...other];

            return {
              status: failed.length > 0 ? "partial" : "ok",
              message: `${active.length} active, ${failed.length} failed, ${other.length} other`,
              data: {
                summary: { total: filtered.length, active: active.length, failed: failed.length, other: other.length },
                unhealthy,
                healthy: active.map((s) => s.name),
              },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to query services", err, "Check that systemctl and podman are accessible");
          }
        }

        // ── logs ─────────────────────────────────────────────────
        if (action === "logs") {
          try {
            const service = args.service as string;
            if (!service) {
              return mcpError({ type: "VALIDATION_ERROR", message: "service is required for action=logs" });
            }
            const lines = Math.min((args.lines as number) || 50, 500);
            const since = args.since as string | undefined;
            const priority = args.priority as string | undefined;
            const grep = args.grep as string | undefined;

            const candidates = [
              service,
              `podman-${service}`,
              `${service}.service`,
              `podman-${service}.service`,
            ];

            let bestUnit = candidates[0];
            let bestLines: string[] = [];

            for (const unit of candidates) {
              try {
                const logLines = await getJournalLines(unit, lines, since, priority, grep);
                if (logLines.length > bestLines.length) {
                  bestUnit = unit;
                  bestLines = logLines;
                }
                if (bestLines.length > 0) break;
              } catch {
                continue;
              }
            }

            return {
              status: "ok",
              message: `${bestLines.length} lines from ${bestUnit}`,
              data: { service: bestUnit, lineCount: bestLines.length, lines: bestLines },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to get logs", err, "Check that journalctl is accessible and the service name is correct");
          }
        }

        // ── container_stats ──────────────────────────────────────
        if (action === "container_stats") {
          try {
            const container = args.container as string | undefined;
            const stats = await getContainerStats(container);

            const data = container
              ? { stats }
              : { stats: stats.map((s) => ({ name: s.name, cpu: s.cpu, memory: s.memory })) };

            return { status: "ok", message: `${stats.length} container(s)`, data };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to get container stats", err, "Is podman running? Check with hwc_services action=status type='container'");
          }
        }

        // ── show ─────────────────────────────────────────────────
        if (action === "show") {
          try {
            const service = args.service as string;
            if (!service) {
              return mcpError({ type: "VALIDATION_ERROR", message: "service is required for action=show" });
            }
            const requestedProps = args.properties as string[] | undefined;

            const candidates = [
              service,
              `${service}.service`,
              `podman-${service}`,
              `podman-${service}.service`,
            ];

            let resolvedUnit: string | null = null;
            for (const c of candidates) {
              const check = await safeExec("systemctl", ["show", c, "--property=ActiveState"]);
              if (check.exitCode === 0 && !check.stdout.includes("inactive") && check.stdout.includes("=")) {
                resolvedUnit = c;
                break;
              }
            }
            if (!resolvedUnit) {
              for (const c of candidates) {
                const check = await safeExec("systemctl", ["show", c, "--property=LoadState"]);
                if (check.exitCode === 0 && check.stdout.includes("loaded")) {
                  resolvedUnit = c;
                  break;
                }
              }
            }
            if (!resolvedUnit) {
              return mcpError({
                type: "NOT_FOUND",
                message: `Service not found: ${service}`,
                suggestion: "Use hwc_services action=status to list available services, then pass the exact name",
                context: { searched: service, tried: candidates },
              });
            }

            const defaultProps = [
              "User", "Group", "SupplementaryGroups", "DynamicUser",
              "ProtectHome", "ProtectSystem", "PrivateTmp", "PrivateDevices",
              "PrivateNetwork", "ProtectKernelTunables", "ProtectKernelModules",
              "ProtectControlGroups", "NoNewPrivileges", "SystemCallFilter",
              "CapabilityBoundingSet", "AmbientCapabilities",
              "ReadWritePaths", "ReadOnlyPaths", "InaccessiblePaths",
              "ExecSearchPath", "WorkingDirectory", "RootDirectory",
              "ExecStart", "ExecStartPre", "ExecStartPost",
              "Environment", "EnvironmentFiles",
              "MemoryMax", "MemoryHigh", "CPUQuota", "TasksMax",
              "LimitNOFILE", "Nice",
              "ActiveState", "SubState", "LoadState",
              "MainPID", "ControlPID", "NRestarts",
              "ActiveEnterTimestamp", "InactiveEnterTimestamp",
              "After", "Requires", "Wants", "BindsTo",
              "RequiredBy", "WantedBy",
            ];

            let propsToQuery: string[];
            if (requestedProps?.includes("all")) {
              propsToQuery = [];
            } else {
              propsToQuery = requestedProps?.length ? requestedProps : defaultProps;
            }

            const sysArgs = ["show", resolvedUnit, "--no-pager"];
            if (propsToQuery.length > 0) {
              sysArgs.push("--property=" + propsToQuery.join(","));
            }

            const result = await safeExec("systemctl", sysArgs, { timeout: 10000, maxBuffer: 512 * 1024 });
            if (result.exitCode !== 0) {
              return mcpError({ type: "COMMAND_FAILED", message: `systemctl show failed for ${resolvedUnit}`, error: result.stderr.slice(0, 500), context: { unit: resolvedUnit } });
            }

            const props: Record<string, string> = {};
            for (const line of result.stdout.split("\n")) {
              const idx = line.indexOf("=");
              if (idx > 0) {
                const key = line.slice(0, idx);
                const val = line.slice(idx + 1);
                if (val && val !== "[not set]" && val !== "0" && val !== "no") {
                  props[key] = val;
                }
              }
            }

            const securityRelevant = ["ProtectHome", "ProtectSystem", "NoNewPrivileges", "PrivateTmp", "DynamicUser", "User"];
            for (const line of result.stdout.split("\n")) {
              const idx = line.indexOf("=");
              if (idx > 0) {
                const key = line.slice(0, idx);
                if (securityRelevant.includes(key) && !(key in props)) {
                  props[key] = line.slice(idx + 1);
                }
              }
            }

            return {
              status: "ok",
              message: `${Object.keys(props).length} properties for ${resolvedUnit}`,
              data: { unit: resolvedUnit, properties: props },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to show service config", err);
          }
        }

        // ── compare ──────────────────────────────────────────────
        if (action === "compare") {
          try {
            const [services, containers] = await Promise.all([
              listServices(),
              listContainers(),
            ]);

            const healthy = services.filter((s) => s.activeState === "active");
            const declaredButStopped = services.filter(
              (s) => s.activeState === "failed" || s.activeState === "inactive"
            );

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
                declaredButStopped: declaredButStopped.map((s) => ({ name: s.name, state: s.activeState })),
                runningButUndeclared,
              },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to compare services", err, "Check that systemctl and podman are accessible");
          }
        }

        // ── by_domain ────────────────────────────────────────────
        if (action === "by_domain") {
          try {
            if (!nixosConfigPath) {
              return mcpError({ type: "UNAVAILABLE", message: "nixosConfigPath not configured", suggestion: "Set HWC_NIXOS_CONFIG_PATH environment variable" });
            }

            const filterDomain = args.domain as string | undefined;
            const domainsDir = join(nixosConfigPath, "domains");

            let domainDirs: string[];
            try {
              const entries = await readdir(domainsDir, { withFileTypes: true });
              domainDirs = entries.filter((e) => e.isDirectory()).map((e) => e.name);
            } catch {
              return mcpError({ type: "NOT_FOUND", message: "domains/ directory not found", suggestion: "Check HWC_NIXOS_CONFIG_PATH points to the nixos-hwc repo" });
            }

            if (filterDomain) {
              domainDirs = domainDirs.filter((d) => d === filterDomain);
              if (domainDirs.length === 0) {
                return mcpError({ type: "NOT_FOUND", message: `Domain '${filterDomain}' not found`, suggestion: "Use hwc_config action=list_domains to see available domains" });
              }
            }

            const result: Array<{
              domain: string;
              services: Array<{ name: string; type: "native" | "container"; file: string; port?: number; live?: boolean }>;
            }> = [];

            const liveServices = await cache.getOrCompute(
              "services:list",
              runtimeTtl,
              () => listServices(),
            );
            const liveNames = new Set(liveServices.map((s) => s.name.replace(".service", "")));

            for (const domain of domainDirs) {
              const domainPath = join(domainsDir, domain);
              const services: Array<{ name: string; type: "native" | "container"; file: string; port?: number; live?: boolean }> = [];

              await scanDomainForServices(domainPath, domain, services);

              for (const svc of services) {
                const candidates = [svc.name, `podman-${svc.name}`];
                svc.live = candidates.some((c) => liveNames.has(c));
              }

              if (services.length > 0 || filterDomain) {
                result.push({ domain, services });
              }
            }

            result.sort((a, b) => a.domain.localeCompare(b.domain));
            const totalServices = result.reduce((sum, d) => sum + d.services.length, 0);

            if (!filterDomain) {
              const compact = result.map((d) => {
                const live = d.services.filter((s) => s.live);
                const expectedLive = d.services.filter((s) => s.type === "container" || s.live);
                const notableOffline = expectedLive.filter((s) => !s.live).map((s) => s.name);
                return {
                  domain: d.domain,
                  liveCount: live.length,
                  declaredCount: d.services.length,
                  live: live.map((s) => s.name),
                  ...(notableOffline.length > 0 ? { notableOffline } : {}),
                };
              });
              const totalLive = compact.reduce((sum, d) => sum + d.liveCount, 0);
              return {
                status: "ok",
                message: `${totalLive} live services across ${compact.length} domains (${totalServices} declared)`,
                data: { domains: compact },
              };
            }

            return {
              status: "ok",
              message: `${totalServices} services across ${result.length} domains`,
              data: { domains: result },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to map services by domain", err);
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
      },
    },
  ];
}

async function scanDomainForServices(
  dir: string,
  domain: string,
  results: Array<{ name: string; type: "native" | "container"; file: string; port?: number }>,
): Promise<void> {
  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory() && entry.name !== "node_modules" && entry.name !== "dist") {
      await scanDomainForServices(fullPath, domain, results);
    } else if (entry.name.endsWith(".nix")) {
      try {
        const content = await readFile(fullPath, "utf-8");
        const relFile = fullPath.split(`domains/${domain}/`)[1] || entry.name;

        const svcRegex = /systemd\.services\.([\w-]+)\s*=/g;
        let match;
        while ((match = svcRegex.exec(content)) !== null) {
          const name = match[1];
          if (!results.some((r) => r.name === name)) {
            const directPort = content.match(new RegExp(`${name}[\\s\\S]{0,500}?(?:listen|port).*?(\\d{4,5})`, "i"));
            results.push({ name, type: "native", file: relFile, port: directPort ? parseInt(directPort[1], 10) : undefined });
          }
        }

        const containerRegex = /oci-containers\.containers\.([\w-]+)\s*=/g;
        while ((match = containerRegex.exec(content)) !== null) {
          const name = match[1];
          if (!results.some((r) => r.name === name)) {
            const portMapMatch = content.match(new RegExp(`${name}[\\s\\S]{0,1000}?ports\\s*=\\s*\\[[^\\]]*?"(\\d+):\\d+"`, "i"));
            results.push({ name, type: "container", file: relFile, port: portMapMatch ? parseInt(portMapMatch[1], 10) : undefined });
          }
        }
      } catch {
        // Skip unreadable files
      }
    }
  }
}
