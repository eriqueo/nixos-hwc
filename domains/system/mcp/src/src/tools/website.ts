/**
 * hwc_website_* tools — read/write the Heartwood Craft 11ty site source.
 *
 * Content lives at ${nixosConfigPath}/domains/business/website/site_files/src/
 *   - pages/   (.md, .njk)  — static pages with YAML frontmatter
 *   - blog/    (.md)        — blog posts with YAML frontmatter
 *   - _data/   (.json)      — structured data (testimonials, site config, etc.)
 *
 * Uses gray-matter for frontmatter parsing/serialization (same as the CMS).
 * All writes are atomic (tmp + rename).
 */

import { readdir, readFile, writeFile, rename, mkdir, stat } from "node:fs/promises";
import { join, basename, extname } from "node:path";
import matter from "gray-matter";
import type { ToolDef, ToolResult } from "../types.js";
import { mcpError, catchError } from "../errors.js";

const CONTENT_TYPES = ["pages", "blog"] as const;
type ContentType = (typeof CONTENT_TYPES)[number];

const PAGE_EXTENSIONS = [".md", ".njk"];

function isValidSlug(slug: string): boolean {
  return /^[a-z0-9][a-z0-9-]*[a-z0-9]$/.test(slug) && !slug.includes("..");
}

export function websiteTools(nixosConfigPath: string): ToolDef[] {
  const siteRoot = join(nixosConfigPath, "domains/business/website/site_files/src");

  function contentDir(type: ContentType): string {
    return type === "pages" ? join(siteRoot, "pages") : join(siteRoot, "blog");
  }

  return [
    // ── hwc_website_list ─────────────────────────────────────────────────
    {
      name: "hwc_website_list",
      description:
        "List website pages or blog posts with frontmatter summaries. " +
        "Returns slug, title, date, and other frontmatter fields for each file.",
      inputSchema: {
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: CONTENT_TYPES,
            description: "Content type: 'pages' for static pages, 'blog' for blog posts",
          },
        },
        required: ["type"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const type = args.type as ContentType;
          if (!CONTENT_TYPES.includes(type)) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid type: ${type}`, suggestion: "Use 'pages' or 'blog'" });
          }

          const dir = contentDir(type);
          let entries: string[];
          try {
            entries = await readdir(dir);
          } catch {
            return mcpError({ type: "NOT_FOUND", message: `Content directory not found: ${dir}` });
          }

          const files = entries.filter((f) => {
            const ext = extname(f).toLowerCase();
            return PAGE_EXTENSIONS.includes(ext) && !f.startsWith(".");
          });

          const items = await Promise.all(
            files.map(async (f) => {
              const filePath = join(dir, f);
              const raw = await readFile(filePath, "utf-8");
              const { data: frontmatter } = matter(raw);
              const s = await stat(filePath);
              return {
                slug: basename(f, extname(f)),
                extension: extname(f),
                frontmatter,
                lastModified: s.mtime.toISOString(),
              };
            }),
          );

          // Blog sorted by date descending, pages alphabetically
          if (type === "blog") {
            items.sort((a, b) => {
              const da = a.frontmatter.date ? new Date(a.frontmatter.date as string).getTime() : 0;
              const db = b.frontmatter.date ? new Date(b.frontmatter.date as string).getTime() : 0;
              return db - da;
            });
          } else {
            items.sort((a, b) => a.slug.localeCompare(b.slug));
          }

          return {
            status: "ok",
            message: `${items.length} ${type}`,
            data: { type, items },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to list content", err);
        }
      },
    },

    // ── hwc_website_read ─────────────────────────────────────────────────
    {
      name: "hwc_website_read",
      description:
        "Read a website page or blog post by slug. Returns parsed YAML frontmatter " +
        "as an object and the markdown body separately. Supports .md and .njk files.",
      inputSchema: {
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: CONTENT_TYPES,
            description: "Content type: 'pages' or 'blog'",
          },
          slug: {
            type: "string",
            description: "File slug (filename without extension), e.g. 'about', 'bathroom-remodeling'",
          },
        },
        required: ["type", "slug"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const type = args.type as ContentType;
          const slug = args.slug as string;

          if (!CONTENT_TYPES.includes(type)) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid type: ${type}` });
          }

          const dir = contentDir(type);

          // Try each extension
          let filePath: string | undefined;
          let ext: string | undefined;
          for (const e of PAGE_EXTENSIONS) {
            const candidate = join(dir, `${slug}${e}`);
            try {
              await stat(candidate);
              filePath = candidate;
              ext = e;
              break;
            } catch {
              // try next
            }
          }

          if (!filePath || !ext) {
            return mcpError({
              type: "NOT_FOUND",
              message: `${type} '${slug}' not found`,
              suggestion: `Use hwc_website_list to see available ${type}`,
            });
          }

          const raw = await readFile(filePath, "utf-8");
          const { data: frontmatter, content: body } = matter(raw);
          const s = await stat(filePath);

          return {
            status: "ok",
            message: `${type}/${slug}${ext}`,
            data: {
              type,
              slug,
              extension: ext,
              frontmatter,
              body,
              lastModified: s.mtime.toISOString(),
            },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to read content", err);
        }
      },
    },

    // ── hwc_website_write ────────────────────────────────────────────────
    {
      name: "hwc_website_write",
      description:
        "Create or update a website page or blog post. Accepts frontmatter (object) and " +
        "markdown body (string). Atomic write (tmp + rename). For new files, slug must be " +
        "lowercase alphanumeric with hyphens. Set create_new=true to create (prevents accidental overwrites).",
      inputSchema: {
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: CONTENT_TYPES,
            description: "Content type: 'pages' or 'blog'",
          },
          slug: {
            type: "string",
            description: "File slug (filename without extension)",
          },
          frontmatter: {
            type: "object",
            description: "YAML frontmatter fields (title, description, date, layout, etc.)",
          },
          body: {
            type: "string",
            description: "Markdown body content",
          },
          create_new: {
            type: "boolean",
            description: "Set true to create a new file. Fails if file already exists. Default false (update).",
          },
        },
        required: ["type", "slug", "frontmatter", "body"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const type = args.type as ContentType;
          const slug = args.slug as string;
          const frontmatter = args.frontmatter as Record<string, unknown>;
          const body = args.body as string;
          const createNew = (args.create_new as boolean) ?? false;

          if (!CONTENT_TYPES.includes(type)) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid type: ${type}` });
          }

          if (!isValidSlug(slug)) {
            return mcpError({
              type: "VALIDATION_ERROR",
              message: `Invalid slug: "${slug}"`,
              suggestion: "Slugs must be lowercase alphanumeric with hyphens, no '..' allowed",
            });
          }

          const dir = contentDir(type);
          const filePath = join(dir, `${slug}.md`);

          if (createNew) {
            // Check it doesn't already exist (any extension)
            for (const e of PAGE_EXTENSIONS) {
              try {
                await stat(join(dir, `${slug}${e}`));
                return mcpError({
                  type: "VALIDATION_ERROR",
                  message: `File already exists: ${slug}${e}`,
                  suggestion: "Omit create_new to update an existing file",
                });
              } catch {
                // good — doesn't exist
              }
            }
          } else {
            // Update mode — verify file exists (try all extensions, write to the one found)
            let found = false;
            for (const e of PAGE_EXTENSIONS) {
              try {
                await stat(join(dir, `${slug}${e}`));
                found = true;
                // If it's .njk, keep the original extension
                if (e === ".njk") {
                  const njkPath = join(dir, `${slug}.njk`);
                  const content = matter.stringify(body, frontmatter);
                  const tmpPath = njkPath + ".tmp";
                  await writeFile(tmpPath, content, "utf-8");
                  await rename(tmpPath, njkPath);
                  return {
                    status: "ok",
                    message: `Updated ${type}/${slug}.njk`,
                    data: { type, slug, path: `${type}/${slug}.njk`, action: "updated" },
                  };
                }
                break;
              } catch {
                // try next
              }
            }
            if (!found) {
              return mcpError({
                type: "NOT_FOUND",
                message: `${type} '${slug}' not found`,
                suggestion: "Set create_new=true to create a new file, or use hwc_website_list to check available slugs",
              });
            }
          }

          const content = matter.stringify(body, frontmatter);
          const tmpPath = filePath + ".tmp";
          await writeFile(tmpPath, content, "utf-8");
          await rename(tmpPath, filePath);

          return {
            status: "ok",
            message: `${createNew ? "Created" : "Updated"} ${type}/${slug}.md`,
            data: { type, slug, path: `${type}/${slug}.md`, action: createNew ? "created" : "updated" },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to write content", err);
        }
      },
    },

    // ── hwc_website_delete ───────────────────────────────────────────────
    {
      name: "hwc_website_delete",
      description:
        "Soft-delete a website page or blog post by moving it to a .trash/ directory " +
        "with a timestamp prefix. Can be recovered manually.",
      inputSchema: {
        type: "object",
        properties: {
          type: {
            type: "string",
            enum: CONTENT_TYPES,
            description: "Content type: 'pages' or 'blog'",
          },
          slug: {
            type: "string",
            description: "File slug to delete",
          },
        },
        required: ["type", "slug"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const type = args.type as ContentType;
          const slug = args.slug as string;

          if (!CONTENT_TYPES.includes(type)) {
            return mcpError({ type: "VALIDATION_ERROR", message: `Invalid type: ${type}` });
          }

          const dir = contentDir(type);

          // Find the file
          let filePath: string | undefined;
          for (const e of PAGE_EXTENSIONS) {
            const candidate = join(dir, `${slug}${e}`);
            try {
              await stat(candidate);
              filePath = candidate;
              break;
            } catch {
              // try next
            }
          }

          if (!filePath) {
            return mcpError({ type: "NOT_FOUND", message: `${type} '${slug}' not found` });
          }

          // Move to .trash/
          const trashDir = join(siteRoot, "..", ".trash");
          await mkdir(trashDir, { recursive: true });
          const filename = basename(filePath);
          const trashedPath = join(trashDir, `${Date.now()}-${filename}`);
          await rename(filePath, trashedPath);

          return {
            status: "ok",
            message: `Soft-deleted ${type}/${filename}`,
            data: { type, slug, trashedTo: trashedPath },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to delete content", err);
        }
      },
    },

    // ── hwc_website_read_data ────────────────────────────────────────────
    {
      name: "hwc_website_read_data",
      description:
        "Read a JSON data file from the site's _data/ directory. " +
        "Available files: testimonials.json, site.json, navigation.json, header.json, " +
        "services.json, calculator-bathroom.json, calculator-deck.json.",
      inputSchema: {
        type: "object",
        properties: {
          name: {
            type: "string",
            description: "Data file name without .json extension, e.g. 'testimonials', 'site'",
          },
        },
        required: ["name"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const name = args.name as string;

          // Security: no path traversal
          if (name.includes("..") || name.includes("/") || name.includes("\\")) {
            return mcpError({ type: "VALIDATION_ERROR", message: "Invalid data file name" });
          }

          const filePath = join(siteRoot, "_data", `${name}.json`);
          let content: string;
          try {
            content = await readFile(filePath, "utf-8");
          } catch {
            // List available files for suggestion
            const dataDir = join(siteRoot, "_data");
            const files = (await readdir(dataDir)).filter((f) => f.endsWith(".json"));
            return mcpError({
              type: "NOT_FOUND",
              message: `Data file '${name}.json' not found`,
              suggestion: `Available: ${files.map((f) => f.replace(".json", "")).join(", ")}`,
            });
          }

          const data = JSON.parse(content);
          return {
            status: "ok",
            message: `_data/${name}.json`,
            data: { name, content: data },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to read data file", err);
        }
      },
    },

    // ── hwc_website_write_data ───────────────────────────────────────────
    {
      name: "hwc_website_write_data",
      description:
        "Write a JSON data file to the site's _data/ directory. Atomic write. " +
        "Content must be valid JSON. Overwrites the existing file.",
      inputSchema: {
        type: "object",
        properties: {
          name: {
            type: "string",
            description: "Data file name without .json extension, e.g. 'testimonials', 'site'",
          },
          content: {
            type: ["object", "array"],
            description: "JSON content to write (object or array)",
          },
        },
        required: ["name", "content"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const name = args.name as string;
          const content = args.content;

          if (name.includes("..") || name.includes("/") || name.includes("\\")) {
            return mcpError({ type: "VALIDATION_ERROR", message: "Invalid data file name" });
          }

          const filePath = join(siteRoot, "_data", `${name}.json`);
          const json = JSON.stringify(content, null, 2) + "\n";
          const tmpPath = filePath + ".tmp";
          await writeFile(tmpPath, json, "utf-8");
          await rename(tmpPath, filePath);

          return {
            status: "ok",
            message: `Wrote _data/${name}.json`,
            data: { name, path: `_data/${name}.json`, bytes: json.length },
          };
        } catch (err) {
          return catchError("INTERNAL_ERROR", "Failed to write data file", err);
        }
      },
    },
  ];
}
