/**
 * hwc_cms_* tools — read/write files in Heartwood business app directories.
 *
 * Supports multiple scoped roots (CMS app, calculator, etc.).
 * Each tool takes a `scope` param to select which root to operate in.
 * Same security model as hwc_config_read_file (resolve + normalize + startsWith).
 * Write uses atomic tmp + rename.
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

/** Resolve a relative path and verify it stays within the root. */
function safePath(root: string, rawPath: string): string | null {
  const abs = resolve(root, rawPath);
  const normalRoot = normalize(root);
  if (!abs.startsWith(normalRoot + "/") && abs !== normalRoot) return null;
  return abs;
}

function resolveScope(scopes: CmsScope[], scopeName: string | undefined): CmsScope | null {
  if (!scopeName) return scopes[0]; // default to first
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
    // ── hwc_cms_list_dir ─────────────────────────────────────────────────
    {
      name: "hwc_cms_list_dir",
      description:
        "List directory contents in a Heartwood business app. " +
        `Scopes: ${scopeDescriptions}. ` +
        "Shows files with sizes and subdirectories. Set recursive=true for up to 3 levels. " +
        "Scoped — cannot escape the selected root.",
      inputSchema: {
        type: "object",
        properties: {
          scope: {
            type: "string",
            enum: scopeNames,
            description: `App scope to operate in (default: '${scopeNames[0]}')`,
          },
          path: {
            type: "string",
            description: "Directory path relative to scope root (default: root). E.g. 'lib', 'routes', 'src'",
          },
          recursive: {
            type: "boolean",
            description: "List recursively (default false, max 3 levels deep)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const scope = resolveScope(scopes, args.scope as string | undefined);
          if (!scope) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid scope: ${args.scope}`, suggestion: `Valid scopes: ${scopeNames.join(", ")}` });
          }

          const root = normalize(scope.path);
          const rawPath = (args.path as string) || ".";
          const recursive = (args.recursive as boolean) ?? false;

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes ${scope.name} root: ${rawPath}` });
          }

          let entries: DirEntry[];
          try {
            entries = await listDirEntries(abs, recursive ? 3 : 0);
          } catch {
            return mcpError({ type: "NOT_FOUND", message: `Directory not found: ${rawPath}` });
          }

          return {
            status: "ok",
            message: `[${scope.name}] ${entries.length} entries in ${rawPath}`,
            data: { scope: scope.name, path: rawPath, entries },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to list directory", err);
        }
      },
    },

    // ── hwc_cms_read_file ────────────────────────────────────────────────
    {
      name: "hwc_cms_read_file",
      description:
        "Read a file from a Heartwood business app by relative path. " +
        `Scopes: ${scopeDescriptions}. ` +
        "Supports offset/limit for large files. Returns numbered lines. " +
        "Scoped — cannot read outside the selected root.",
      inputSchema: {
        type: "object",
        properties: {
          scope: {
            type: "string",
            enum: scopeNames,
            description: `App scope to operate in (default: '${scopeNames[0]}')`,
          },
          path: {
            type: "string",
            description: "File path relative to scope root, e.g. 'server.js', 'lib/content.js', 'src/main.jsx'",
          },
          offset: {
            type: "number",
            description: "Start reading from this line number (1-based, default 1)",
          },
          limit: {
            type: "number",
            description: "Max lines to return (default 200, max 500)",
          },
        },
        required: ["path"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const scope = resolveScope(scopes, args.scope as string | undefined);
          if (!scope) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid scope: ${args.scope}`, suggestion: `Valid scopes: ${scopeNames.join(", ")}` });
          }

          const root = normalize(scope.path);
          const rawPath = args.path as string;
          const offset = Math.max(1, (args.offset as number) || 1);
          const limit = Math.min(500, Math.max(1, (args.limit as number) || 200));

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes ${scope.name} root: ${rawPath}` });
          }

          let fileStat;
          try {
            fileStat = await stat(abs);
          } catch {
            return mcpError({
              type: "NOT_FOUND",
              message: `File not found: ${rawPath}`,
              suggestion: "Use hwc_cms_list_dir to browse available files",
            });
          }
          if (!fileStat.isFile()) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Not a file: ${rawPath}`, suggestion: "Use hwc_cms_list_dir for directories" });
          }

          const content = await readFile(abs, "utf-8");
          const allLines = content.split("\n");
          const totalLines = allLines.length;
          const startIdx = offset - 1;
          const slice = allLines.slice(startIdx, startIdx + limit);
          const numbered = slice.map((line, i) => `${String(startIdx + i + 1).padStart(5)} | ${line}`).join("\n");

          return {
            status: "ok",
            message: `[${scope.name}] ${rawPath} (lines ${offset}-${Math.min(offset + limit - 1, totalLines)} of ${totalLines})`,
            data: {
              scope: scope.name,
              path: rawPath,
              totalLines,
              offset,
              limit,
              content: numbered,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to read file", err);
        }
      },
    },

    // ── hwc_cms_write_file ───────────────────────────────────────────────
    {
      name: "hwc_cms_write_file",
      description:
        "Write or create a file in a Heartwood business app. " +
        `Scopes: ${scopeDescriptions}. ` +
        "Creates parent directories if needed. Atomic write (tmp + rename). " +
        "Scoped — cannot write outside the selected root.",
      inputSchema: {
        type: "object",
        properties: {
          scope: {
            type: "string",
            enum: scopeNames,
            description: `App scope to operate in (default: '${scopeNames[0]}')`,
          },
          path: {
            type: "string",
            description: "File path relative to scope root, e.g. 'lib/content.js', 'src/main.jsx'",
          },
          content: {
            type: "string",
            description: "Full file content to write",
          },
        },
        required: ["path", "content"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const scope = resolveScope(scopes, args.scope as string | undefined);
          if (!scope) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid scope: ${args.scope}`, suggestion: `Valid scopes: ${scopeNames.join(", ")}` });
          }

          const root = normalize(scope.path);
          const rawPath = args.path as string;
          const content = args.content as string;

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes ${scope.name} root: ${rawPath}` });
          }

          // Block writing to certain sensitive paths
          const relPath = relative(root, abs);
          if (relPath === "package-lock.json" || relPath === "node_modules" || relPath.startsWith("node_modules/")) {
            return mcpError({
              type: "PERMISSION_DENIED",
              message: `Cannot write to ${relPath}`,
              suggestion: "Use npm to manage dependencies, not direct file writes",
            });
          }

          // Create parent dirs if needed
          await mkdir(dirname(abs), { recursive: true });

          // Check if update or create
          let action: "created" | "updated";
          try {
            await stat(abs);
            action = "updated";
          } catch {
            action = "created";
          }

          // Atomic write
          const tmpPath = abs + ".tmp";
          await writeFile(tmpPath, content, "utf-8");
          await rename(tmpPath, abs);

          return {
            status: "ok",
            message: `[${scope.name}] ${action === "created" ? "Created" : "Updated"} ${rawPath}`,
            data: { scope: scope.name, path: rawPath, action, bytes: content.length },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to write file", err);
        }
      },
    },

    // ── hwc_cms_delete_file ──────────────────────────────────────────────
    {
      name: "hwc_cms_delete_file",
      description:
        "Delete a file in a Heartwood business app. Permanent deletion (no trash). " +
        `Scopes: ${scopeDescriptions}. ` +
        "Scoped — cannot delete outside the selected root. Cannot delete directories.",
      inputSchema: {
        type: "object",
        properties: {
          scope: {
            type: "string",
            enum: scopeNames,
            description: `App scope to operate in (default: '${scopeNames[0]}')`,
          },
          path: {
            type: "string",
            description: "File path relative to scope root to delete",
          },
        },
        required: ["path"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const scope = resolveScope(scopes, args.scope as string | undefined);
          if (!scope) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid scope: ${args.scope}`, suggestion: `Valid scopes: ${scopeNames.join(", ")}` });
          }

          const root = normalize(scope.path);
          const rawPath = args.path as string;

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes ${scope.name} root: ${rawPath}` });
          }

          const relPath = relative(root, abs);
          if (relPath === "package.json" || relPath === "package-lock.json" || relPath === "server.js") {
            return mcpError({
              type: "PERMISSION_DENIED",
              message: `Cannot delete critical file: ${relPath}`,
              suggestion: "Edit this file instead of deleting it",
            });
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
      },
    },
  ];
}
