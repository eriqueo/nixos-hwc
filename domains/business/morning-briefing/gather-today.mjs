#!/usr/bin/env node
// domains/business/morning-briefing/gather-today.mjs
//
// Fetches the Today Queue from the gateway's hwc_today tool (which derives it
// from the just-written briefing.json + its dismiss state) and prints the
// section JSON for run.sh to inject as sections.today. Runs AFTER Step 2 so
// the queue sees mail triage. Emits {} on any failure — the briefing degrades
// gracefully (dashboard/email simply skip the TODAY block).
//
// Same StreamableHTTP JSON-RPC transport as gather-live.mjs; keep in lockstep.

const GATEWAY = process.env.HWC_GATEWAY_URL || "http://127.0.0.1:6200/mcp";
const FETCH_TIMEOUT_MS = 20_000;

const session = { id: null, protocolVersion: "2025-06-18", seq: 0 };

async function rpc(method, params) {
  const isNotification = method.startsWith("notifications/");
  const body = { jsonrpc: "2.0", method, params };
  if (!isNotification) body.id = ++session.seq;

  const headers = {
    "content-type": "application/json",
    accept: "application/json, text/event-stream",
  };
  if (session.id) headers["mcp-session-id"] = session.id;
  if (session.protocolVersion) headers["mcp-protocol-version"] = session.protocolVersion;

  const res = await fetch(GATEWAY, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  const sid = res.headers.get("mcp-session-id");
  if (sid) session.id = sid;
  if (isNotification || res.status === 202) return null;

  const text = await res.text();
  if (!res.ok) throw new Error(`gateway HTTP ${res.status}: ${text.slice(0, 200)}`);

  let msg = null;
  if ((res.headers.get("content-type") || "").includes("text/event-stream")) {
    for (const line of text.split("\n")) {
      if (!line.startsWith("data:")) continue;
      try {
        const j = JSON.parse(line.slice(5).trim());
        if (j && (j.id === body.id || j.result !== undefined || j.error)) msg = j;
      } catch { /* keepalives */ }
    }
  } else {
    msg = JSON.parse(text);
  }
  if (!msg) throw new Error(`no JSON-RPC response for ${method}`);
  if (msg.error) throw new Error(msg.error.message || `rpc error on ${method}`);
  return msg.result;
}

async function main() {
  await rpc("initialize", {
    protocolVersion: session.protocolVersion,
    capabilities: {},
    clientInfo: { name: "gather-today", version: "1.0.0" },
  });
  await rpc("notifications/initialized", {});
  // Gather enough depth for the dashboard's explicit "show all" exploration
  // path; the initial render remains capped independently.
  const r = await rpc("tools/call", { name: "hwc_today", arguments: { action: "board", limit: 50 } });
  const text = (r.content || []).find((c) => c.type === "text")?.text ?? "";
  if (r.isError) throw new Error(text.slice(0, 200) || "hwc_today error");
  const parsed = JSON.parse(text);
  const data = parsed.data ?? {};

  // Case-ledger delta: what changed since the previous briefing run (each
  // parameterless delta call advances the cursor, so 3×/day this is exactly
  // run-over-run). Additive `changes` key — run.sh's jq templates and the
  // dashboard read only items/spillover, so this degrades to null harmlessly.
  // The shape guard also covers a not-yet-updated gateway, whose unknown
  // action would fall through to a board payload.
  let changes = null;
  try {
    const d = await rpc("tools/call", { name: "hwc_today", arguments: { action: "delta" } });
    const dText = (d.content || []).find((c) => c.type === "text")?.text ?? "";
    if (!d.isError) {
      const dData = JSON.parse(dText).data ?? {};
      if (Array.isArray(dData.new) && Array.isArray(dData.reopened)) changes = dData;
    }
  } catch { /* board still ships without the delta */ }

  process.stdout.write(JSON.stringify({
    items: data.items ?? [],
    spillover: data.spillover ?? 0,
    generated_at: data.generated_at ?? null,
    changes,
  }));
}

main().catch(() => process.stdout.write("{}"));
