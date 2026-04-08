/**
 * hwc_cms_* tools — read/write files in the Heartwood CMS application.
 *
 * Root: /opt/business/heartwood-cms/ (configurable via HWC_CMS_APP_PATH).
 * Provides general-purpose file operations scoped to the CMS directory:
 * list, read, write, delete. Same security model as hwc_config_read_file
 * (resolve + normalize + startsWith). Write uses atomic tmp + rename.
 */

import { readdir, readFile, writeFile, rename, mkdir, stat, unlink } from "node:fs/promises";
import { join, relative, resolve, normalize, dirname } from "node:path";
import type { ToolDef, ToolResult } from "../types.js";
import { mcpError, catchError } from "../errors.js";

/** Resolve a relative path and verify it stays within the root. */
function safePath(root: string, rawPath: string): string | null {
  const abs = resolve(root, rawPath);
  const normalRoot = normalize(root);
  if (!abs.startsWith(normalRoot + "/") && abs !== normalRoot) return null;
  return abs;
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
    // Skip hidden dirs, node_modules, dist, .git
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

export function cmsTools(cmsAppPath: string): ToolDef[] {
  const root = normalize(cmsAppPath);

  return [
    // ── hwc_cms_list_dir ─────────────────────────────────────────────────
    {
      name: "hwc_cms_list_dir",
      description:
        "List directory contents in the Heartwood CMS app (/opt/business/heartwood-cms/). " +
        "Shows files with sizes and subdirectories. Set recursive=true for up to 3 levels. " +
        "Scoped — cannot escape the CMS root.",
      inputSchema: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Directory path relative to CMS root (default: root). E.g. 'lib', 'routes', 'public/js'",
          },
          recursive: {
            type: "boolean",
            description: "List recursively (default false, max 3 levels deep)",
          },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const rawPath = (args.path as string) || ".";
          const recursive = (args.recursive as boolean) ?? false;

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes CMS root: ${rawPath}` });
          }

          let entries: DirEntry[];
          try {
            entries = await listDirEntries(abs, recursive ? 3 : 0);
          } catch {
            return mcpError({ type: "NOT_FOUND", message: `Directory not found: ${rawPath}` });
          }

          return {
            status: "ok",
            message: `${entries.length} entries in ${rawPath}`,
            data: { path: rawPath, entries },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to list CMS directory", err);
        }
      },
    },

    // ── hwc_cms_read_file ────────────────────────────────────────────────
    {
      name: "hwc_cms_read_file",
      description:
        "Read a file from the Heartwood CMS app by relative path. Supports offset/limit " +
        "for large files. Returns numbered lines. Scoped — cannot read outside CMS root.",
      inputSchema: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "File path relative to CMS root, e.g. 'server.js', 'lib/content.js', 'public/js/app.js'",
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
          const rawPath = args.path as string;
          const offset = Math.max(1, (args.offset as number) || 1);
          const limit = Math.min(500, Math.max(1, (args.limit as number) || 200));

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes CMS root: ${rawPath}` });
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
            message: `${rawPath} (lines ${offset}-${Math.min(offset + limit - 1, totalLines)} of ${totalLines})`,
            data: {
              path: rawPath,
              totalLines,
              offset,
              limit,
              content: numbered,
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to read CMS file", err);
        }
      },
    },

    // ── hwc_cms_write_file ───────────────────────────────────────────────
    {
      name: "hwc_cms_write_file",
      description:
        "Write or create a file in the Heartwood CMS app. Creates parent directories if needed. " +
        "Atomic write (tmp + rename). Scoped — cannot write outside CMS root. " +
        "Use for editing source code: server.js, lib/*.js, routes/*.js, public/js/*.js, public/css/*.css.",
      inputSchema: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "File path relative to CMS root, e.g. 'lib/content.js', 'routes/pages.js'",
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
          const rawPath = args.path as string;
          const content = args.content as string;

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes CMS root: ${rawPath}` });
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
            message: `${action === "created" ? "Created" : "Updated"} ${rawPath}`,
            data: { path: rawPath, action, bytes: content.length },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to write CMS file", err);
        }
      },
    },

    // ── hwc_cms_delete_file ──────────────────────────────────────────────
    {
      name: "hwc_cms_delete_file",
      description:
        "Delete a file in the Heartwood CMS app. Permanent deletion (no trash). " +
        "Scoped — cannot delete outside CMS root. Cannot delete directories.",
      inputSchema: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "File path relative to CMS root to delete",
          },
        },
        required: ["path"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const rawPath = args.path as string;

          const abs = safePath(root, rawPath);
          if (!abs) {
            return mcpError({ type: "PERMISSION_DENIED", message: `Path escapes CMS root: ${rawPath}` });
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
            message: `Deleted ${rawPath}`,
            data: { path: rawPath, action: "deleted" },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to delete CMS file", err);
        }
      },
    },
  ];
}
