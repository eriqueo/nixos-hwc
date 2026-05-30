// MCP-over-HTTP shell. Mounted at /mcp on the same port as the OpenAI shell.
// Mirrors brain-mcp's transport: POST /mcp with a JSON-RPC body, returns
// JSON-RPC response. No SSE (yet).

import { handleRpc, type McpToolsDeps, type RpcReq } from "./mcp-tools.ts";

export function createMcpHttpShell(deps: McpToolsDeps) {
  return async function handle(req: Request): Promise<Response | null> {
    const url = new URL(req.url);
    if (url.pathname !== "/mcp") return null;

    if (req.method === "GET") {
      // Capability probe — return a minimal JSON describing the endpoint.
      return new Response(JSON.stringify({
        protocol: "mcp-2024-11-05",
        transport: "json-rpc-http",
        post: "/mcp",
      }), { status: 200, headers: { "content-type": "application/json" } });
    }

    if (req.method !== "POST") {
      return new Response("method not allowed", { status: 405 });
    }

    let body: RpcReq;
    try {
      body = await req.json() as RpcReq;
    } catch {
      return new Response(JSON.stringify({
        jsonrpc: "2.0", id: null,
        error: { code: -32700, message: "parse error" },
      }), { status: 400, headers: { "content-type": "application/json" } });
    }

    const result = await handleRpc(body, deps);
    return new Response(JSON.stringify(result), {
      status: 200, headers: { "content-type": "application/json" },
    });
  };
}
