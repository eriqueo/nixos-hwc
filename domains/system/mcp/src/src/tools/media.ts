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
      name: "hwc_media_status",
      description:
        "Get media infrastructure status — *arr stack and/or download clients. " +
        "Default returns both arr services and download queues.",
      inputSchema: {
        type: "object",
        properties: {
          include: {
            type: "string",
            enum: ["all", "arr", "downloads"],
            default: "all",
            description: "What to include (default: all)",
          },
          service: {
            type: "string",
            enum: ["sonarr", "radarr", "lidarr", "readarr", "prowlarr", "all"],
            default: "all",
            description: "Filter arr services",
          },
          client: {
            type: "string",
            enum: ["sabnzbd", "qbittorrent", "all"],
            default: "all",
            description: "Filter download clients",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const include = (args.include as string) || "all";
          const data: Record<string, unknown> = {};
          const parts: string[] = [];

          // Arr services
          if (include === "all" || include === "arr") {
            const filter = args.service as string || "all";
            const services = filter === "all"
              ? ARR_SERVICES
              : ARR_SERVICES.filter((s) => s.name === filter);

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

                  const statusResp = await fetch(
                    `http://localhost:${svc.port}/api/v3/system/status`,
                    { headers, signal: AbortSignal.timeout(5000) }
                  );

                  if (statusResp.status === 401) {
                    return { name: svc.name, port: svc.port, running: true, apiKeyRequired: true, apiKeyAvailable: !!apiKey };
                  }
                  if (!statusResp.ok) {
                    return { name: svc.name, port: svc.port, running: true, httpStatus: statusResp.status };
                  }

                  const status = await statusResp.json() as Record<string, unknown>;

                  let healthWarnings: unknown[] = [];
                  try {
                    const healthResp = await fetch(`http://localhost:${svc.port}/api/v3/health`, { headers, signal: AbortSignal.timeout(3000) });
                    if (healthResp.ok) healthWarnings = await healthResp.json() as unknown[];
                  } catch { /* health endpoint may fail */ }

                  let queueCount: number | undefined;
                  try {
                    const queueResp = await fetch(`http://localhost:${svc.port}/api/v3/queue`, { headers, signal: AbortSignal.timeout(3000) });
                    if (queueResp.ok) {
                      const queue = await queueResp.json() as Record<string, unknown>;
                      queueCount = (queue.totalRecords as number) ?? undefined;
                    }
                  } catch { /* queue endpoint may fail */ }

                  return {
                    name: svc.name, port: svc.port, running: true, version: status.version,
                    healthWarnings: Array.isArray(healthWarnings) ? healthWarnings.map((w: unknown) => { const warn = w as Record<string, unknown>; return { type: warn.type, message: warn.message }; }) : [],
                    healthWarningCount: Array.isArray(healthWarnings) ? healthWarnings.length : 0,
                    queueCount,
                  };
                } catch {
                  return { name: svc.name, port: svc.port, running: false };
                }
              })
            );

            const running = results.filter((r) => r.running);
            const withWarnings = results.filter((r) => "healthWarningCount" in r && (r.healthWarningCount as number) > 0);
            data.arr = { services: results };
            parts.push(`${running.length}/${results.length} arr services${withWarnings.length > 0 ? ` (${withWarnings.length} warnings)` : ""}`);
          }

          // Download clients
          if (include === "all" || include === "downloads") {
            const client = (args.client as string) || "all";
            const downloads: Record<string, unknown> = {};

            if (client === "all" || client === "sabnzbd") {
              try {
                const apiKey = await getSabnzbdApiKey();
                const url = apiKey
                  ? `http://localhost:8081/sabnzbd/api?mode=queue&output=json&apikey=${apiKey}`
                  : "http://localhost:8081/sabnzbd/api?mode=queue&output=json";
                const resp = await fetch(url, { signal: AbortSignal.timeout(5000) });
                if (resp.ok) {
                  const queue = await resp.json() as Record<string, unknown>;
                  const q = queue.queue as Record<string, unknown> | undefined;
                  downloads.sabnzbd = { speed: q?.speed, remaining: q?.timeleft, sizeLeft: q?.sizeleft, items: Array.isArray(q?.slots) ? (q.slots as unknown[]).length : 0, paused: q?.paused };
                } else {
                  downloads.sabnzbd = { error: `HTTP ${resp.status}` };
                }
              } catch { downloads.sabnzbd = { error: "Not reachable" }; }
            }

            if (client === "all" || client === "qbittorrent") {
              try {
                const resp = await fetch("http://localhost:8080/api/v2/torrents/info", { signal: AbortSignal.timeout(5000) });
                if (resp.ok) {
                  const torrents = await resp.json() as Array<Record<string, unknown>>;
                  downloads.qbittorrent = {
                    totalTorrents: torrents.length,
                    active: torrents.filter((t) => t.state === "downloading" || t.state === "uploading").length,
                    downloading: torrents.filter((t) => t.state === "downloading").length,
                    seeding: torrents.filter((t) => t.state === "uploading" || t.state === "stalledUP").length,
                  };
                } else {
                  downloads.qbittorrent = { error: `HTTP ${resp.status}` };
                }
              } catch { downloads.qbittorrent = { error: "Not reachable" }; }
            }

            data.downloads = downloads;
            parts.push("downloads checked");
          }

          return {
            status: "ok",
            message: parts.join(", "),
            data,
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to check media status", err, "Are the media containers running?");
        }
      },
    },
  ];
}
