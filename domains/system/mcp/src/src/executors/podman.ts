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
 */
export async function getContainerStats(
  container?: string
): Promise<ContainerStats[]> {
  const args = ["stats", "--no-stream", "--format", "json"];
  if (container) args.push(container);

  const result = await safeExec("podman", podmanArgs(args), { timeout: 15000 });
  if (result.exitCode !== 0) return [];

  try {
    const raw = JSON.parse(result.stdout || "[]") as Array<Record<string, unknown>>;
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
  } catch {
    return [];
  }
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
