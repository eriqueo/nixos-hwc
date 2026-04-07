/**
 * hwc_network_* tools — Tailscale, Caddy routes, VPN, firewall.
 */

import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { getStatus as getTailscaleStatus } from "../executors/tailscale.js";
import { TtlCache } from "../cache.js";
import { mcpError, catchError } from "../errors.js";

const cache = new TtlCache();

export function networkTools(runtimeTtl: number, nixosConfigPath?: string): ToolDef[] {
  return [
    {
      name: "hwc_network_tailscale_status",
      description:
        "Get Tailscale network status — self info, connected peers, IPs, online/offline state. " +
        "Collapses funnel-ingress-nodes into a summary. Read-only.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const status = await cache.getOrCompute(
            "tailscale:status",
            runtimeTtl,
            () => getTailscaleStatus()
          );

          // Collapse funnel-ingress-node entries into a summary
          const funnelNodes = status.peers.filter((p) =>
            p.hostname.startsWith("funnel-ingress-node")
          );
          const regularPeers = status.peers.filter((p) =>
            !p.hostname.startsWith("funnel-ingress-node")
          );
          const online = regularPeers.filter((p) => p.online);

          const collapsedPeers = [
            ...regularPeers,
            ...(funnelNodes.length > 0
              ? [{
                  hostname: `funnel-ingress-nodes (${funnelNodes.length} total)`,
                  ip: "",
                  os: "linux",
                  online: funnelNodes.some((f) => f.online),
                  exitNode: false,
                }]
              : []),
          ];

          return {
            status: "ok",
            message: `${online.length}/${regularPeers.length} peers online (+ ${funnelNodes.length} funnel nodes)`,
            data: { ...status, peers: collapsedPeers },
          };
        } catch (err) {
          return catchError("UNAVAILABLE", "Failed to get Tailscale status", err, "Is tailscaled running?");
        }
      },
    },

    {
      name: "hwc_network_caddy_routes",
      description:
        "Get Caddy reverse proxy configuration. Tries live admin API first, falls back to " +
        "parsing routes.nix. Optionally probes upstream health (slower). Read-only.",
      inputSchema: {
        type: "object",
        properties: {
          route: {
            type: "string",
            description: "Route name (e.g. 'jellyfin', 'sonarr') for full details. Omit for compact overview of all routes.",
          },
          check_health: {
            type: "boolean",
            default: false,
            description: "If true, probe each upstream for health (slower).",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const routeFilter = args.route as string | undefined;
          const checkHealth = args.check_health === true;

          // Try Caddy admin API first
          try {
            const response = await fetch("http://localhost:2019/config/", {
              headers: {
                "Content-Type": "application/json",
                Origin: "http://localhost",
              },
              signal: AbortSignal.timeout(5000),
            });

            if (response.ok) {
              const config = await response.json() as Record<string, unknown>;
              const apps = config.apps as Record<string, unknown> | undefined;
              const httpApp = apps?.http as Record<string, unknown> | undefined;
              const servers = httpApp?.servers as Record<string, unknown> | undefined;

              const routes: Array<Record<string, unknown>> = [];
              if (servers) {
                for (const [serverName, server] of Object.entries(servers)) {
                  const srv = server as Record<string, unknown>;
                  const srvRoutes = (srv.routes || []) as Array<Record<string, unknown>>;
                  const listen = (srv.listen || []) as string[];

                  for (const route of srvRoutes) {
                    routes.push({
                      server: serverName,
                      listen,
                      match: route.match,
                      handle: summarizeHandlers(route.handle as Array<Record<string, unknown>>),
                    });
                  }
                }
              }

              // Admin API returns raw Caddy config — pass through as-is
              // (routeFilter not applicable to live admin API format)
              return {
                status: "ok",
                message: `${routes.length} routes across ${Object.keys(servers || {}).length} servers (live)`,
                data: { source: "admin-api", routes, serverCount: Object.keys(servers || {}).length },
              };
            }

            // If admin API returned non-ok, fall through to config parsing
          } catch {
            // Admin API not reachable, fall through to config parsing
          }

          // Fallback: parse routes.nix from the declarative config
          if (nixosConfigPath) {
            const routesPath = join(nixosConfigPath, "domains/networking/routes.nix");
            try {
              const content = await readFile(routesPath, "utf-8");
              const routes = parseCaddyRoutes(content);

              // Optionally health-check upstreams
              if (checkHealth) {
                await Promise.all(
                  routes.map(async (r) => {
                    if (r.upstream) {
                      try {
                        const resp = await fetch(`http://${r.upstream}/`, {
                          signal: AbortSignal.timeout(3000),
                        });
                        r.healthy = resp.ok || resp.status < 500;
                      } catch {
                        r.healthy = false;
                      }
                    }
                  })
                );
              }

              // Single route detail
              if (routeFilter) {
                const match = routes.find((r) => r.name === routeFilter);
                if (!match) {
                  return mcpError({
                    type: "NOT_FOUND",
                    message: `Route not found: ${routeFilter}`,
                    suggestion: "Call without 'route' param to list all route names",
                    context: { available: routes.map((r) => r.name) },
                  });
                }
                return {
                  status: "ok",
                  message: `Route: ${match.name}`,
                  data: { source: "routes.nix", route: match },
                };
              }

              // Compact overview — drop upstream (internal plumbing)
              const compact = routes.map((r) => {
                const entry: Record<string, unknown> = { name: r.name, mode: r.mode };
                if (r.port) entry.port = r.port;
                if (r.path) entry.path = r.path;
                if (r.healthy !== undefined) entry.healthy = r.healthy;
                return entry;
              });

              return {
                status: "ok",
                message: `${routes.length} routes from routes.nix`,
                data: { source: "routes.nix", routes: compact },
              };
            } catch {
              // routes.nix not readable
            }
          }

          return mcpError({
            type: "UNAVAILABLE",
            message: "Caddy admin API returned 403 and routes.nix fallback unavailable",
            suggestion: "Caddy admin API may need 'admin { origins localhost }'. Check Caddy is running.",
          });
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to query Caddy config", err);
        }
      },
    },

    {
      name: "hwc_network_vpn_status",
      description:
        "Get Gluetun VPN status — connected server, public IP, port forwarding. " +
        "Requires Gluetun container running on port 8000.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const [ipResult, statusResult] = await Promise.allSettled([
            fetch("http://localhost:8000/v1/publicip/ip", {
              signal: AbortSignal.timeout(5000),
            }).then((r) => r.json()),
            fetch("http://localhost:8000/v1/openvpn/status", {
              signal: AbortSignal.timeout(5000),
            }).then((r) => r.json()),
          ]);

          return {
            status: "ok",
            message: "VPN status retrieved",
            data: {
              publicIp: ipResult.status === "fulfilled" ? ipResult.value : "unavailable",
              vpnStatus: statusResult.status === "fulfilled" ? statusResult.value : "unavailable",
            },
          };
        } catch (err) {
          return catchError("UNAVAILABLE", "Failed to get VPN status (Gluetun may not be running)", err, "Check that the Gluetun container is running on port 8000");
        }
      },
    },
  ];
}

interface ParsedRoute {
  name: string;
  mode: string;
  port?: number;
  upstream?: string;
  path?: string;
  healthy?: boolean;
}

function parseCaddyRoutes(content: string): ParsedRoute[] {
  const routes: ParsedRoute[] = [];
  const blockRegex = /\{\s*\n([^}]*?name\s*=\s*"[^"]+";[^}]*?)\}/g;
  let match: RegExpExecArray | null;

  while ((match = blockRegex.exec(content)) !== null) {
    const block = match[1];
    const nameMatch = block.match(/name\s*=\s*"([^"]+)"/);
    const modeMatch = block.match(/mode\s*=\s*"([^"]+)"/);
    const portMatch = block.match(/port\s*=\s*(\d+)/);
    const upstreamMatch = block.match(/upstream\s*=\s*"([^"]+)"/);
    const pathMatch = block.match(/path\s*=\s*"([^"]+)"/);

    if (nameMatch && modeMatch) {
      routes.push({
        name: nameMatch[1],
        mode: modeMatch[1],
        port: portMatch ? parseInt(portMatch[1], 10) : undefined,
        upstream: upstreamMatch?.[1],
        path: pathMatch?.[1],
      });
    }
  }
  return routes;
}

function summarizeHandlers(
  handlers: Array<Record<string, unknown>> | undefined
): Array<Record<string, unknown>> {
  if (!handlers) return [];
  return handlers.map((h) => {
    const summary: Record<string, unknown> = { handler: h.handler };
    if (h.handler === "reverse_proxy") {
      const upstreams = (h.upstreams || []) as Array<{ dial?: string }>;
      summary.upstreams = upstreams.map((u) => u.dial).filter(Boolean);
    }
    if (h.handler === "file_server") {
      summary.root = h.root;
    }
    return summary;
  });
}
