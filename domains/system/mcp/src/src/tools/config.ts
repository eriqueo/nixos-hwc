/**
 * hwc_config_* tools — query the declarative NixOS configuration.
 *
 * Most tools parse the filesystem directly for speed and uncommitted-change support.
 * Only hwc_config_get_option uses nix eval (slow, requires committed changes).
 */

import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { nixEval, flakeMetadata } from "../executors/nix.js";

const HOSTS = ["hwc-server", "hwc-laptop", "hwc-xps", "hwc-gaming", "hwc-firestick"] as const;

export function configTools(nixosConfigPath: string, declarativeTtl: number): ToolDef[] {
  return [
    // ── hwc_config_get_option ───────────────────────────────────────────
    {
      name: "hwc_config_get_option",
      description:
        "Get the evaluated value of any option from the NixOS configuration. " +
        "Uses nix eval (slow ~5-15s, cached). Only sees committed changes. " +
        "Examples: 'hwc.media.jellyfin.enable', 'networking.hostName'",
      inputSchema: {
        type: "object",
        properties: {
          option_path: {
            type: "string",
            description: "Dot-separated option path, e.g. 'hwc.media.jellyfin.enable'",
          },
          host: {
            type: "string",
            enum: HOSTS,
            default: "hwc-server",
            description: "Which host config to evaluate",
          },
        },
        required: ["option_path"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const optionPath = args.option_path as string;
          const host = (args.host as string) || "hwc-server";

          const value = await nixEval(nixosConfigPath, host, optionPath, declarativeTtl);
          return {
            status: "ok",
            message: `${host}: ${optionPath}`,
            data: { host, path: optionPath, value },
          };
        } catch (err) {
          return {
            status: "error",
            message: "nix eval failed (is the option path correct? are changes committed?)",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_config_list_domains ─────────────────────────────────────────
    {
      name: "hwc_config_list_domains",
      description:
        "List all domains in the nixos-hwc architecture with their subdomains " +
        "and module files. Parses the filesystem directly (fast, sees uncommitted changes).",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const domainsDir = join(nixosConfigPath, "domains");
          const entries = await readdir(domainsDir, { withFileTypes: true });
          const domains: Array<{
            domain: string;
            subdomains: string[];
            files: string[];
            hasIndex: boolean;
          }> = [];

          for (const entry of entries) {
            if (!entry.isDirectory()) continue;
            const domainPath = join(domainsDir, entry.name);
            const subEntries = await readdir(domainPath, { withFileTypes: true });

            const subdomains: string[] = [];
            const files: string[] = [];
            let hasIndex = false;

            for (const sub of subEntries) {
              if (sub.isDirectory()) {
                subdomains.push(sub.name);
              } else if (sub.name.endsWith(".nix")) {
                files.push(sub.name);
                if (sub.name === "index.nix") hasIndex = true;
              }
            }

            domains.push({
              domain: entry.name,
              subdomains: subdomains.sort(),
              files: files.sort(),
              hasIndex,
            });
          }

          domains.sort((a, b) => a.domain.localeCompare(b.domain));

          return {
            status: "ok",
            message: `${domains.length} domains found`,
            data: { domains },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to list domains",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_config_get_port_map ─────────────────────────────────────────
    {
      name: "hwc_config_get_port_map",
      description:
        "Get the complete port allocation map from routes.nix — internal ports, " +
        "external Caddy ports, subpath routes. Useful for checking conflicts.",
      inputSchema: {
        type: "object",
        properties: {
          filter: {
            type: "string",
            description: "Filter by service name or port number. Omit for full map.",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const filter = (args.filter as string)?.toLowerCase();
          const routesPath = join(nixosConfigPath, "domains/networking/routes.nix");
          const content = await readFile(routesPath, "utf-8");

          const routes = parseRoutes(content);
          const filtered = filter
            ? routes.filter(
                (r) =>
                  r.name.toLowerCase().includes(filter) ||
                  String(r.port || "").includes(filter) ||
                  (r.path || "").toLowerCase().includes(filter) ||
                  (r.upstream || "").includes(filter)
              )
            : routes;

          return {
            status: "ok",
            message: `${filtered.length} routes${filter ? ` matching '${filter}'` : ""}`,
            data: { routes: filtered, total: routes.length },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to parse port map",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_config_get_host_profile ─────────────────────────────────────
    {
      name: "hwc_config_get_host_profile",
      description:
        "Get the full profile and domain import list for a host — profiles, " +
        "domains, channel (stable/unstable), and special config.",
      inputSchema: {
        type: "object",
        properties: {
          host: {
            type: "string",
            enum: HOSTS,
            description: "Host to query",
          },
        },
        required: ["host"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const host = args.host as string;
          const machineName = host.replace("hwc-", "");
          const configPath = join(nixosConfigPath, "machines", machineName, "config.nix");

          let content: string;
          try {
            content = await readFile(configPath, "utf-8");
          } catch {
            return {
              status: "error",
              message: `Machine config not found: ${configPath}`,
              error: `No config.nix found for ${host}`,
            };
          }

          // Parse imports
          const imports = parseImports(content);
          const profiles = imports.filter((i) => i.includes("profiles/"));
          const domains = imports.filter((i) => i.includes("domains/"));

          // Determine channel from flake.nix
          const flakePath = join(nixosConfigPath, "flake.nix");
          const flakeContent = await readFile(flakePath, "utf-8");
          const isStable = flakeContent.includes(`${host} = nixpkgs-stable`) ||
                           flakeContent.includes(`${host.replace("hwc-", "")} = nixpkgs-stable`);

          // Extract hostname
          const hostnameMatch = content.match(/hostName\s*=\s*"([^"]+)"/);
          const stateVersionMatch = content.match(/stateVersion\s*=\s*"([^"]+)"/);

          return {
            status: "ok",
            message: `Profile for ${host}`,
            data: {
              host,
              hostname: hostnameMatch?.[1] || host,
              channel: isStable ? "stable (nixos-25.11)" : "unstable",
              stateVersion: stateVersionMatch?.[1] || "unknown",
              profiles,
              domainImports: domains,
              allImports: imports,
            },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to get host profile",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_config_search_options ────────────────────────────────────────
    {
      name: "hwc_config_search_options",
      description:
        "Search for Nix option declarations by keyword. Scans domains/ for " +
        "mkOption/mkEnableOption patterns matching the query. Fast filesystem scan.",
      inputSchema: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "Search term, e.g. 'gpu', 'port', 'enable', 'backup'",
          },
        },
        required: ["query"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          if (!args.query || typeof args.query !== "string") {
            return { status: "error", message: "query parameter is required" };
          }
          const query = (args.query as string).toLowerCase();
          const domainsDir = join(nixosConfigPath, "domains");
          const results = await searchOptionDeclarations(domainsDir, query);

          return {
            status: "ok",
            message: `${results.length} option declarations matching '${query}'`,
            data: { results },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to search options",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },

    // ── hwc_config_flake_metadata ───────────────────────────────────────
    {
      name: "hwc_config_flake_metadata",
      description:
        "Get flake metadata — inputs, their current revisions, when last updated.",
      inputSchema: {
        type: "object",
        properties: {},
      },
      handler: async (): Promise<ToolResult> => {
        try {
          const meta = await flakeMetadata(nixosConfigPath, declarativeTtl);
          const locks = (meta.locks as Record<string, unknown>) || {};
          const nodes = (locks as { nodes?: Record<string, unknown> }).nodes || {};

          const inputs: Array<{ name: string; url?: string; rev?: string; lastModified?: string }> = [];
          for (const [name, node] of Object.entries(nodes)) {
            if (name === "root") continue;
            const locked = (node as Record<string, unknown>).locked as Record<string, unknown> | undefined;
            if (locked) {
              inputs.push({
                name,
                url: (locked.url as string) || `${locked.owner}/${locked.repo}`,
                rev: (locked.rev as string)?.slice(0, 12),
                lastModified: locked.lastModified
                  ? new Date((locked.lastModified as number) * 1000).toISOString().slice(0, 10)
                  : undefined,
              });
            }
          }

          return {
            status: "ok",
            message: `${inputs.length} flake inputs`,
            data: { inputs },
          };
        } catch (err) {
          return {
            status: "error",
            message: "Failed to get flake metadata",
            error: err instanceof Error ? err.message : String(err),
          };
        }
      },
    },
  ];
}

// ── Helpers ──────────────────────────────────────────────────────────────

interface Route {
  name: string;
  mode: string;
  port?: number;
  path?: string;
  upstream?: string;
  needsUrlBase?: boolean;
}

function parseRoutes(content: string): Route[] {
  const routes: Route[] = [];
  // Match route blocks: { name = "..."; mode = "..."; ... }
  const blockRegex = /\{\s*\n([^}]*?name\s*=\s*"[^"]+";[^}]*?)\}/g;
  let match: RegExpExecArray | null;

  while ((match = blockRegex.exec(content)) !== null) {
    const block = match[1];

    const nameMatch = block.match(/name\s*=\s*"([^"]+)"/);
    const modeMatch = block.match(/mode\s*=\s*"([^"]+)"/);
    const portMatch = block.match(/port\s*=\s*(\d+)/);
    const pathMatch = block.match(/path\s*=\s*"([^"]+)"/);
    const upstreamMatch = block.match(/upstream\s*=\s*"([^"]+)"/);
    const urlBaseMatch = block.match(/needsUrlBase\s*=\s*(true|false)/);

    if (nameMatch && modeMatch) {
      routes.push({
        name: nameMatch[1],
        mode: modeMatch[1],
        port: portMatch ? parseInt(portMatch[1], 10) : undefined,
        path: pathMatch?.[1],
        upstream: upstreamMatch?.[1],
        needsUrlBase: urlBaseMatch ? urlBaseMatch[1] === "true" : undefined,
      });
    }
  }

  return routes;
}

function parseImports(content: string): string[] {
  const imports: string[] = [];
  // Match import paths: ./path or ../../path or ${something}/path
  const importBlockMatch = content.match(/imports\s*=\s*\[([\s\S]*?)\];/);
  if (!importBlockMatch) return imports;

  const block = importBlockMatch[1];
  const pathRegex = /(?:\.\/)([^\s;]+\.nix)|(?:\.\.\/)+([^\s;]+\.nix)/g;
  let match: RegExpExecArray | null;

  while ((match = pathRegex.exec(block)) !== null) {
    imports.push(match[1] || match[2]);
  }

  // Also catch profiles/domains paths in comments or string form
  const stringPaths = block.match(/(?:profiles|domains)\/[^\s;}\]]+/g);
  if (stringPaths) {
    for (const p of stringPaths) {
      if (!imports.some((i) => i.includes(p))) {
        imports.push(p);
      }
    }
  }

  return imports;
}

interface OptionDeclaration {
  file: string;
  line: number;
  name: string;
  type: string;
  snippet: string;
}

async function searchOptionDeclarations(
  dir: string,
  query: string,
  basePath?: string
): Promise<OptionDeclaration[]> {
  const results: OptionDeclaration[] = [];
  const base = basePath || dir;

  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    return results;
  }

  for (const entry of entries) {
    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      results.push(...await searchOptionDeclarations(fullPath, query, base));
    } else if (entry.name.endsWith(".nix")) {
      try {
        const content = await readFile(fullPath, "utf-8");
        const lines = content.split("\n");

        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          if (
            (line.includes("mkOption") || line.includes("mkEnableOption")) &&
            (line.toLowerCase().includes(query) ||
             lines.slice(Math.max(0, i - 2), i + 5).join("\n").toLowerCase().includes(query))
          ) {
            // Extract option name by walking back through the nesting
            const contextBefore = lines.slice(Math.max(0, i - 10), i + 1).join("\n");

            // Try to match full path like "gpu.enable = lib.mkOption" or inline "enable = mkEnableOption"
            const fullPathMatch = contextBefore.match(/([\w.]+)\s*=\s*(?:lib\.)?mk(?:Option|EnableOption)/);
            // Also try extracting from nesting: look for attribute paths in context
            let optionName = fullPathMatch?.[1] || "unknown";

            // If we only got a leaf name like "enable", try to build path from nesting context
            if (optionName === "enable" || optionName === "unknown") {
              const widerContext = lines.slice(Math.max(0, i - 20), i + 1);
              const pathParts: string[] = [];
              for (const ctx of widerContext) {
                const attrMatch = ctx.match(/^\s*([\w]+)\s*=\s*\{/);
                if (attrMatch) pathParts.push(attrMatch[1]);
              }
              if (fullPathMatch?.[1]) pathParts.push(fullPathMatch[1]);
              if (pathParts.length > 1) optionName = pathParts.join(".");
            }

            const snippet = lines.slice(i, Math.min(lines.length, i + 3)).join("\n").trim();

            results.push({
              file: relative(base, fullPath),
              line: i + 1,
              name: optionName,
              type: line.includes("mkEnableOption") ? "enable" : "option",
              snippet: snippet.slice(0, 200),
            });
          }
        }
      } catch {
        // Skip unreadable files
      }
    }
  }

  return results;
}
