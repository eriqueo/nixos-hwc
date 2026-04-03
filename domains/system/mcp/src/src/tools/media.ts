/**
 * hwc_media_* tools — arr stack status, download queues, library stats.
 */

import { readFile } from "node:fs/promises";
import type { ToolDef, ToolResult } from "../types.js";
import { catchError } from "../errors.js";

const ARR_SERVICES = [
  { name: "sonarr", port: 8989 },
  { name: "radarr", port: 7878 },
  { name: "lidarr", port: 8686 },
  { name: "readarr", port: 8787 },
  { name: "prowlarr", port: 9696 },
] as const;

/** Read an agenix secret file, returning null if not readable. */
async function readSecret(name: string): Promise<string | null> {
  try {
    const content = await readFile(`/run/agenix/${name}`, "utf-8");
    return content.trim();
  } catch {
    return null;
  }
}

/** Read SABnzbd API key from its config file. */
async function getSabnzbdApiKey(): Promise<string | null> {
  const configPaths = [
    "/mnt/hot/appdata/sabnzbd/config/sabnzbd.ini",
    "/mnt/hot/appdata/sabnzbd/sabnzbd.ini",
  ];

  for (const path of configPaths) {
    try {
      const content = await readFile(path, "utf-8");
      const match = content.match(/^api_key\s*=\s*(.+)$/m);
      if (match?.[1]?.trim()) return match[1].trim();
    } catch {
      continue;
    }
  }
  return null;
}

export function mediaTools(): ToolDef[] {
  return [
    {
      name: "hwc_media_arr_status",
      description:
        "Get status of the *arr stack (Sonarr, Radarr, Lidarr, Readarr, Prowlarr). " +
        "Checks system status, health warnings, and queue depth using API keys from agenix. Filter to a specific service or check all.",
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

          // Pre-load API keys for services that have them
          const apiKeys: Record<string, string | null> = {};
          await Promise.all(
            services.map(async (svc) => {
              apiKeys[svc.name] = await readSecret(`${svc.name}-api-key`);
            })
          );

          const results = await Promise.all(
            services.map(async (svc) => {
              try {
                const apiKey = apiKeys[svc.name];
                const headers: Record<string, string> = { Accept: "application/json" };
                if (apiKey) headers["X-Api-Key"] = apiKey;

                // Get system status
                const statusResp = await fetch(
                  `http://localhost:${svc.port}/api/v3/system/status`,
                  { headers, signal: AbortSignal.timeout(5000) }
                );

                if (statusResp.status === 401) {
                  return {
                    name: svc.name,
                    port: svc.port,
                    running: true,
                    apiKeyRequired: true,
                    apiKeyAvailable: !!apiKey,
                  };
                }

                if (!statusResp.ok) {
                  return { name: svc.name, port: svc.port, running: true, httpStatus: statusResp.status };
                }

                const status = await statusResp.json() as Record<string, unknown>;

                // Get health warnings
                let healthWarnings: unknown[] = [];
                try {
                  const healthResp = await fetch(
                    `http://localhost:${svc.port}/api/v3/health`,
                    { headers, signal: AbortSignal.timeout(3000) }
                  );
                  if (healthResp.ok) healthWarnings = await healthResp.json() as unknown[];
                } catch {
                  // health endpoint may fail
                }

                // Get queue depth
                let queueCount: number | undefined;
                try {
                  const queueResp = await fetch(
                    `http://localhost:${svc.port}/api/v3/queue`,
                    { headers, signal: AbortSignal.timeout(3000) }
                  );
                  if (queueResp.ok) {
                    const queue = await queueResp.json() as Record<string, unknown>;
                    queueCount = (queue.totalRecords as number) ?? undefined;
                  }
                } catch {
                  // queue endpoint may fail
                }

                return {
                  name: svc.name,
                  port: svc.port,
                  running: true,
                  version: status.version,
                  healthWarnings: Array.isArray(healthWarnings)
                    ? healthWarnings.map((w: unknown) => {
                        const warn = w as Record<string, unknown>;
                        return { type: warn.type, message: warn.message };
                      })
                    : [],
                  healthWarningCount: Array.isArray(healthWarnings) ? healthWarnings.length : 0,
                  queueCount,
                };
              } catch {
                return { name: svc.name, port: svc.port, running: false };
              }
            })
          );

          const running = results.filter((r) => r.running);
          const withWarnings = results.filter(
            (r) => "healthWarningCount" in r && (r.healthWarningCount as number) > 0
          );

          return {
            status: withWarnings.length > 0 ? "partial" : "ok",
            message: `${running.length}/${results.length} arr services responding` +
              (withWarnings.length > 0 ? `, ${withWarnings.length} with health warnings` : ""),
            data: { services: results },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to check arr status", err, "Are the arr containers running?");
        }
      },
    },

    {
      name: "hwc_media_download_queue",
      description:
        "Get current download queue from SABnzbd and/or qBittorrent. Shows speed, remaining time, active items, and pause state.",
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
              // Read SABnzbd API key from config
              const apiKey = await getSabnzbdApiKey();
              const url = apiKey
                ? `http://localhost:8081/sabnzbd/api?mode=queue&output=json&apikey=${apiKey}`
                : "http://localhost:8081/sabnzbd/api?mode=queue&output=json";

              const resp = await fetch(url, { signal: AbortSignal.timeout(5000) });
              if (resp.ok) {
                const queue = await resp.json() as Record<string, unknown>;
                const q = queue.queue as Record<string, unknown> | undefined;
                data.sabnzbd = {
                  speed: q?.speed,
                  remaining: q?.timeleft,
                  sizeLeft: q?.sizeleft,
                  items: Array.isArray(q?.slots) ? (q.slots as unknown[]).length : 0,
                  paused: q?.paused,
                };
              } else {
                data.sabnzbd = {
                  error: `HTTP ${resp.status}`,
                  hint: apiKey ? "API key was provided but request failed" : "No API key found in sabnzbd.ini",
                };
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
                  downloading: torrents.filter((t) => t.state === "downloading").length,
                  seeding: torrents.filter((t) => t.state === "uploading" || t.state === "stalledUP").length,
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
          return catchError("INTERNAL_ERROR", "Failed to check download queue", err);
        }
      },
    },
  ];
}
