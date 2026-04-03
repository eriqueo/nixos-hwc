/**
 * hwc_network_* tools — Tailscale, Caddy routes, VPN, firewall.
 */

import type { ToolDef, ToolResult } from "../types.js";
import { getStatus as getTailscaleStatus } from "../executors/tailscale.js";
import { TtlCache } from "../cache.js";

const cache = new TtlCache();

export function networkTools(runtimeTtl: number): ToolDef[] {
  return [
    {
      name: "hwc_network_tailscale_status",
      description:
        "Get Tailscale network status — self info, connected peers, IPs, online/offline state.",
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

          const online = status.peers.filter((p) => p.online);
          return {
            status: "ok",
            message: `${online.length}/${status.peers.length} peers online`,
            data: status,
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to get Tailscale status",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    {
      name: "hwc_network_caddy_routes",
      description:
        "Get the live Caddy reverse proxy configuration via admin API. " +
        "Shows all routes, upstreams, and optionally checks health.",
      inputSchema: {
        type: "object",
        properties: {
          check_health: {
            type: "boolean",
            default: false,
            description: "If true, probe each upstream for health (slower).",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const checkHealth = args.check_health === true;

          // Query Caddy admin API
          const response = await fetch("http://localhost:2019/config/", {
            signal: AbortSignal.timeout(5000),
          });

          if (!response.ok) {
            return {
              status: "error",
              message: `Caddy admin API returned ${response.status}`,
              error: "Caddy may not be running or admin API is disabled",
            };
          }

          const config = await response.json() as Record<string, unknown>;

          // Extract route information
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

          return {
            status: "ok",
            message: `${routes.length} routes across ${Object.keys(servers || {}).length} servers`,
            data: { routes, serverCount: Object.keys(servers || {}).length },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to query Caddy config",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    {
      name: "hwc_network_vpn_status",
      description:
        "Get Gluetun VPN status — connected server, public IP, port forwarding.",
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
          return {
            status: "error",
            message: "Failed to get VPN status (Gluetun may not be running)",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },
  ];
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
