/**
 * Tailscale CLI wrappers — status, peers, funnel config.
 */

import { safeExec } from "./shell.js";

interface TailscalePeer {
  hostname: string;
  ip: string;
  os: string;
  online: boolean;
  lastSeen?: string;
  exitNode: boolean;
}

interface TailscaleStatus {
  self: {
    hostname: string;
    ip: string;
    online: boolean;
    os: string;
  };
  peers: TailscalePeer[];
}

/**
 * Get Tailscale network status.
 */
export async function getStatus(): Promise<TailscaleStatus> {
  const result = await safeExec("tailscale", ["status", "--json"], {
    timeout: 10000,
  });

  if (result.exitCode !== 0) {
    throw new Error(`tailscale status failed: ${result.stderr}`);
  }

  const data = JSON.parse(result.stdout);
  const self = data.Self || {};
  const peerMap = data.Peer || {};

  const peers: TailscalePeer[] = Object.values(peerMap).map((p: unknown) => {
    const peer = p as Record<string, unknown>;
    const addrs = (peer.TailscaleIPs || []) as string[];
    return {
      hostname: (peer.HostName || "unknown") as string,
      ip: addrs[0] || "",
      os: (peer.OS || "unknown") as string,
      online: peer.Online === true,
      lastSeen: peer.LastSeen as string | undefined,
      exitNode: peer.ExitNode === true,
    };
  });

  const selfAddrs = (self.TailscaleIPs || []) as string[];
  return {
    self: {
      hostname: self.HostName || "unknown",
      ip: selfAddrs[0] || "",
      online: true,
      os: self.OS || "unknown",
    },
    peers,
  };
}
