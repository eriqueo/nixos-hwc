// MCP tool dispatcher — shared by HTTP and stdio shells.
//
// Implements the small slice of the MCP protocol we need: initialize,
// tools/list, tools/call. Hand-rolled JSON-RPC 2.0 (matches brain-mcp's
// pattern) — pulling the full @modelcontextprotocol/sdk would add a
// dependency for what's essentially three RPC methods.

import type { ChatRequest, PersonaManifest } from "../core/types.ts";
import type { ConversationStore, VectorStore } from "../ports/store.ts";
import type { EmbedPort } from "../ports/llm.ts";
import type { VaultWriterPort } from "../ports/vault-writer.ts";
import type { LogPort } from "../ports/log.ts";
import { PersonaDaemonError } from "../core/errors.ts";

export interface McpToolsDeps {
  orchestrate: (req: ChatRequest) => Promise<import("../core/types.ts").ChatResponse>;
  personas: PersonaManifest;
  store: ConversationStore;
  vectorStore?: VectorStore;
  embed?: EmbedPort;
  vaultWriter?: VaultWriterPort;
  log: LogPort;
}

export type RpcReq = {
  jsonrpc: "2.0";
  id?: string | number | null;
  method: string;
  params?: unknown;
};
export type RpcResp = {
  jsonrpc: "2.0";
  id: string | number | null;
  result?: unknown;
  error?: { code: number; message: string };
};

const TOOL_DEFS = [
  {
    name: "chat",
    description: "Send a chat completion via the named persona. Honours useMemory/useKnowledge.",
    inputSchema: {
      type: "object",
      properties: {
        persona: { type: "string" },
        prompt: { type: "string" },
        conversation_id: { type: "string", description: "Optional uuid to continue a thread" },
        new_conversation: { type: "boolean", description: "Start a new thread (returns its id)" },
        use_knowledge: { type: "boolean", description: "Override persona's useKnowledge flag" },
        knowledge_top_k: { type: "number" },
      },
      required: ["persona", "prompt"],
    },
  },
  {
    name: "recall",
    description: "Top-K cosine retrieval over the brain vault index. Returns chunk metadata + bodies.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
        top_k: { type: "number", description: "Default 6" },
      },
      required: ["query"],
    },
  },
  {
    name: "list_personas",
    description: "Return all persona metadata (model, description, useMemory/useKnowledge flags).",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "list_conversations",
    description: "List conversations, newest first. Optional persona filter + limit.",
    inputSchema: {
      type: "object",
      properties: {
        persona: { type: "string" },
        limit: { type: "number", description: "Default 50" },
      },
    },
  },
  {
    name: "inbox_capture",
    description: "Persist a derived insight back to the brain vault via brain-mcp's inbox_capture tool. Single-writer principle — daemon does not write the vault directly.",
    inputSchema: {
      type: "object",
      properties: {
        content: { type: "string" },
        source: { type: "string", description: "e.g. 'persona-daemon:assistant'" },
        conversation_id: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
      },
      required: ["content", "source"],
    },
  },
];

type ToolArgs = Record<string, unknown>;

async function callTool(name: string, args: ToolArgs, deps: McpToolsDeps): Promise<unknown> {
  switch (name) {
    case "chat": {
      const persona = String(args.persona ?? "");
      const prompt = String(args.prompt ?? "");
      if (!persona || !prompt) {
        throw new PersonaDaemonError("INVALID_REQUEST", "chat requires persona + prompt");
      }
      const req: ChatRequest = {
        persona,
        messages: [{ role: "user", content: prompt }],
        new_conversation: !!args.new_conversation,
        ...(args.conversation_id
          ? { conversation_id: String(args.conversation_id) } : {}),
        ...(typeof args.use_knowledge === "boolean"
          ? { use_knowledge: args.use_knowledge } : {}),
        ...(typeof args.knowledge_top_k === "number"
          ? { knowledge_top_k: args.knowledge_top_k } : {}),
      };
      const res = await deps.orchestrate(req);
      return {
        content: [{ type: "text", text: res.choices[0].message.content }],
        meta: {
          persona: res.persona,
          conversation_id: res.conversation_id,
          model: res.model,
          usage: res.usage,
        },
      };
    }

    case "recall": {
      if (!deps.vectorStore || !deps.embed) {
        throw new PersonaDaemonError(
          "EMBED_UNAVAILABLE",
          "recall requires the embed + vector subsystem (set vaultPath)",
        );
      }
      const query = String(args.query ?? "");
      const topK = typeof args.top_k === "number" ? args.top_k : 6;
      if (!query) throw new PersonaDaemonError("INVALID_REQUEST", "query required");
      const [vec] = await deps.embed.embed([query]);
      const hits = await deps.vectorStore.topK(vec, topK);
      return {
        content: [{
          type: "text",
          text: hits.map((h, i) =>
            `[${i + 1}] ${h.notePath} :: ${h.sectionTitle} (score=${h.score.toFixed(4)})\n${h.body}`
          ).join("\n\n---\n\n"),
        }],
        meta: { hits: hits.length, top_k: topK },
      };
    }

    case "list_personas": {
      return {
        content: [{ type: "text", text: JSON.stringify(deps.personas, null, 2) }],
        meta: { count: Object.keys(deps.personas).length },
      };
    }

    case "list_conversations": {
      const persona = args.persona ? String(args.persona) : undefined;
      const limit = typeof args.limit === "number" ? args.limit : 50;
      const rows = await deps.store.list({ personaId: persona, limit });
      return {
        content: [{ type: "text", text: JSON.stringify(rows, null, 2) }],
        meta: { count: rows.length },
      };
    }

    case "inbox_capture": {
      if (!deps.vaultWriter) {
        throw new PersonaDaemonError(
          "VAULT_WRITER_UNAVAILABLE",
          "inbox_capture not wired (brain-mcp URL not configured)",
        );
      }
      const content = String(args.content ?? "");
      const source = String(args.source ?? "");
      if (!content || !source) {
        throw new PersonaDaemonError(
          "INVALID_REQUEST",
          "inbox_capture requires content + source",
        );
      }
      const result = await deps.vaultWriter.captureInbox({
        content,
        source,
        conversationId: args.conversation_id ? String(args.conversation_id) : undefined,
        tags: Array.isArray(args.tags) ? args.tags.map(String) : undefined,
      });
      return {
        content: [{ type: "text", text: `Saved: ${result.savedPath}` }],
        meta: { savedPath: result.savedPath },
      };
    }

    default:
      throw new PersonaDaemonError(
        "INVALID_REQUEST",
        `unknown tool: ${name}`,
        { available: TOOL_DEFS.map((t) => t.name) },
      );
  }
}

function rpcError(id: string | number | null, code: number, message: string): RpcResp {
  return { jsonrpc: "2.0", id, error: { code, message } };
}

export async function handleRpc(req: RpcReq, deps: McpToolsDeps): Promise<RpcResp> {
  const id = req.id ?? null;
  try {
    switch (req.method) {
      case "initialize":
        return {
          jsonrpc: "2.0", id,
          result: {
            protocolVersion: "2024-11-05",
            serverInfo: { name: "persona-daemon", version: "0.3.0" },
            capabilities: { tools: {} },
          },
        };

      case "tools/list":
        return { jsonrpc: "2.0", id, result: { tools: TOOL_DEFS } };

      case "tools/call": {
        const p = req.params as { name?: string; arguments?: ToolArgs } | undefined;
        if (!p?.name) return rpcError(id, -32602, "tools/call: missing name");
        const result = await callTool(p.name, p.arguments ?? {}, deps);
        return { jsonrpc: "2.0", id, result };
      }

      case "notifications/initialized":
      case "notifications/cancelled":
        // Per MCP: notifications don't get responses.
        return { jsonrpc: "2.0", id, result: null };

      default:
        return rpcError(id, -32601, `method not found: ${req.method}`);
    }
  } catch (e) {
    if (e instanceof PersonaDaemonError) {
      deps.log.warn("mcp.tool_error", { code: e.code, detail: e.detail });
      return rpcError(id, -32000, `${e.code}: ${e.message}`);
    }
    const msg = e instanceof Error ? e.message : String(e);
    deps.log.error("mcp.unhandled", { msg });
    return rpcError(id, -32603, `internal error: ${msg}`);
  }
}
