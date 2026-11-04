/**
 * Resource registry — static or slowly-changing data exposed as MCP resources.
 * These are read-only context that clients can pull on demand.
 */

import { mapReads } from "../executors/concurrency.js";
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import type { ResourceDef } from "../types.js";

// Fixed patterns are shared; stateful uses reset their cursor below.
const allResourcesBlockRegexRegex = /\{\s*\n([^}]*?name\s*=\s*"[^"]+";[^}]*?)\}/g;
const allResourcesPatternRegex = /name\s*=\s*"([^"]+)"/;
const allResourcesPatternRegex2 = /mode\s*=\s*"([^"]+)"/;
const allResourcesPatternRegex3 = /port\s*=\s*(\d+)/;
const allResourcesPatternRegex4 = /path\s*=\s*"([^"]+)"/;
const allResourcesPatternRegex5 = /upstream\s*=\s*"([^"]+)"/;
const allResourcesFlatRegexRegex = /age\.secrets\.([\w-]+)\s*=/g;
const allResourcesPatternRegex6 = /age\.secrets\s*=\s*\{([\s\S]*)\};/;
const allResourcesEntryRegexRegex = /^\s*([\w-]+)\s*=\s*\{/gm;
const allResourcesPatternRegex7 = /imports\s*=\s*\[([\s\S]*?)\];/;
const allResourcesPatternRegex8 = /profiles\/[\w.]+/g;
const allResourcesPatternRegex9 = /domains\/[\w/]+/g;

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
          const branches = await mapReads(domains.filter((d) => d.isDirectory()), async (d) => {
            const domainPath = join(domainsDir, d.name);
            const entries = await readdir(domainPath, { withFileTypes: true });
            return [d.name, {
              subdomains: entries.filter((e) => e.isDirectory()).map((e) => e.name).sort(),
              files: entries.filter((e) => e.name.endsWith(".nix")).map((e) => e.name).sort(),
            }] as const;
          });
          Object.assign(tree, Object.fromEntries(branches));
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
          const blockRegex = allResourcesBlockRegexRegex;


          for (const match of content.matchAll(blockRegex)) {
            const block = match[1];
            const entry: Record<string, unknown> = {};

            const nameMatch = block.match(allResourcesPatternRegex);
            const modeMatch = block.match(allResourcesPatternRegex2);
            const portMatch = block.match(allResourcesPatternRegex3);
            const pathMatch = block.match(allResourcesPatternRegex4);
            const upstreamMatch = block.match(allResourcesPatternRegex5);

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

          const contents = await mapReads(files.filter((f) => f.endsWith(".nix") && f !== "index.nix"),
            async (file) => [file, await readFile(join(declDir, file), "utf-8")] as const);
          for (const [file, content] of contents) {
            const category = file.replace(".nix", "");

            const names: string[] = [];
            // Try flat format: age.secrets.name = { ... }
            const flatRegex = allResourcesFlatRegexRegex;

            for (const m of content.matchAll(flatRegex)) {
              names.push(m[1]);
            }
            // If none found, try nested: age.secrets = { name = { ... }; }
            if (names.length === 0) {
              const nestedMatch = content.match(allResourcesPatternRegex6);
              if (nestedMatch) {
                const entryRegex = allResourcesEntryRegexRegex;
                for (const m of nestedMatch[1].matchAll(entryRegex)) {
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

          const configs = await mapReads(machines.filter((m) => m.isDirectory()), async (m) => {
            const key = `hwc-${m.name}`;
            const configPath = join(machinesDir, m.name, "config.nix");
            try {
              const content = await readFile(configPath, "utf-8");
              const importBlock = content.match(allResourcesPatternRegex7);
              const block = importBlock?.[1] || "";

              const profiles = (block.match((allResourcesPatternRegex8.lastIndex = 0, allResourcesPatternRegex8)) || []).map(
                (p) => p.replace("profiles/", "").replace(".nix", "")
              );
              const domains = (block.match((allResourcesPatternRegex9.lastIndex = 0, allResourcesPatternRegex9)) || []).map(
                (d) => d.replace("/index.nix", "")
              );

              return [key, { profiles, domains }] as const;
            } catch {
              return [key, { profiles: [], domains: [] }] as const;
            }
          });
          Object.assign(matrix, Object.fromEntries(configs));

          return JSON.stringify(matrix, null, 2);
        } catch {
          return JSON.stringify({ error: "Could not read machines directory" });
        }
      },
    },
  ];
}
