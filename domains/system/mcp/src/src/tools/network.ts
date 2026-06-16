/**
 * hwc_network — consolidated network tool (caddy, tunnels).
 */

import { readFile } from "node:fs/promises";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { getStatus as getTailscaleStatus } from "../executors/tailscale.js";
import { TtlCache } from "../cache.js";
import { mcpError, catchError } from "../errors.js";
import { contract } from "../result.js";

const cache = new TtlCache();

export function networkTools(runtimeTtl: number, nixosConfigPath?: string): ToolDef[] {
  return [
    {
      name: "hwc_network",
      description: "Network status. Actions: caddy (Caddy routes), tunnels (tunnel status).",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["caddy", "tunnels"],
            description: "Action to perform",
          },
          // [tunnels] params
          tunnel: {
            type: "string",
            enum: ["tailscale", "vpn", "all"],
            description: "[tunnels] Which tunnel to check (default: all)",
          },
          // [caddy] params
          route: {
            type: "string",
            description: "[caddy] Route name (e.g. 'jellyfin') for full details. Omit for compact overview.",
          },
          check_health: {
            type: "boolean",
            description: "[caddy] If true, probe each upstream for health (slower, default: false)",
          },
        },
        required: ["action"],
      },
      handler: async (args): Promise<ToolResult> => {
        const action = args.action as string;

        // ── tunnels ──────────────────────────────────────────────
        if (action === "tunnels") {
          try {
            const tunnel = (args.tunnel as string) || "all";
            const data: Record<string, unknown> = {};
            const parts: string[] = [];

            if (tunnel === "all" || tunnel === "tailscale") {
              try {
                const status = await cache.getOrCompute(
                  "tailscale:status",
                  runtimeTtl,
                  () => getTailscaleStatus()
                );

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

                data.tailscale = { ...status, peers: collapsedPeers };
                parts.push(`Tailscale: ${online.length}/${regularPeers.length} peers`);
              } catch {
                data.tailscale = { error: "tailscaled not reachable" };
                parts.push("Tailscale: down");
              }
            }

            if (tunnel === "all" || tunnel === "vpn") {
              try {
                const [ipResult, statusResult] = await Promise.allSettled([
                  fetch("http://localhost:8000/v1/publicip/ip", {
                    signal: AbortSignal.timeout(5000),
                  }).then((r) => r.json()),
                  fetch("http://localhost:8000/v1/openvpn/status", {
                    signal: AbortSignal.timeout(5000),
                  }).then((r) => r.json()),
                ]);

                data.vpn = {
                  publicIp: ipResult.status === "fulfilled" ? ipResult.value : "unavailable",
                  vpnStatus: statusResult.status === "fulfilled" ? statusResult.value : "unavailable",
                };
                parts.push("VPN: connected");
              } catch {
                data.vpn = { error: "Gluetun not reachable" };
                parts.push("VPN: down");
              }
            }

            // Universal Result Contract view (status): one check per tunnel.
            const checks: Array<{ status: string; name: string; note?: string }> = [];
            if (data.tailscale) {
              const ts = data.tailscale as Record<string, unknown>;
              if (ts.error) {
                checks.push({ status: "down", name: "tailscale", note: String(ts.error) });
              } else {
                const peers = (ts.peers || []) as Array<{ hostname: string; online: boolean }>;
                const onlineCount = peers.filter((p) => p.online).length;
                checks.push({ status: "up", name: "tailscale", note: `${onlineCount}/${peers.length} peers online` });
              }
            }
            if (data.vpn) {
              const vpn = data.vpn as Record<string, unknown>;
              if (vpn.error) {
                checks.push({ status: "down", name: "vpn", note: String(vpn.error) });
              } else {
                checks.push({ status: "up", name: "vpn", note: "Gluetun reachable" });
              }
            }
            const overall = checks.some((c) => c.status === "down") ? "warning" : "ok";

            return {
              status: "ok",
              message: parts.join(", "),
              data,
              view: contract("status", "Network", { overall, checks }, { source: "hwc_network", action }),
            };
          } catch (err) {
            return catchError("UNAVAILABLE", "Failed to get tunnel status", err);
          }
        }

        // ── caddy ────────────────────────────────────────────────
        if (action === "caddy") {
          try {
            const routeFilter = args.route as string | undefined;
            const checkHealth = args.check_health === true;

            // Try Caddy admin API first
            try {
              const response = await fetch("http://localhost:2019/config/", {
                headers: { "Content-Type": "application/json", Origin: "http://localhost" },
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

                const source = "admin-api";
                return {
                  status: "ok",
                  message: `${routes.length} routes across ${Object.keys(servers || {}).length} servers (live)`,
                  data: { source, routes, serverCount: Object.keys(servers || {}).length },
                  view: contract("status", "Network", {
                    overall: "ok",
                    checks: [{ status: "up", name: "caddy", note: `${routes.length} routes (${source})` }],
                  }, { source: "hwc_network", action }),
                };
              }
            } catch {
              // Admin API not reachable, fall through to config parsing
            }

            // Fallback: parse routes.nix
            if (nixosConfigPath) {
              const routesPath = join(nixosConfigPath, "domains/networking/routes.nix");
              try {
                const content = await readFile(routesPath, "utf-8");
                const routes = parseCaddyRoutes(content);

                if (checkHealth) {
                  await Promise.all(
                    routes.map(async (r) => {
                      if (r.upstream) {
                        try {
                          const resp = await fetch(`http://${r.upstream}/`, { signal: AbortSignal.timeout(3000) });
                          r.healthy = resp.ok || resp.status < 500;
                        } catch {
                          r.healthy = false;
                        }
                      }
                    })
                  );
                }

                if (routeFilter) {
                  const match = routes.find((r) => r.name === routeFilter);
                  if (!match) {
                    return mcpError({ type: "NOT_FOUND", message: `Route not found: ${routeFilter}`, suggestion: "Call without 'route' param to list all route names", context: { available: routes.map((r) => r.name) } });
                  }
                  return { status: "ok", message: `Route: ${match.name}`, data: { source: "routes.nix", route: match } };
                }

                const compact = routes.map((r) => {
                  const entry: Record<string, unknown> = { name: r.name, mode: r.mode };
                  if (r.port) entry.port = r.port;
                  if (r.path) entry.path = r.path;
                  if (r.healthy !== undefined) entry.healthy = r.healthy;
                  return entry;
                });

                const source = "routes.nix";
                return {
                  status: "ok",
                  message: `${routes.length} routes from routes.nix`,
                  data: { source, routes: compact },
                  view: contract("status", "Network", {
                    overall: "ok",
                    checks: [{ status: "ok", name: "caddy", note: `${routes.length} routes (${source})` }],
                  }, { source: "hwc_network", action }),
                };
              } catch {
                // routes.nix not readable
              }
            }

            return mcpError({ type: "UNAVAILABLE", message: "Caddy admin API returned 403 and routes.nix fallback unavailable", suggestion: "Caddy admin API may need 'admin { origins localhost }'. Check Caddy is running." });
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to query Caddy config", err);
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
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
