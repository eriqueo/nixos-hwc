/**
 * hwc_config — consolidated config tool (browse, host_profile, get_option, port_map, list_domains, search_options, flake_metadata).
 */

import { readdir, readFile, stat } from "node:fs/promises";
import { join, relative, resolve, normalize } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { nixEval, flakeMetadata } from "../executors/nix.js";
import { mcpError, catchError } from "../errors.js";

const HOSTS = ["hwc-server", "hwc-laptop", "hwc-xps", "hwc-gaming", "hwc-firestick"] as const;

export function configTools(nixosConfigPath: string, declarativeTtl: number): ToolDef[] {
  return [
    {
      name: "hwc_config",
      description:
        "NixOS config inspection. Actions: browse, host_profile, get_option, port_map, list_domains, search_options, flake_metadata.",
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["browse", "host_profile", "get_option", "port_map", "list_domains", "search_options", "flake_metadata"],
            description: "Action to perform",
          },
          // [browse] params
          path: {
            type: "string",
            description: "[browse] Path relative to repo root (default: root dir)",
          },
          offset: {
            type: "number",
            description: "[browse] For files: start line (1-based, default 1)",
          },
          limit: {
            type: "number",
            description: "[browse] For files: max lines (default 200, max 500)",
          },
          recursive: {
            type: "boolean",
            description: "[browse] For directories: recurse up to 3 levels (default false)",
          },
          // [get_option] params
          option_path: {
            type: "string",
            description: "[get_option] Dot-separated option path, e.g. 'hwc.media.jellyfin.enable'",
          },
          host: {
            type: "string",
            enum: HOSTS,
            description: "[get_option/host_profile] Which host config to evaluate (default: hwc-server)",
          },
          // [port_map] params
          filter: {
            type: "string",
            description: "[port_map] Filter by service name or port number",
          },
          // [search_options] params
          query: {
            type: "string",
            description: "[search_options] Search term, e.g. 'gpu', 'port', 'enable', 'backup'",
          },
        },
        required: ["action"],
      },
      handler: async (args): Promise<ToolResult> => {
        const action = args.action as string;

        // ── get_option ───────────────────────────────────────────
        if (action === "get_option") {
          try {
            const optionPath = args.option_path as string;
            if (!optionPath) {
              return mcpError({ type: "VALIDATION_ERROR", message: "option_path is required for action=get_option" });
            }
            const host = (args.host as string) || "hwc-server";
            const value = await nixEval(nixosConfigPath, host, optionPath, declarativeTtl);
            return { status: "ok", message: `${host}: ${optionPath}`, data: { host, path: optionPath, value } };
          } catch (err) {
            return catchError("COMMAND_FAILED", "nix eval failed (is the option path correct? are changes committed?)", err, "Option paths must use dots (hwc.media.jellyfin.enable). Only committed changes are visible to nix eval.");
          }
        }

        // ── list_domains ─────────────────────────────────────────
        if (action === "list_domains") {
          try {
            const domainsDir = join(nixosConfigPath, "domains");
            const entries = await readdir(domainsDir, { withFileTypes: true });
            const domains: Array<{ domain: string; subdomains: string[]; files: string[]; hasIndex: boolean }> = [];

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

              domains.push({ domain: entry.name, subdomains: subdomains.sort(), files: files.sort(), hasIndex });
            }

            domains.sort((a, b) => a.domain.localeCompare(b.domain));
            return { status: "ok", message: `${domains.length} domains found`, data: { domains } };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to list domains", err);
          }
        }

        // ── port_map ─────────────────────────────────────────────
        if (action === "port_map") {
          try {
            const filter = (args.filter as string)?.toLowerCase();
            const routesPath = join(nixosConfigPath, "domains/networking/routes.nix");
            const content = await readFile(routesPath, "utf-8");

            const routes = parseRoutes(content);
            const filtered = filter
              ? routes.filter((r) =>
                  r.name.toLowerCase().includes(filter) ||
                  String(r.port || "").includes(filter) ||
                  (r.path || "").toLowerCase().includes(filter) ||
                  (r.upstream || "").includes(filter)
                )
              : routes;

            return { status: "ok", message: `${filtered.length} routes${filter ? ` matching '${filter}'` : ""}`, data: { routes: filtered, total: routes.length } };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to parse port map", err, "Check that domains/networking/routes.nix exists");
          }
        }

        // ── host_profile ─────────────────────────────────────────
        if (action === "host_profile") {
          try {
            const host = args.host as string;
            if (!host) {
              return mcpError({ type: "VALIDATION_ERROR", message: "host is required for action=host_profile" });
            }
            const machineName = host.replace("hwc-", "");
            const configPath = join(nixosConfigPath, "machines", machineName, "config.nix");

            let content: string;
            try {
              content = await readFile(configPath, "utf-8");
            } catch {
              return mcpError({ type: "NOT_FOUND", message: `Machine config not found: ${configPath}`, suggestion: `Valid hosts: ${HOSTS.join(", ")}`, context: { host, path: configPath } });
            }

            const imports = parseImports(content);
            const profiles = imports.filter((i) => i.includes("profiles/"));
            const domains = imports.filter((i) => i.includes("domains/"));

            const flakePath = join(nixosConfigPath, "flake.nix");
            const flakeContent = await readFile(flakePath, "utf-8");
            const isStable = flakeContent.includes(`${host} = nixpkgs-stable`) ||
                             flakeContent.includes(`${host.replace("hwc-", "")} = nixpkgs-stable`);

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
            return catchError("INTERNAL_ERROR", "Failed to get host profile", err);
          }
        }

        // ── search_options ───────────────────────────────────────
        if (action === "search_options") {
          try {
            const query = args.query as string;
            if (!query || typeof query !== "string") {
              return mcpError({ type: "VALIDATION_ERROR", message: "query parameter is required", suggestion: "Provide a search term like 'gpu', 'port', 'backup', or 'enable'" });
            }
            const lowerQuery = query.toLowerCase();
            const domainsDir = join(nixosConfigPath, "domains");
            const results = await searchOptionDeclarations(domainsDir, lowerQuery);

            const byFile = new Map<string, Array<{ line: number; name: string; type: string; default?: string }>>();
            for (const r of results) {
              if (!byFile.has(r.file)) byFile.set(r.file, []);
              const typeMatch = r.snippet.match(/type\s*=\s*(?:types\.|lib\.types\.)?([\w.]+)/);
              const defaultMatch = r.snippet.match(/default\s*=\s*([^;]{1,60})/);
              byFile.get(r.file)!.push({
                line: r.line,
                name: r.name,
                type: r.type === "enable" ? "bool" : (typeMatch?.[1] || "unknown"),
                ...(defaultMatch ? { default: defaultMatch[1].trim() } : {}),
              });
            }
            const grouped = Array.from(byFile.entries()).map(([file, options]) => ({ file, options }));

            return { status: "ok", message: `${results.length} options in ${grouped.length} files matching '${query}'`, data: { files: grouped } };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to search options", err);
          }
        }

        // ── browse ───────────────────────────────────────────────
        if (action === "browse") {
          try {
            const rawPath = (args.path as string) || ".";
            const absPath = resolve(nixosConfigPath, rawPath);
            const normalRepo = normalize(nixosConfigPath);
            if (!absPath.startsWith(normalRepo + "/") && absPath !== normalRepo) {
              return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes repo root: ${rawPath}`, suggestion: "Paths must be relative to the nixos-hwc repo root" });
            }

            let pathStat;
            try {
              pathStat = await stat(absPath);
            } catch {
              return mcpError({ type: "NOT_FOUND", message: `Not found: ${rawPath}` });
            }

            if (pathStat.isFile()) {
              const off = Math.max(1, (args.offset as number) || 1);
              const lim = Math.min(500, Math.max(1, (args.limit as number) || 200));
              const content = await readFile(absPath, "utf-8");
              const allLines = content.split("\n");
              const totalLines = allLines.length;
              const startIdx = off - 1;
              const slice = allLines.slice(startIdx, startIdx + lim);
              const numbered = slice.map((line, i) => `${String(startIdx + i + 1).padStart(5)} │ ${line}`).join("\n");

              return {
                status: "ok",
                message: `${rawPath} (lines ${off}–${Math.min(off + lim - 1, totalLines)} of ${totalLines})`,
                data: { type: "file", path: rawPath, totalLines, offset: off, limit: lim, content: numbered },
              };
            }

            const recursive = (args.recursive as boolean) ?? false;
            const entries = await listDirEntries(absPath, normalRepo, recursive ? 3 : 0);
            return {
              status: "ok",
              message: `${entries.length} entries in ${rawPath}`,
              data: { type: "directory", path: rawPath, entries },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to browse path", err);
          }
        }

        // ── flake_metadata ───────────────────────────────────────
        if (action === "flake_metadata") {
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

            return { status: "ok", message: `${inputs.length} flake inputs`, data: { inputs } };
          } catch (err) {
            return catchError("COMMAND_FAILED", "Failed to get flake metadata", err, "Is nix available and the flake.lock valid?");
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
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
  const importBlockMatch = content.match(/imports\s*=\s*\[([\s\S]*?)\];/);
  if (!importBlockMatch) return imports;

  const block = importBlockMatch[1];
  const pathRegex = /(?:\.\/)([^\s;]+\.nix)|(?:\.\.\/)+([^\s;]+\.nix)/g;
  let match: RegExpExecArray | null;

  while ((match = pathRegex.exec(block)) !== null) {
    imports.push(match[1] || match[2]);
  }

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
            const contextBefore = lines.slice(Math.max(0, i - 10), i + 1).join("\n");
            const fullPathMatch = contextBefore.match(/([\w.]+)\s*=\s*(?:lib\.)?mk(?:Option|EnableOption)/);
            let optionName = fullPathMatch?.[1] || "unknown";

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

interface DirEntry {
  name: string;
  type: "file" | "directory";
  size?: number;
  children?: DirEntry[];
}

async function listDirEntries(
  dir: string,
  repoRoot: string,
  maxDepth: number,
  depth: number = 0,
): Promise<DirEntry[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const results: DirEntry[] = [];

  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name.startsWith(".") || entry.name === "node_modules" || entry.name === "dist") continue;

    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      const item: DirEntry = { name: entry.name, type: "directory" };
      if (depth < maxDepth) {
        try {
          item.children = await listDirEntries(fullPath, repoRoot, maxDepth, depth + 1);
        } catch {
          /* unreadable */
        }
      }
      results.push(item);
    } else if (entry.isFile()) {
      try {
        const s = await stat(fullPath);
        results.push({ name: entry.name, type: "file", size: s.size });
      } catch {
        results.push({ name: entry.name, type: "file" });
      }
    }
  }

  return results;
}
