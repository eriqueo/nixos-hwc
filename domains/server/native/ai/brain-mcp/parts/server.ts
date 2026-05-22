#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env
/**
 * brain-mcp/parts/server.ts
 *
 * MCP server exposing the brain vault as 6 tools via Streamable HTTP transport.
 * Protocol: JSON-RPC 2.0 over HTTP POST (MCP spec 2024-11-05).
 * Auth: Bearer token read from BRAIN_MCP_KEY_FILE at startup.
 */

import { join, resolve, relative, dirname } from "jsr:@std/path@1";
import { walk, exists } from "jsr:@std/fs@1";

// ── Configuration ────────────────────────────────────────────────────────────
const VAULT_ROOT = resolve(Deno.env.get("BRAIN_VAULT_ROOT") ?? "/mnt/vaults/brain");
const PORT = parseInt(Deno.env.get("BRAIN_MCP_PORT") ?? "9876");
const KEY_FILE = Deno.env.get("BRAIN_MCP_KEY_FILE") ?? "/run/agenix/brain-mcp-api-key";

let API_KEY: string;
try {
  API_KEY = (await Deno.readTextFile(KEY_FILE)).trim();
} catch (e) {
  console.error(`[brain-mcp] Cannot read API key from ${KEY_FILE}: ${e}`);
  Deno.exit(1);
}

// ── Path safety ──────────────────────────────────────────────────────────────
function safePath(rel: string): string {
  const normalized = resolve(join(VAULT_ROOT, rel));
  if (!normalized.startsWith(VAULT_ROOT + "/") && normalized !== VAULT_ROOT) {
    throw new Error(`Path traversal attempt blocked: ${rel}`);
  }
  return normalized;
}

// ── MCP tool definitions ─────────────────────────────────────────────────────
const TOOL_DEFS = [
  {
    name: "read_note",
    description: "Read a note from the brain vault by relative path",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to vault root (e.g. wiki/foo.md)" }
      },
      required: ["path"]
    }
  },
  {
    name: "write_note",
    description: "Create or overwrite a note in the brain vault",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Path relative to vault root" },
        content: { type: "string", description: "Full file content to write" }
      },
      required: ["path", "content"]
    }
  },
  {
    name: "list_notes",
    description: "List .md files in a vault folder (recursive)",
    inputSchema: {
      type: "object",
      properties: {
        folder: { type: "string", description: "Folder relative to vault root. Omit to list all notes." }
      }
    }
  },
  {
    name: "search_notes",
    description: "Full-text search across vault notes using ripgrep",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query (ripgrep regex)" },
        folder: { type: "string", description: "Optional subfolder to limit search scope" }
      },
      required: ["query"]
    }
  },
  {
    name: "lint_wiki",
    description: "Check wiki health: orphan pages, broken [[wikilinks]], frontmatter issues",
    inputSchema: {
      type: "object",
      properties: {}
    }
  },
  {
    name: "append_to_inbox",
    description: "Write a fleeting note to inbox/ for later processing",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string", description: "Note content to save" },
        filename: { type: "string", description: "Filename (auto-generated timestamp if omitted)" }
      },
      required: ["content"]
    }
  }
];

// ── Tool implementations ──────────────────────────────────────────────────────
type ToolArgs = Record<string, unknown>;
type ToolResult = { content: Array<{ type: string; text: string }> };

async function callTool(name: string, args: ToolArgs): Promise<ToolResult> {
  switch (name) {
    case "read_note": {
      const path = String(args.path);
      const full = safePath(path);
      const text = await Deno.readTextFile(full);
      return { content: [{ type: "text", text }] };
    }

    case "write_note": {
      const path = String(args.path);
      const content = String(args.content);
      const full = safePath(path);
      await Deno.mkdir(dirname(full), { recursive: true });
      await Deno.writeTextFile(full, content);
      return { content: [{ type: "text", text: `Written: ${path} (${content.length} bytes)` }] };
    }

    case "list_notes": {
      const folder = args.folder ? String(args.folder) : undefined;
      const dir = folder ? safePath(folder) : VAULT_ROOT;
      const files: string[] = [];
      for await (const entry of walk(dir, {
        exts: [".md"],
        skip: [/\/.obsidian\//, /\/.git\//, /\/.trash\//],
        includeDirs: false,
      })) {
        files.push(relative(VAULT_ROOT, entry.path));
      }
      files.sort();
      return { content: [{ type: "text", text: files.length > 0 ? files.join("\n") : "(empty)" }] };
    }

    case "search_notes": {
      const query = String(args.query);
      const folder = args.folder ? String(args.folder) : undefined;
      const searchDir = folder ? safePath(folder) : VAULT_ROOT;

      const cmd = new Deno.Command("rg", {
        args: ["--with-filename", "--line-number", "--color", "never", query, searchDir],
        stdout: "piped",
        stderr: "piped",
      });
      const { stdout } = await cmd.output();
      const raw = new TextDecoder().decode(stdout);
      // Make paths relative to vault root for cleaner output
      const output = raw.replaceAll(VAULT_ROOT + "/", "");
      return { content: [{ type: "text", text: output || "No matches found." }] };
    }

    case "lint_wiki": {
      const wikiDir = join(VAULT_ROOT, "wiki");
      if (!await exists(wikiDir)) {
        return { content: [{ type: "text", text: "wiki/ directory not found or empty." }] };
      }

      const wikiFiles = new Map<string, string>(); // slug → full path
      const inbound = new Map<string, Set<string>>(); // slug → set of pages linking to it

      for await (const entry of walk(wikiDir, { exts: [".md"], includeDirs: false })) {
        const slug = entry.name.replace(/\.md$/, "");
        wikiFiles.set(slug, entry.path);
        inbound.set(slug, new Set());
      }

      const brokenLinks: string[] = [];
      const frontmatterIssues: string[] = [];

      for (const [slug, path] of wikiFiles) {
        const content = await Deno.readTextFile(path);

        if (!content.startsWith("---")) {
          frontmatterIssues.push(`${slug}: missing frontmatter`);
        }

        for (const m of content.matchAll(/\[\[([^\]|#]+)/g)) {
          const target = m[1].trim().replace(/\.md$/, "");
          if (wikiFiles.has(target)) {
            inbound.get(target)!.add(slug);
          } else {
            brokenLinks.push(`${slug} → [[${m[1].trim()}]]`);
          }
        }
      }

      const orphans = [...wikiFiles.keys()].filter(
        (slug) => !slug.startsWith("_") && (inbound.get(slug)?.size ?? 0) === 0
      );

      const report = [
        `# Wiki Lint Report — ${new Date().toISOString().slice(0, 10)}`,
        `\nTotal wiki pages: ${wikiFiles.size}`,
        `\n## Broken wikilinks (${brokenLinks.length})`,
        ...brokenLinks.map((l) => `- ${l}`),
        `\n## Orphan pages (${orphans.length})`,
        ...orphans.map((p) => `- ${p}`),
        `\n## Frontmatter issues (${frontmatterIssues.length})`,
        ...frontmatterIssues.map((i) => `- ${i}`),
      ].join("\n");

      return { content: [{ type: "text", text: report }] };
    }

    case "append_to_inbox": {
      const content = String(args.content);
      const ts = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
      const filename = args.filename ? String(args.filename) : `capture-${ts}.md`;
      const full = safePath(`inbox/${filename}`);
      await Deno.mkdir(dirname(full), { recursive: true });
      await Deno.writeTextFile(full, content);
      return { content: [{ type: "text", text: `Saved: inbox/${filename}` }] };
    }

    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

// ── JSON-RPC protocol ─────────────────────────────────────────────────────────
type RpcReq = { jsonrpc: "2.0"; id?: string | number | null; method: string; params?: unknown };
type RpcResp = { jsonrpc: "2.0"; id: string | number | null; result?: unknown; error?: { code: number; message: string } };

function rpcError(id: string | number | null, code: number, message: string): RpcResp {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

async function handleRpc(req: RpcReq): Promise<RpcResp | null> {
  const id = req.id ?? null;
  try {
    switch (req.method) {
      case "initialize":
        return {
          jsonrpc: "2.0", id,
          result: {
            protocolVersion: "2024-11-05",
            serverInfo: { name: "brain-mcp", version: "1.0.0" },
            capabilities: { tools: {} },
          },
        };

      case "notifications/initialized":
        return null; // notifications have no response

      case "ping":
        return { jsonrpc: "2.0", id, result: {} };

      case "tools/list":
        return { jsonrpc: "2.0", id, result: { tools: TOOL_DEFS } };

      case "tools/call": {
        const p = req.params as { name: string; arguments?: ToolArgs };
        const result = await callTool(p.name, p.arguments ?? {});
        return { jsonrpc: "2.0", id, result };
      }

      default:
        return rpcError(id, -32601, `Method not found: ${req.method}`);
    }
  } catch (e) {
    return rpcError(id, -32603, e instanceof Error ? e.message : String(e));
  }
}

// ── HTTP server ───────────────────────────────────────────────────────────────
Deno.serve({ port: PORT, hostname: "127.0.0.1" }, async (req: Request): Promise<Response> => {
  const url = new URL(req.url);

  // Health check — no auth required
  if (url.pathname === "/health" && req.method === "GET") {
    return Response.json({ status: "ok", service: "brain-mcp", vault: VAULT_ROOT, port: PORT });
  }

  // Bearer token auth for all /mcp routes
  const authHeader = req.headers.get("authorization") ?? "";
  if (authHeader !== `Bearer ${API_KEY}`) {
    return new Response("Unauthorized", {
      status: 401,
      headers: { "WWW-Authenticate": "Bearer" },
    });
  }

  if (url.pathname === "/mcp" || url.pathname === "/mcp/") {
    if (req.method !== "POST") {
      return new Response("Method Not Allowed — use POST for MCP", { status: 405 });
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return Response.json(rpcError(null, -32700, "Parse error: invalid JSON"), { status: 400 });
    }

    if (Array.isArray(body)) {
      const results = (
        await Promise.all(body.map((r) => handleRpc(r as RpcReq)))
      ).filter((r): r is RpcResp => r !== null);
      return Response.json(results, { headers: { "Content-Type": "application/json" } });
    }

    const result = await handleRpc(body as RpcReq);
    if (result === null) return new Response(null, { status: 204 });
    return Response.json(result, { headers: { "Content-Type": "application/json" } });
  }

  return new Response("Not Found", { status: 404 });
});

console.log(`[brain-mcp] Listening on 127.0.0.1:${PORT} — vault: ${VAULT_ROOT}`);
