/**
 * hwc_cms — consolidated CMS tool (browse, write, delete).
 */

import { readdir, readFile, writeFile, rename, mkdir, stat, unlink } from "node:fs/promises";
import { join, relative, resolve, normalize, dirname } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { mcpError, catchError } from "../errors.js";

export interface CmsScope {
  name: string;
  path: string;
  description: string;
}

function safePath(root: string, rawPath: string): string | null {
  const abs = resolve(root, rawPath);
  const normalRoot = normalize(root);
  if (!abs.startsWith(normalRoot + "/") && abs !== normalRoot) return null;
  return abs;
}

function resolveScope(scopes: CmsScope[], scopeName: string | undefined): CmsScope | null {
  if (!scopeName) return scopes[0];
  return scopes.find((s) => s.name === scopeName) || null;
}

interface DirEntry {
  name: string;
  type: "file" | "directory";
  size?: number;
  children?: DirEntry[];
}

async function listDirEntries(
  dir: string,
  maxDepth: number,
  depth: number = 0,
): Promise<DirEntry[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const results: DirEntry[] = [];

  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.name.startsWith(".") || entry.name === "node_modules") continue;

    const fullPath = join(dir, entry.name);
    if (entry.isDirectory()) {
      const item: DirEntry = { name: entry.name, type: "directory" };
      if (depth < maxDepth) {
        try {
          item.children = await listDirEntries(fullPath, maxDepth, depth + 1);
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

export function cmsTools(scopes: CmsScope[]): ToolDef[] {
  const scopeNames = scopes.map((s) => s.name);
  const scopeDescriptions = scopes.map((s) => `'${s.name}' — ${s.description}`).join("; ");

  return [
    {
      name: "hwc_cms",
      description:
        `Heartwood CMS file management. Scopes: ${scopeDescriptions}. Actions: browse, write, delete.`,
      inputSchema: {
        type: "object",
        properties: {
          action: {
            type: "string",
            enum: ["browse", "write", "delete"],
            description: "Action to perform",
          },
          scope: {
            type: "string",
            enum: scopeNames,
            description: `App scope to operate in (default: '${scopeNames[0]}')`,
          },
          // [browse] params
          path: {
            type: "string",
            description: "[browse/write/delete] Path relative to scope root (default: root dir for browse)",
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
          // [write] params
          content: {
            type: "string",
            description: "[write] Full file content to write",
          },
        },
        required: ["action"],
      },
      handler: async (args): Promise<ToolResult> => {
        const action = args.action as string;

        // ── browse ───────────────────────────────────────────────
        if (action === "browse") {
          try {
            const scope = resolveScope(scopes, args.scope as string | undefined);
            if (!scope) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid scope: ${args.scope}`, suggestion: `Valid scopes: ${scopeNames.join(", ")}` });
            }

            const root = normalize(scope.path);
            const rawPath = (args.path as string) || ".";

            const abs = safePath(root, rawPath);
            if (!abs) {
              return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes ${scope.name} root: ${rawPath}` });
            }

            let pathStat;
            try {
              pathStat = await stat(abs);
            } catch {
              return mcpError({ type: "NOT_FOUND", message: `Not found: ${rawPath}` });
            }

            if (pathStat.isFile()) {
              const off = Math.max(1, (args.offset as number) || 1);
              const lim = Math.min(500, Math.max(1, (args.limit as number) || 200));
              const content = await readFile(abs, "utf-8");
              const allLines = content.split("\n");
              const totalLines = allLines.length;
              const startIdx = off - 1;
              const slice = allLines.slice(startIdx, startIdx + lim);
              const numbered = slice.map((line, i) => `${String(startIdx + i + 1).padStart(5)} | ${line}`).join("\n");

              return {
                status: "ok",
                message: `[${scope.name}] ${rawPath} (lines ${off}-${Math.min(off + lim - 1, totalLines)} of ${totalLines})`,
                data: { type: "file", scope: scope.name, path: rawPath, totalLines, offset: off, limit: lim, content: numbered },
              };
            }

            const recursive = (args.recursive as boolean) ?? false;
            let entries: DirEntry[];
            try {
              entries = await listDirEntries(abs, recursive ? 3 : 0);
            } catch {
              return mcpError({ type: "NOT_FOUND", message: `Directory not readable: ${rawPath}` });
            }

            return {
              status: "ok",
              message: `[${scope.name}] ${entries.length} entries in ${rawPath}`,
              data: { type: "directory", scope: scope.name, path: rawPath, entries },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to browse path", err);
          }
        }

        // ── write ────────────────────────────────────────────────
        if (action === "write") {
          try {
            const scope = resolveScope(scopes, args.scope as string | undefined);
            if (!scope) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid scope: ${args.scope}`, suggestion: `Valid scopes: ${scopeNames.join(", ")}` });
            }

            const root = normalize(scope.path);
            const rawPath = args.path as string;
            const content = args.content as string;

            if (!rawPath) return mcpError({ type: "VALIDATION_ERROR", message: "path is required for action=write" });
            if (content === undefined) return mcpError({ type: "VALIDATION_ERROR", message: "content is required for action=write" });

            const abs = safePath(root, rawPath);
            if (!abs) {
              return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes ${scope.name} root: ${rawPath}` });
            }

            const relPath = relative(root, abs);
            if (relPath === "package-lock.json" || relPath === "node_modules" || relPath.startsWith("node_modules/")) {
              return mcpError({ type: "PERMISSION_DENIED", message: `Cannot write to ${relPath}`, suggestion: "Use npm to manage dependencies, not direct file writes" });
            }

            await mkdir(dirname(abs), { recursive: true });

            let writeAction: "created" | "updated";
            try {
              await stat(abs);
              writeAction = "updated";
            } catch {
              writeAction = "created";
            }

            const tmpPath = abs + ".tmp";
            await writeFile(tmpPath, content, "utf-8");
            await rename(tmpPath, abs);

            return {
              status: "ok",
              message: `[${scope.name}] ${writeAction === "created" ? "Created" : "Updated"} ${rawPath}`,
              data: { scope: scope.name, path: rawPath, action: writeAction, bytes: content.length },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to write file", err);
          }
        }

        // ── delete ───────────────────────────────────────────────
        if (action === "delete") {
          try {
            const scope = resolveScope(scopes, args.scope as string | undefined);
            if (!scope) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Invalid scope: ${args.scope}`, suggestion: `Valid scopes: ${scopeNames.join(", ")}` });
            }

            const root = normalize(scope.path);
            const rawPath = args.path as string;

            if (!rawPath) return mcpError({ type: "VALIDATION_ERROR", message: "path is required for action=delete" });

            const abs = safePath(root, rawPath);
            if (!abs) {
              return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes ${scope.name} root: ${rawPath}` });
            }

            const relPath = relative(root, abs);
            if (relPath === "package.json" || relPath === "package-lock.json" || relPath === "server.js") {
              return mcpError({ type: "PERMISSION_DENIED", message: `Cannot delete critical file: ${relPath}`, suggestion: "Edit this file instead of deleting it" });
            }

            let fileStat;
            try {
              fileStat = await stat(abs);
            } catch {
              return mcpError({ type: "NOT_FOUND", message: `File not found: ${rawPath}` });
            }

            if (!fileStat.isFile()) {
              return mcpError({ type: "VALIDATION_ERROR", message: `Not a file: ${rawPath}`, suggestion: "This tool only deletes files, not directories" });
            }

            await unlink(abs);

            return {
              status: "ok",
              message: `[${scope.name}] Deleted ${rawPath}`,
              data: { scope: scope.name, path: rawPath, action: "deleted" },
            };
          } catch (err) {
            return catchError("INTERNAL_ERROR", "Failed to delete file", err);
          }
        }

        return { status: "error", message: `Unknown action: ${action}`, error: `Unknown action: ${action}`, error_type: "VALIDATION_ERROR" };
      },
    },
  ];
}
