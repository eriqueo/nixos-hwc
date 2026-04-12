/**
 * hwc_services_* tools — query and manage live service state.
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
      name: "hwc_services_status",
      description:
        "Get runtime status of a specific service or all services. Returns systemd state, uptime, memory, and recent logs. " +
        "Pass a service name (e.g. 'jellyfin', 'caddy') or omit for overview. " +
        "Accepts short names — automatically tries podman- prefix and .service suffix.",
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

            return mcpError({
              type: "NOT_FOUND",
              message: `Service not found: ${serviceName}`,
              suggestion: "Use the full unit name (e.g. 'caddy', 'jellyfin') or check hwc_services_status without a name to list all services",
              context: { searched: serviceName, tried: candidates },
            });
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

          // Unhealthy services get full details; healthy ones are just names
          const unhealthy = [...failed, ...other];

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
              unhealthy,
              healthy: active.map((s) => s.name),
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to query services", err, "Check that systemctl and podman are accessible");
        }
      },
    },

    // ── hwc_services_logs ─────────────────────────────────────────────
    {
      name: "hwc_services_logs",
      description:
        "Get recent log output from journald for a service. Supports time range (since), severity filtering (priority), and text search (grep). " +
        "Max 500 lines. Pass service short name — unit resolution is automatic.",
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

          // Try each candidate and pick the one with the most log lines
          let bestUnit = candidates[0];
          let bestLines: string[] = [];

          for (const unit of candidates) {
            try {
              const logLines = await getJournalLines(unit, lines, since, priority, grep);
              if (logLines.length > bestLines.length) {
                bestUnit = unit;
                bestLines = logLines;
              }
              // If we got results, no need to try more candidates
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
      },
    },

    // ── hwc_services_container_stats ───────────────────────────────────
    {
      name: "hwc_services_container_stats",
      description:
        "Get real-time resource usage for running Podman containers — CPU, memory, net/block IO. " +
        "Pass a container name or omit for all. Read-only.",
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

          // Overview mode (no specific container): slim output — drop fields that are
          // always empty (memLimit, netIO, blockIO from systemd fallback) or useless
          // (id=PID, pids=always 1, status=always "running").
          const data = container
            ? { stats }
            : {
                stats: stats.map((s) => ({
                  name: s.name,
                  cpu: s.cpu,
                  memory: s.memory,
                })),
              };

          return {
            status: "ok",
            message: `${stats.length} container(s)`,
            data,
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to get container stats", err, "Is podman running? Check with hwc_services_status type='container'");
        }
      },
    },

    // ── hwc_services_show ─────────────────────────────────────────────
    {
      name: "hwc_services_show",
      description:
        "Show the full effective systemd unit configuration — security sandbox (ProtectHome, ReadWritePaths, NoNewPrivileges), " +
        "resource limits, environment, exec paths, and dependencies. " +
        "Use when diagnosing permission, sandbox, or startup issues. Read-only.",
      inputSchema: {
        type: "object",
        properties: {
          service: {
            type: "string",
            description: "Service name (e.g. 'hwc-infra-mcp', 'caddy', 'jellyfin')",
          },
          properties: {
            type: "array",
            items: { type: "string" },
            description:
              "Specific properties to query (default: security + resource properties). " +
              "Pass ['all'] for every property.",
          },
        },
        required: ["service"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const service = args.service as string;
          const requestedProps = args.properties as string[] | undefined;

          // Try to resolve the unit name
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
          // Even if inactive, use the first candidate that doesn't error
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
              suggestion: "Use hwc_services_status to list available services, then pass the exact name",
              context: { searched: service, tried: candidates },
            });
          }

          // Default to security + resource + identity properties
          const defaultProps = [
            // Identity
            "User", "Group", "SupplementaryGroups", "DynamicUser",
            // Security sandbox
            "ProtectHome", "ProtectSystem", "PrivateTmp", "PrivateDevices",
            "PrivateNetwork", "ProtectKernelTunables", "ProtectKernelModules",
            "ProtectControlGroups", "NoNewPrivileges", "SystemCallFilter",
            "CapabilityBoundingSet", "AmbientCapabilities",
            // Paths
            "ReadWritePaths", "ReadOnlyPaths", "InaccessiblePaths",
            "ExecSearchPath", "WorkingDirectory", "RootDirectory",
            // Exec
            "ExecStart", "ExecStartPre", "ExecStartPost",
            "Environment", "EnvironmentFiles",
            // Resources
            "MemoryMax", "MemoryHigh", "CPUQuota", "TasksMax",
            "LimitNOFILE", "Nice",
            // State
            "ActiveState", "SubState", "LoadState",
            "MainPID", "ControlPID", "NRestarts",
            "ActiveEnterTimestamp", "InactiveEnterTimestamp",
            // Dependencies
            "After", "Requires", "Wants", "BindsTo",
            "RequiredBy", "WantedBy",
          ];

          let propsToQuery: string[];
          if (requestedProps?.includes("all")) {
            // Query everything — no --property filter
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
            return mcpError({
              type: "COMMAND_FAILED",
              message: `systemctl show failed for ${resolvedUnit}`,
              error: result.stderr.slice(0, 500),
              context: { unit: resolvedUnit },
            });
          }

          // Parse into structured key=value
          const props: Record<string, string> = {};
          for (const line of result.stdout.split("\n")) {
            const idx = line.indexOf("=");
            if (idx > 0) {
              const key = line.slice(0, idx);
              const val = line.slice(idx + 1);
              // Skip empty/unset values for cleaner output
              if (val && val !== "[not set]" && val !== "0" && val !== "no") {
                props[key] = val;
              }
            }
          }

          // Also include empty/zero values that are security-relevant
          const securityRelevant = [
            "ProtectHome", "ProtectSystem", "NoNewPrivileges",
            "PrivateTmp", "DynamicUser", "User",
          ];
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
      },
    },

    // ── hwc_services_compare_declared_vs_running ──────────────────────
    {
      name: "hwc_services_compare_declared_vs_running",
      description:
        "Compare what should be running (enabled systemd units) vs what is running. " +
        "Finds services that are enabled but down, or containers running without systemd management.",
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
          return catchError("INTERNAL_ERROR", "Failed to compare services", err, "Check that systemctl and podman are accessible");
        }
      },
    },

    // ── hwc_services_by_domain ──────────────────────────────────────
    {
      name: "hwc_services_by_domain",
      description:
        "Map NixOS domain names to their associated services, ports, and config files. " +
        "Pass a domain (e.g. 'media', 'monitoring', 'mail') or omit for all.",
      inputSchema: {
        type: "object",
        properties: {
          domain: {
            type: "string",
            description: "Domain name (e.g. 'media', 'monitoring', 'mail', 'networking'). Omit for all.",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          if (!nixosConfigPath) {
            return mcpError({
              type: "UNAVAILABLE",
              message: "nixosConfigPath not configured",
              suggestion: "Set HWC_NIXOS_CONFIG_PATH environment variable",
            });
          }

          const filterDomain = args.domain as string | undefined;
          const domainsDir = join(nixosConfigPath, "domains");

          let domainDirs: string[];
          try {
            const entries = await readdir(domainsDir, { withFileTypes: true });
            domainDirs = entries.filter((e) => e.isDirectory()).map((e) => e.name);
          } catch {
            return mcpError({
              type: "NOT_FOUND",
              message: "domains/ directory not found",
              suggestion: "Check HWC_NIXOS_CONFIG_PATH points to the nixos-hwc repo",
            });
          }

          if (filterDomain) {
            domainDirs = domainDirs.filter((d) => d === filterDomain);
            if (domainDirs.length === 0) {
              return mcpError({
                type: "NOT_FOUND",
                message: `Domain '${filterDomain}' not found`,
                suggestion: "Use hwc_config_list_domains to see available domains",
              });
            }
          }

          // Scan each domain for service/container definitions
          const result: Array<{
            domain: string;
            services: Array<{ name: string; type: "native" | "container"; file: string; port?: number; live?: boolean }>;
          }> = [];

          // Get live services for cross-reference
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

            // Cross-reference with live state
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

          // Overview mode: compact per-domain summary (live names only)
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
      },
    },
  ];
}

/** Recursively scan a domain directory for systemd service and container definitions. */
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

        // Match systemd.services.<name>
        const svcRegex = /systemd\.services\.([\w-]+)\s*=/g;
        let match;
        while ((match = svcRegex.exec(content)) !== null) {
          const name = match[1];
          if (!results.some((r) => r.name === name)) {
            const directPort = content.match(new RegExp(`${name}[\\s\\S]{0,500}?(?:listen|port).*?(\\d{4,5})`, "i"));
            results.push({
              name,
              type: "native",
              file: relFile,
              port: directPort ? parseInt(directPort[1], 10) : undefined,
            });
          }
        }

        // Match oci-containers.containers.<name> (podman)
        const containerRegex = /oci-containers\.containers\.([\w-]+)\s*=/g;
        while ((match = containerRegex.exec(content)) !== null) {
          const name = match[1];
          if (!results.some((r) => r.name === name)) {
            // Try to extract a port mapping
            const portMapMatch = content.match(new RegExp(`${name}[\\s\\S]{0,1000}?ports\\s*=\\s*\\[[^\\]]*?"(\\d+):\\d+"`, "i"));
            results.push({
              name,
              type: "container",
              file: relFile,
              port: portMapMatch ? parseInt(portMapMatch[1], 10) : undefined,
            });
          }
        }
      } catch {
        // Skip unreadable files
      }
    }
  }
}
