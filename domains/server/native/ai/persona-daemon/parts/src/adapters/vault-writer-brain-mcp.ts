// vault-writer-brain-mcp: implements VaultWriterPort by calling brain-mcp's
// JSON-RPC 2.0 endpoint. Single-writer principle — daemon never writes the
// vault directly; brain-mcp owns vault mutations + their hardening + their
// audit trail.

import type {
  InboxCaptureArgs,
  InboxCaptureResult,
  VaultWriterPort,
} from "../ports/vault-writer.ts";
import { PersonaDaemonError } from "../core/errors.ts";

export interface BrainMcpClientCfg {
  baseUrl: string;            // e.g. http://127.0.0.1:9876
  apiKey: string;             // bearer token (read once at startup)
  timeoutMs?: number;
}

const DEFAULT_TIMEOUT = 30_000;

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const ctrl = new AbortController();
  const tid = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } finally {
    clearTimeout(tid);
  }
}

export function createBrainMcpVaultWriter(cfg: BrainMcpClientCfg): VaultWriterPort {
  const timeout = cfg.timeoutMs ?? DEFAULT_TIMEOUT;

  return {
    async captureInbox(args: InboxCaptureArgs): Promise<InboxCaptureResult> {
      const rpcBody = {
        jsonrpc: "2.0",
        id: crypto.randomUUID(),
        method: "tools/call",
        params: {
          name: "inbox_capture",
          arguments: {
            content: args.content,
            source: args.source,
            ...(args.conversationId ? { conversation_id: args.conversationId } : {}),
            ...(args.tags && args.tags.length > 0 ? { tags: args.tags } : {}),
          },
        },
      };

      let res: Response;
      try {
        res = await fetchWithTimeout(
          `${cfg.baseUrl}/mcp`,
          {
            method: "POST",
            headers: {
              "content-type": "application/json",
              "authorization": `Bearer ${cfg.apiKey}`,
            },
            body: JSON.stringify(rpcBody),
          },
          timeout,
        );
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        throw new PersonaDaemonError(
          "VAULT_WRITER_UNAVAILABLE",
          `brain-mcp unreachable: ${msg}`,
          { endpoint: cfg.baseUrl },
        );
      }

      if (!res.ok) {
        const text = await res.text().catch(() => "<no body>");
        throw new PersonaDaemonError(
          "VAULT_WRITER_UNAVAILABLE",
          `brain-mcp returned ${res.status}`,
          { endpoint: cfg.baseUrl, status: res.status, body: text.slice(0, 500) },
        );
      }

      type RpcResp = {
        jsonrpc: "2.0";
        id: string;
        result?: { content?: Array<{ type: string; text: string }> };
        error?: { code: number; message: string };
      };
      const json = await res.json() as RpcResp;

      if (json.error) {
        throw new PersonaDaemonError(
          "VAULT_WRITER_UNAVAILABLE",
          `brain-mcp inbox_capture failed: ${json.error.message}`,
          { rpcCode: json.error.code },
        );
      }

      const text = json.result?.content?.[0]?.text ?? "";
      // brain-mcp returns "Saved: _llm-inbox/<date>/<file>.md (<n> bytes)"
      const m = text.match(/Saved:\s+(\S+)/);
      const savedPath = m ? m[1] : "";
      return { savedPath };
    },
  };
}
