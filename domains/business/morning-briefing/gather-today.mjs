#!/usr/bin/env node
// domains/business/morning-briefing/gather-today.mjs
//
// Fetches the Today Queue from the gateway's hwc_today tool (which derives it
// from the just-written briefing.json + its dismiss state) and prints the
// section JSON for run.sh to inject as sections.today. Runs AFTER Step 2 so
// the queue sees mail triage. Emits {} on any failure — the briefing degrades
// gracefully (dashboard/email simply skip the TODAY block).
//

import { pathToFileURL } from "node:url";
import { createMcpClient } from "./dashboard/mcp-client.mjs";

export async function gatherToday({ gatewayUrl, fetch: fetchRequest }) {
  const client = createMcpClient({ url: gatewayUrl, fetch: fetchRequest, timeoutMs: 20_000,
    clientInfo: { name: "gather-today", version: "1.0.0" } });
  // Gather enough depth for the dashboard's explicit "show all" exploration
  // path; the initial render remains capped independently.
  const parsed = await client.callTool("hwc_today", { action: "board", limit: 50 });
  const data = parsed.data ?? {};

  // Case-ledger delta: what changed since the previous briefing run (each
  // parameterless delta call advances the cursor, so 3×/day this is exactly
  // run-over-run). Additive `changes` key — run.sh's jq templates and the
  // dashboard read only items/spillover, so this degrades to null harmlessly.
  // The shape guard also covers a not-yet-updated gateway, whose unknown
  // action would fall through to a board payload.
  let changes = null;
  try {
    const d = await client.callTool("hwc_today", { action: "delta" });
    const dData = d.data ?? {};
    if (Array.isArray(dData.new) && Array.isArray(dData.reopened)) changes = dData;
  } catch { /* board still ships without the delta */ }

  return {
    items: data.items ?? [],
    spillover: data.spillover ?? 0,
    generated_at: data.generated_at ?? null,
    changes,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  gatherToday({ gatewayUrl: process.env.HWC_GATEWAY_URL || "http://127.0.0.1:6200/mcp", fetch })
    .then((out) => process.stdout.write(JSON.stringify(out)))
    .catch(() => process.stdout.write("{}"));
}
