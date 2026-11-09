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

import { pathToFileURL } from "node:url";

export async function gatherResearch({ baseUrl, publicUrl, timeoutMs, staleIngestHours, fetch: fetchRequest, now }) {
const BASE = baseUrl;
const PUBLIC_URL = publicUrl;
const TIMEOUT_MS = timeoutMs;
const TOP_N = 3;
const STALE_INGEST_HOURS = staleIngestHours;

async function callTool(tool, body = {}) {
  const res = await fetchRequest(`${BASE}/api/${tool}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`${tool}: http ${res.status}`);
  return res.json();
}

function card(item, profileId) {
  return {
    title: String(item.title || "untitled").trim().slice(0, 140),
    url: item.url || null,
    tier: item.tierLabel || item.classification || null,
    category: item.primaryCategory || null,
    profile: profileId,
  };
}

  let profiles = [];
  try {
    const listed = await callTool("research_profiles_list");
    profiles = (listed.profiles || []).filter((p) => p.enabled);
  } catch {
    // Server down or not yet migrated — report unavailable rather than {} so
    // the section can say so instead of silently vanishing.
    return { url: PUBLIC_URL, available: false, counts: { awaiting: 0 } };
  }

  async function gatherQueue() {
    let awaiting = 0;
    const top = [];
    // Four profile requests per batch; extra profiles wait for the batch to finish.
    const profileBatchSize = 4;
    for (let i = 0; i < profiles.length; i += profileBatchSize) {
      const queues = await Promise.all(profiles.slice(i, i + profileBatchSize).map(async (p) => {
        try {
          const q = await callTool("research_review_queue", { profileId: p.id, limit: TOP_N });
          return { total: Number(q.total || 0), cards: (q.items || []).map((item) => card(item, p.id)) };
        } catch {
          return { total: 0, cards: [] }; // One failing profile must not lose the others.
        }
      }));
      for (const q of queues) { awaiting += q.total; top.push(...q.cards); }
    }

    // Highest-tier first is already the queue's own order; keep it and cap.
    const queue = top.slice(0, TOP_N);
    return { awaiting, queue };
  }

  async function gatherLessons() {
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
    return lessons;
  }

  // Ingest AGE, never item count. 2026-08-26 premortem: zero new items is a
  // normal arXiv weekend (2026-08-19, 08-22 and 08-23 each recorded 12
  // completed classify runs with items_selected = 0), so a count cannot tell
  // "broke" from "quiet". A completed ingest run lands every day regardless of
  // how many papers it found, so its age is the unambiguous signal.
  async function gatherHealth() {
    let health = null;
    try {
      const stats = await callTool("research_stats");
      const runs = stats?._structured?.recentIngestRuns ?? stats?.recentIngestRuns ?? [];
      const done = runs
        .filter((r) => r.status === "completed" && r.completed_at)
        .map((r) => Date.parse(r.completed_at))
        .filter((t) => Number.isFinite(t));
      if (done.length > 0) {
        const last = Math.max(...done);
        const ageHours = (now - last) / 3_600_000;
        health = {
          lastIngestAt: new Date(last).toISOString(),
          ingestAgeHours: Math.round(ageHours * 10) / 10,
          // Daily timer + 30min RandomizedDelaySec; 36h clears one late run
          // without waiting a whole second day to complain.
          staleIngest: ageHours > STALE_INGEST_HOURS,
        };
      } else {
        health = { lastIngestAt: null, ingestAgeHours: null, staleIngest: true };
      }
    } catch {
      // research_stats failing must not lose the queue section.
    }
    return health;
  }

  // Fixed three-group fan-out (at most six HTTP requests with the profile batch).
  const [{ awaiting, queue }, lessons, health] = await Promise.all([
    gatherQueue(), gatherLessons(), gatherHealth(),
  ]);

  return {
      url: PUBLIC_URL,
      available: true,
      counts: { awaiting, profiles: profiles.length, showing: queue.length },
      queue,
      lessons,
      health,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  gatherResearch({ baseUrl: process.env.RESEARCH_SCOUT_URL || "http://127.0.0.1:8422",
    publicUrl: process.env.RESEARCH_SCOUT_PUBLIC_URL || "https://research-scout.hwc.iheartwoodcraft.com",
    timeoutMs: Number(process.env.RESEARCH_SCOUT_TIMEOUT_MS || 8000),
    staleIngestHours: Number(process.env.RESEARCH_SCOUT_STALE_HOURS || 36), fetch, now: Date.now(),
  }).then((out) => process.stdout.write(JSON.stringify(out)))
    .catch(() => process.stdout.write("{}"));
}
