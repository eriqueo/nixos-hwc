/**
 * Podman executor — container inspection, stats, and log queries.
 *
 * Uses the root podman socket (unix:///run/podman/podman.sock) so the MCP
 * server (running as eric with SupplementaryGroups=podman) can see all
 * root-managed containers without running as root.
 */

import { safeExec } from "./shell.js";
import type { ContainerStats } from "../types.js";

const ROOT_SOCKET = "unix:///run/podman/podman.sock";

interface ContainerInfo {
  Names: string[];
  Id: string;
  State: string;
  Status: string;
  Image: string;
  Created: string;
  Ports: Array<{ host_port: number; container_port: number; protocol: string }>;
}

/** Prepend --url flag to target the root podman socket. */
function podmanArgs(args: string[]): string[] {
  return ["--url", ROOT_SOCKET, ...args];
}

/**
 * List all containers (running and stopped).
 */
export async function listContainers(): Promise<ContainerInfo[]> {
  const result = await safeExec("podman", podmanArgs(["ps", "-a", "--format", "json"]), {
    timeout: 10000,
  });
  if (result.exitCode !== 0) return [];
  try {
    return JSON.parse(result.stdout || "[]");
  } catch {
    return [];
  }
}

/**
 * Get real-time stats for running containers.
 * Tries podman stats first, falls back to systemd cgroup data.
 */
export async function getContainerStats(
  container?: string
): Promise<ContainerStats[]> {
  // Try podman stats first
  const args = ["stats", "--no-stream", "--format", "json"];
  if (container) args.push(container);

  const result = await safeExec("podman", podmanArgs(args), { timeout: 15000 });
  if (result.exitCode === 0) {
    try {
      const raw = JSON.parse(result.stdout || "[]") as Array<Record<string, unknown>>;
      if (raw.length > 0) {
        return raw.map((c) => ({
          name: (c.name || c.Name || "") as string,
          id: ((c.id || c.ID || "") as string).slice(0, 12),
          cpu: (c.cpu_percent || c.CPU || "0%") as string,
          memory: (c.mem_usage || c.MemUsage || "0B") as string,
          memLimit: (c.mem_limit || c.MemLimit || "0B") as string,
          netIO: (c.net_io || c.NetIO || "0B/0B") as string,
          blockIO: (c.block_io || c.BlockIO || "0B/0B") as string,
          pids: parseInt(String(c.pids || c.PIDs || 0), 10),
          status: "running",
        }));
      }
    } catch {
      // Fall through to systemd fallback
    }
  }

  // Fallback: query systemd cgroup data for podman-* services
  return getContainerStatsFromSystemd(container);
}

/**
 * Fallback: get container stats from systemd cgroup accounting.
 * Works reliably because all containers are managed as podman-<name>.service.
 */
async function getContainerStatsFromSystemd(
  container?: string
): Promise<ContainerStats[]> {
  // Get list of podman-* services
  const listResult = await safeExec("systemctl", [
    "list-units",
    "--type=service",
    "--state=running",
    "--plain",
    "--no-legend",
    "--no-pager",
    container ? `podman-${container}.service` : "podman-*",
  ], { timeout: 10000 });

  if (listResult.exitCode !== 0) return [];

  const units = listResult.stdout
    .split("\n")
    .filter(Boolean)
    .map((line) => line.trim().split(/\s+/)[0])
    .filter((name) => name.startsWith("podman-") && name.endsWith(".service"));

  if (units.length === 0) return [];

  // Query cgroup stats for each unit in parallel (batched)
  const stats: ContainerStats[] = [];
  const batchSize = 10;

  for (let i = 0; i < units.length; i += batchSize) {
    const batch = units.slice(i, i + batchSize);
    const results = await Promise.all(
      batch.map(async (unit) => {
        const showResult = await safeExec("systemctl", [
          "show",
          unit,
          "--property=MemoryCurrent,CPUUsageNSec,MainPID,TasksCurrent",
          "--no-pager",
        ], { timeout: 5000 });

        if (showResult.exitCode !== 0) return null;

        const props: Record<string, string> = {};
        for (const line of showResult.stdout.split("\n")) {
          const idx = line.indexOf("=");
          if (idx > 0) props[line.slice(0, idx)] = line.slice(idx + 1);
        }

        const name = unit.replace("podman-", "").replace(".service", "");
        const memBytes = parseInt(props.MemoryCurrent || "0", 10);
        const cpuNs = parseInt(props.CPUUsageNSec || "0", 10);
        const pids = parseInt(props.TasksCurrent || "0", 10);

        return {
          name,
          id: props.MainPID || "0",
          cpu: `${(cpuNs / 1e9).toFixed(1)}s total`,
          memory: formatBytes(memBytes),
          memLimit: "",
          netIO: "",
          blockIO: "",
          pids,
          status: "running",
        } satisfies ContainerStats;
      })
    );

    stats.push(...results.filter((r): r is ContainerStats => r !== null));
  }

  return stats;
}

function formatBytes(bytes: number): string {
  if (bytes === 0 || isNaN(bytes)) return "0B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return `${(bytes / Math.pow(1024, i)).toFixed(1)}${units[i]}`;
}

/**
 * Get recent logs for a container.
 */
export async function getContainerLogs(
  container: string,
  tail: number = 50,
  since?: string
): Promise<string[]> {
  const args = ["logs", "--tail", String(Math.min(tail, 500))];
  if (since) args.push("--since", since);
  args.push(container);

  const result = await safeExec("podman", podmanArgs(args), { timeout: 10000 });
  // podman logs writes to both stdout and stderr
  const output = result.stdout + result.stderr;
  return output.split("\n").filter(Boolean);
}

/**
 * Inspect a container for detailed configuration.
 */
export async function inspectContainer(
  container: string
): Promise<Record<string, unknown> | null> {
  const result = await safeExec("podman", podmanArgs(["inspect", container, "--format", "json"]), {
    timeout: 10000,
  });
  if (result.exitCode !== 0) return null;
  try {
    const parsed = JSON.parse(result.stdout);
    return Array.isArray(parsed) ? parsed[0] : parsed;
  } catch {
    return null;
  }
}
