/**
 * Resource registry — static or slowly-changing data exposed as MCP resources.
 * These are read-only context that clients can pull on demand.
 */

import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import type { ResourceDef } from "../types.js";

export function allResources(nixosConfigPath: string): ResourceDef[] {
  return [
    // ── Charter ─────────────────────────────────────────────────────────
    {
      uri: "hwc://charter",
      name: "Architecture Charter v11.1",
      description: "The architectural laws governing the nixos-hwc system",
      mimeType: "text/markdown",
      load: async () => {
        try {
          return await readFile(join(nixosConfigPath, "CHARTER.md"), "utf-8");
        } catch {
          return "Charter file not found at CHARTER.md";
        }
      },
    },

    // ── Domain Tree ─────────────────────────────────────────────────────
    {
      uri: "hwc://domain-tree",
      name: "Domain Architecture Tree",
      description: "Complete domain/subdomain/module tree with file paths",
      mimeType: "application/json",
      load: async () => {
        const domainsDir = join(nixosConfigPath, "domains");
        const tree: Record<string, { subdomains: string[]; files: string[] }> = {};

        try {
          const domains = await readdir(domainsDir, { withFileTypes: true });
          for (const d of domains) {
            if (!d.isDirectory()) continue;
            const domainPath = join(domainsDir, d.name);
            const entries = await readdir(domainPath, { withFileTypes: true });
            tree[d.name] = {
              subdomains: entries.filter((e) => e.isDirectory()).map((e) => e.name).sort(),
              files: entries.filter((e) => e.name.endsWith(".nix")).map((e) => e.name).sort(),
            };
          }
        } catch {
          return JSON.stringify({ error: "Could not read domains directory" });
        }

        return JSON.stringify(tree, null, 2);
      },
    },

    // ── Port Map ────────────────────────────────────────────────────────
    {
      uri: "hwc://port-map",
      name: "Port Allocation Map",
      description: "Every port used by every service — internal, external Caddy, protocols",
      mimeType: "application/json",
      load: async () => {
        try {
          const content = await readFile(
            join(nixosConfigPath, "domains/networking/routes.nix"),
            "utf-8"
          );
          // Extract route blocks
          const routes: Array<Record<string, unknown>> = [];
          const blockRegex = /\{\s*\n([^}]*?name\s*=\s*"[^"]+";[^}]*?)\}/g;
          let match: RegExpExecArray | null;

          while ((match = blockRegex.exec(content)) !== null) {
            const block = match[1];
            const entry: Record<string, unknown> = {};

            const nameMatch = block.match(/name\s*=\s*"([^"]+)"/);
            const modeMatch = block.match(/mode\s*=\s*"([^"]+)"/);
            const portMatch = block.match(/port\s*=\s*(\d+)/);
            const pathMatch = block.match(/path\s*=\s*"([^"]+)"/);
            const upstreamMatch = block.match(/upstream\s*=\s*"([^"]+)"/);

            if (nameMatch) entry.name = nameMatch[1];
            if (modeMatch) entry.mode = modeMatch[1];
            if (portMatch) entry.port = parseInt(portMatch[1], 10);
            if (pathMatch) entry.path = pathMatch[1];
            if (upstreamMatch) entry.upstream = upstreamMatch[1];

            if (entry.name) routes.push(entry);
          }

          return JSON.stringify(routes, null, 2);
        } catch {
          return JSON.stringify({ error: "Could not read routes.nix" });
        }
      },
    },

    // ── Secret Inventory ────────────────────────────────────────────────
    {
      uri: "hwc://secret-inventory",
      name: "Secret Inventory",
      description: "All agenix-managed secret NAMES by category. Never values.",
      mimeType: "application/json",
      load: async () => {
        try {
          const declDir = join(nixosConfigPath, "domains/secrets/declarations");
          const files = await readdir(declDir);
          const inventory: Record<string, string[]> = {};

          for (const file of files) {
            if (!file.endsWith(".nix") || file === "index.nix") continue;
            const category = file.replace(".nix", "");
            const content = await readFile(join(declDir, file), "utf-8");

            const names: string[] = [];
            // Try flat format: age.secrets.name = { ... }
            const flatRegex = /age\.secrets\.([\w-]+)\s*=/g;
            let m: RegExpExecArray | null;
            while ((m = flatRegex.exec(content)) !== null) {
              names.push(m[1]);
            }
            // If none found, try nested: age.secrets = { name = { ... }; }
            if (names.length === 0) {
              const nestedMatch = content.match(/age\.secrets\s*=\s*\{([\s\S]*)\};/);
              if (nestedMatch) {
                const entryRegex = /^\s*([\w-]+)\s*=\s*\{/gm;
                while ((m = entryRegex.exec(nestedMatch[1])) !== null) {
                  if (!["file", "mode", "owner", "group", "path"].includes(m[1])) {
                    names.push(m[1]);
                  }
                }
              }
            }
            if (names.length > 0) inventory[category] = names.sort();
          }

          return JSON.stringify(inventory, null, 2);
        } catch {
          return JSON.stringify({ error: "Could not read secret declarations" });
        }
      },
    },

    // ── Host Matrix ─────────────────────────────────────────────────────
    {
      uri: "hwc://host-matrix",
      name: "Host Profile Matrix",
      description: "All hosts with their channel, profiles, and domain imports",
      mimeType: "application/json",
      load: async () => {
        try {
          const machinesDir = join(nixosConfigPath, "machines");
          const machines = await readdir(machinesDir, { withFileTypes: true });
          const matrix: Record<string, { profiles: string[]; domains: string[] }> = {};

          for (const m of machines) {
            if (!m.isDirectory()) continue;
            const configPath = join(machinesDir, m.name, "config.nix");
            try {
              const content = await readFile(configPath, "utf-8");
              const importBlock = content.match(/imports\s*=\s*\[([\s\S]*?)\];/);
              const block = importBlock?.[1] || "";

              const profiles = (block.match(/profiles\/[\w.]+/g) || []).map(
                (p) => p.replace("profiles/", "").replace(".nix", "")
              );
              const domains = (block.match(/domains\/[\w/]+/g) || []).map(
                (d) => d.replace("/index.nix", "")
              );

              matrix[`hwc-${m.name}`] = { profiles, domains };
            } catch {
              matrix[`hwc-${m.name}`] = { profiles: [], domains: [] };
            }
          }

          return JSON.stringify(matrix, null, 2);
        } catch {
          return JSON.stringify({ error: "Could not read machines directory" });
        }
      },
    },
  ];
}
