/**
 * hwc_media_* tools — arr stack status, download queues, library stats.
 */

import type { ToolDef, ToolResult } from "../types.js";

const ARR_SERVICES = [
  { name: "sonarr", port: 8989 },
  { name: "radarr", port: 7878 },
  { name: "lidarr", port: 8686 },
  { name: "readarr", port: 8787 },
  { name: "prowlarr", port: 9696 },
] as const;

export function mediaTools(): ToolDef[] {
  return [
    {
      name: "hwc_media_arr_status",
      description:
        "Get status of the *arr stack — Sonarr, Radarr, Lidarr, Readarr, Prowlarr. " +
        "Checks system status and health endpoints.",
      inputSchema: {
        type: "object",
        properties: {
          service: {
            type: "string",
            enum: ["sonarr", "radarr", "lidarr", "readarr", "prowlarr", "all"],
            default: "all",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const filter = args.service as string || "all";
          const services = filter === "all"
            ? ARR_SERVICES
            : ARR_SERVICES.filter((s) => s.name === filter);

          const results = await Promise.all(
            services.map(async (svc) => {
              try {
                // Check if the service is responding at all
                const statusResp = await fetch(
                  `http://localhost:${svc.port}/api/v3/system/status`,
                  {
                    headers: { Accept: "application/json" },
                    signal: AbortSignal.timeout(5000),
                  }
                );

                if (statusResp.status === 401) {
                  // API key required — service is running but we can't query it
                  return { name: svc.name, port: svc.port, running: true, apiKeyRequired: true };
                }

                if (!statusResp.ok) {
                  return { name: svc.name, port: svc.port, running: true, httpStatus: statusResp.status };
                }

                const status = await statusResp.json() as Record<string, unknown>;

                // Try health check
                let health: unknown[] = [];
                try {
                  const healthResp = await fetch(
                    `http://localhost:${svc.port}/api/v3/health`,
                    {
                      headers: { Accept: "application/json" },
                      signal: AbortSignal.timeout(3000),
                    }
                  );
                  if (healthResp.ok) health = await healthResp.json() as unknown[];
                } catch {
                  // health endpoint may also need API key
                }

                return {
                  name: svc.name,
                  port: svc.port,
                  running: true,
                  version: status.version,
                  healthWarnings: Array.isArray(health) ? health.length : 0,
                };
              } catch {
                return { name: svc.name, port: svc.port, running: false };
              }
            })
          );

          const running = results.filter((r) => r.running);
          return {
            status: "ok",
            message: `${running.length}/${results.length} arr services responding`,
            data: { services: results },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to check arr status",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    {
      name: "hwc_media_download_queue",
      description:
        "Get the current download queue across SABnzbd and qBittorrent.",
      inputSchema: {
        type: "object",
        properties: {
          client: {
            type: "string",
            enum: ["sabnzbd", "qbittorrent", "all"],
            default: "all",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const client = (args.client as string) || "all";
          const data: Record<string, unknown> = {};

          if (client === "all" || client === "sabnzbd") {
            try {
              const resp = await fetch(
                "http://localhost:8081/sabnzbd/api?mode=queue&output=json",
                { signal: AbortSignal.timeout(5000) }
              );
              if (resp.ok) {
                const queue = await resp.json() as Record<string, unknown>;
                const q = queue.queue as Record<string, unknown> | undefined;
                data.sabnzbd = {
                  speed: q?.speed,
                  remaining: q?.timeleft,
                  items: Array.isArray(q?.slots) ? (q.slots as unknown[]).length : 0,
                };
              } else {
                data.sabnzbd = { error: `HTTP ${resp.status} (API key may be required)` };
              }
            } catch {
              data.sabnzbd = { error: "Not reachable" };
            }
          }

          if (client === "all" || client === "qbittorrent") {
            try {
              const resp = await fetch(
                "http://localhost:8080/api/v2/torrents/info",
                { signal: AbortSignal.timeout(5000) }
              );
              if (resp.ok) {
                const torrents = await resp.json() as Array<Record<string, unknown>>;
                const active = torrents.filter((t) => t.state === "downloading" || t.state === "uploading");
                data.qbittorrent = {
                  totalTorrents: torrents.length,
                  active: active.length,
                };
              } else {
                data.qbittorrent = { error: `HTTP ${resp.status} (auth may be required)` };
              }
            } catch {
              data.qbittorrent = { error: "Not reachable" };
            }
          }

          return {
            status: "ok",
            message: "Download queue status",
            data,
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to check download queue",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },
  ];
}
