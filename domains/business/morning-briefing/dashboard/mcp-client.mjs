// The same StreamableHTTP session serves headless gathers and browser actions.
// Requests are never replayed: a lost reply may follow a completed mutation.
export function createMcpClient({ url, fetch: fetchRequest, timeoutMs, clientInfo }) {
  let sessionId = null;
  const initialProtocolVersion = "2025-06-18";
  let protocolVersion = initialProtocolVersion;
  let sequence = 0;
  let initialization = null;

  async function rpc(method, params) {
    const notification = method.startsWith("notifications/");
    const body = { jsonrpc: "2.0", method, params };
    if (!notification) body.id = ++sequence;
    const headers = {
      "content-type": "application/json",
      accept: "application/json, text/event-stream",
      "mcp-protocol-version": protocolVersion,
    };
    if (sessionId) headers["mcp-session-id"] = sessionId;
    const response = await fetchRequest(url, {
      method: "POST", headers, body: JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (!response.ok) throw new Error(`gateway HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
    const returnedSession = response.headers.get("mcp-session-id");
    if (returnedSession) sessionId = returnedSession;
    if (notification || response.status === 202) return null;

    const text = await response.text();
    let message = null;
    if ((response.headers.get("content-type") || "").includes("text/event-stream")) {
      for (const line of text.split("\n")) {
        if (!line.startsWith("data:")) continue;
        try {
          const candidate = JSON.parse(line.slice(5).trim());
          if (candidate?.id === body.id) message = candidate;
        } catch { /* SSE keepalives need not contain JSON. */ }
      }
    } else {
      message = JSON.parse(text);
    }
    if (!message || message.id !== body.id) throw new Error(`no JSON-RPC response for ${method}`);
    if (message.error) throw new Error(message.error.message || `rpc error on ${method}`);
    return message.result;
  }

  function initialize() {
    if (!initialization) {
      initialization = (async () => {
        const result = await rpc("initialize", { protocolVersion, capabilities: {}, clientInfo });
        if (!result || typeof result !== "object") throw new Error("invalid initialize result");
        if (result.protocolVersion) protocolVersion = result.protocolVersion;
        await rpc("notifications/initialized", {});
      })().catch((cause) => {
        initialization = null;
        sessionId = null;
        protocolVersion = initialProtocolVersion;
        throw Object.assign(new Error(cause.message, { cause }), { code: "MCP_INITIALIZATION_FAILED" });
      });
    }
    return initialization;
  }

  return {
    async callTool(name, args) {
      await initialize();
      const result = await rpc("tools/call", { name, arguments: args });
      if (!result || typeof result !== "object") throw new Error(`invalid tool result for ${name}`);
      const text = (result.content || []).find((content) => content.type === "text")?.text ?? "";
      if (result.isError) throw new Error(`${name}: ${text.slice(0, 200) || "tool error"}`);
      try { return JSON.parse(text); } catch { return text; }
    },
  };
}
