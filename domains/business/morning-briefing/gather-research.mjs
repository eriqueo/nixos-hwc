#!/usr/bin/env node
// domains/business/morning-briefing/gather-research.mjs
//
// research-scout's review lane, for the briefing: how many articles are
// waiting for Eric to read, the top few, and the standing themes report over
// the takeaways he has already written.
//
// LOOPBACK REST, NOT MCP. The 6am run is headless, and ~/.claude runs
// defaultMode=acceptEdits, which does not cover Bash or MCP — an MCP gather
// is auto-denied and shows up as a CRITICAL "permission denied" alert. So
// this talks to the unified research-scout server's REST dispatch on
// 127.0.0.1:8422 (POST /api/<tool>), the same handlers the MCP tools wrap.
// Same reasoning as gather-refinery.mjs reading the item store directly.
//
// NEVER GENERATES. The lessons report is read with generate:false, so the
// briefing costs zero LLM calls; generating one is a deliberate act from the
// dashboard or `review-report`.
//
// Emits {} on any failure so the briefing degrades gracefully — the section
// simply renders empty. It must never throw.

const BASE = process.env.RESEARCH_SCOUT_URL || "http://127.0.0.1:8422";
const PUBLIC_URL =
  process.env.RESEARCH_SCOUT_PUBLIC_URL ||
  "https://research-scout.hwc.iheartwoodcraft.com";
const TIMEOUT_MS = Number(process.env.RESEARCH_SCOUT_TIMEOUT_MS || 8000);
const TOP_N = 3;

async function callTool(tool, body = {}) {
  const res = await fetch(`${BASE}/api/${tool}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`${tool}: http ${res.status}`);
  return res.json();
}

/** Trim a title to one briefing line. */
function card(item, profileId) {
  return {
    title: String(item.title || "untitled").trim().slice(0, 140),
    url: item.url || null,
    tier: item.tierLabel || item.classification || null,
    category: item.primaryCategory || null,
    profile: profileId,
  };
}

async function main() {
  let profiles = [];
  try {
    const listed = await callTool("research_profiles_list");
    profiles = (listed.profiles || []).filter((p) => p.enabled);
  } catch {
    // Server down or not yet migrated — report unavailable rather than {} so
    // the section can say so instead of silently vanishing.
    process.stdout.write(
      JSON.stringify({ url: PUBLIC_URL, available: false, counts: { awaiting: 0 } })
    );
    return;
  }

  let awaiting = 0;
  const top = [];
  for (const p of profiles) {
    try {
      const q = await callTool("research_review_queue", { profileId: p.id, limit: TOP_N });
      awaiting += Number(q.total || 0);
      for (const item of q.items || []) top.push(card(item, p.id));
    } catch {
      // One profile failing must not lose the others.
    }
  }

  // Highest-tier first is already the queue's own order; keep it and cap.
  const queue = top.slice(0, TOP_N);

  let lessons = null;
  try {
    const snap = await callTool("research_lessons_report", { generate: false });
    if (snap && !snap.error && snap.data) {
      lessons = {
        status: snap.data.themes_status || null,
        reviewed: snap.data.reviewed_total ?? 0,
        kept: snap.data.kept ?? 0,
        skipped: snap.data.skipped ?? 0,
        generated_at: snap.data.generated_at || null,
        themes: (snap.data.themes || []).map((t) => String(t.name)).slice(0, 5),
      };
    }
  } catch {
    // No snapshot yet is the normal early state, not an error.
  }

  process.stdout.write(
    JSON.stringify({
      url: PUBLIC_URL,
      available: true,
      counts: { awaiting, profiles: profiles.length, showing: queue.length },
      queue,
      lessons,
    })
  );
}

main().catch(() => process.stdout.write("{}"));
