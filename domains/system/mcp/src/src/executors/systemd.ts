/**
 * Systemd executor — wraps systemctl and journalctl commands.
 */

import { safeExec, execOrThrow } from "./shell.js";
import type { ServiceStatus } from "../types.js";

/**
 * Get status of a specific systemd service.
 */
export async function getServiceStatus(unit: string): Promise<ServiceStatus> {
  const props = [
    "ActiveState",
    "SubState",
    "Description",
    "MainPID",
    "MemoryCurrent",
    "NRestarts",
    "ActiveEnterTimestamp",
  ];
  const result = await safeExec("systemctl", [
    "show",
    unit,
    "--property=" + props.join(","),
    "--no-pager",
  ]);

  const parsed: Record<string, string> = {};
  for (const line of result.stdout.split("\n")) {
    const idx = line.indexOf("=");
    if (idx > 0) {
      parsed[line.slice(0, idx)] = line.slice(idx + 1);
    }
  }

  const isContainer = unit.startsWith("podman-");
  return {
    name: unit,
    activeState: parsed.ActiveState || "unknown",
    subState: parsed.SubState || "unknown",
    description: parsed.Description || "",
    mainPid: parsed.MainPID ? parseInt(parsed.MainPID, 10) : undefined,
    memoryUsage: parsed.MemoryCurrent && parsed.MemoryCurrent !== "[not set]"
      ? formatBytes(parseInt(parsed.MemoryCurrent, 10))
      : undefined,
    restartCount: parsed.NRestarts ? parseInt(parsed.NRestarts, 10) : undefined,
    uptime: parsed.ActiveEnterTimestamp || undefined,
    type: isContainer ? "container" : "native",
  };
}

/**
 * List all hwc-related and podman services.
 */
export async function listServices(): Promise<ServiceStatus[]> {
  const result = await safeExec("systemctl", [
    "list-units",
    "--type=service",
    "--no-pager",
    "--no-legend",
    "--plain",
  ]);

  const units = result.stdout
    .split("\n")
    .map((line) => line.trim().split(/\s+/)[0])
    .filter((u) => u && (u.startsWith("podman-") || u.startsWith("hwc-") ||
      u.startsWith("heartwood-") || u.startsWith("tailscale") ||
      u === "caddy.service" || u === "sshd.service" ||
      u === "protonmail-bridge.service" || u === "borgbackup-job-hwc.service"));

  const statuses: ServiceStatus[] = [];
  for (const unit of units) {
    try {
      statuses.push(await getServiceStatus(unit));
    } catch {
      statuses.push({
        name: unit,
        activeState: "error",
        subState: "error",
        description: "Failed to query",
        type: unit.startsWith("podman-") ? "container" : "native",
      });
    }
  }
  return statuses;
}

/**
 * Get recent journal lines for a service.
 */
export async function getJournalLines(
  unit: string,
  lines: number = 50,
  since?: string,
  priority?: string,
  grep?: string
): Promise<string[]> {
  const args = ["-u", unit, "--no-pager", "-n", String(Math.min(lines, 500))];
  if (since) args.push("--since", since);
  if (priority) args.push("-p", priority);
  if (grep) args.push("--grep", grep);

  const result = await safeExec("journalctl", args, { timeout: 10000 });
  return result.stdout.split("\n").filter(Boolean);
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}K`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)}M`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)}G`;
}
