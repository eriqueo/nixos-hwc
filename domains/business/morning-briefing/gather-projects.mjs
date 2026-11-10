#!/usr/bin/env node
// domains/business/morning-briefing/gather-projects.mjs
//
// The project tracker, reduced to what Eric acts on. Two hub reads:
// /api/attention is the one ranked list of what waits on him (the hub sets each
// item's class and rank; this file only groups by them), and /api/portfolio
// gives the review dates, the live-product cap and the groups. Emits {} on any
// failure so the briefing degrades gracefully.
//
// TRACKER_URL      hub base (default http://127.0.0.1:8765)

import { pathToFileURL } from "node:url";

export async function gatherProjects({ baseUrl, publicUrl, fetch: fetchRequest, requestTimeoutMs, totalTimeoutMs }) {
  const BASE = baseUrl.replace(/\/$/, "");
  const PUBLIC = publicUrl.replace(/\/$/, "");
  // The shell allows 30 seconds; both reads share one total deadline.
  const budget = AbortSignal.timeout(totalTimeoutMs);
  async function readJson(path) {
    const signal = AbortSignal.any([budget, AbortSignal.timeout(requestTimeoutMs)]);
    const response = await fetchRequest(`${BASE}${path}`, { signal });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  }
  const folio = await readJson("/api/portfolio");
  const P = folio.projects || {};
  const live = Object.values(P).filter((p) => p.status === "active");
  const url = (id, tab = "") => `${PUBLIC}/p/${encodeURIComponent(id)}${tab}`;

  const overdue = live.filter((p) => p.overdue)
    .sort((a, b) => b.overdueDays - a.overdueDays)
    .map((p) => ({ id: p.id, title: p.title, days: p.overdueDays, reviewBy: p.reviewBy, kind: p.kind, url: url(p.id, "/roadmap") }));

  // What waits on Eric. The hub owns the list, the class and the order. If the
  // read fails or passes the deadline, the portfolio above still makes a section.
  let list = null;
  try { list = (await readJson("/api/attention")).cards || []; } catch { /* reported as attention: false */ }
  const days = (date) => (date ? Math.round((new Date(date + "T12:00:00") - new Date(folio.today + "T12:00:00")) / 86400000) : null);
  const item = (c) => ({ key: c.key, id: c.project, title: c.projectTitle, card: c.kind === "wait" ? null : c.id, kind: c.kind, ask: c.title,
    rank: c.rank, where: c.where ?? null, days: c.days ?? null, expired: !!c.expired, daysLeft: days(c.due), url: `${PUBLIC}${c.url}` });
  const of = (name) => (list || []).filter((c) => c.class === name).map(item);
  const decide = of("decide"), unsorted = of("unsorted"), agent = of("agent");
  // Errands group by place so one trip clears every item at that place.
  const inPerson = Object.entries(Object.groupBy(of("in-person"), (errand) => errand.where || "no place given"))
    .map(([where, items]) => ({ where, items }));
  const errands = inPerson.reduce((n, place) => n + place.items.length, 0);

  // Re-plan drift: a product re-planned three or more times with nothing
  // finished since is the premortem's "gaming the clock" signal.
  const churn = live.filter((p) => p.kind === "product" && p.replans >= 3 && !p.progress.terminalReached)
    .map((p) => ({ id: p.id, title: p.title, replans: p.replans, url: url(p.id, "/roadmap") }));

  const c = folio.counts || {};
  return {
    url: PUBLIC,
    available: true,
    today: folio.today,
    cap: { products: c.products ?? 0, limit: folio.liveCap ?? 8, over: (c.products ?? 0) > (folio.liveCap ?? 8) },
    attention: list !== null,
    counts: { live: c.live ?? 0, overdue: overdue.length, decide: decide.length, inPerson: errands, unsorted: unsorted.length, agent: agent.length, parked: c.parked ?? 0, stale: c.stale ?? 0 },
    overdue, decide, inPerson, unsorted, agent, churn,
    groups: (folio.groups || []).map((g) => ({ label: g.label, count: g.count, needYou: g.needYou, stale: g.stale, avgComplete: g.avgComplete })),
    actionable: overdue.length + decide.length + errands + unsorted.length + (c.products > folio.liveCap ? 1 : 0) > 0,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  gatherProjects({ baseUrl: process.env.TRACKER_URL || "http://127.0.0.1:8765",
    publicUrl: process.env.TRACKER_PUBLIC_URL || "http://hwc-work:8765",
    fetch,
    requestTimeoutMs: 10_000, totalTimeoutMs: 25_000,
  }).then((out) => process.stdout.write(JSON.stringify(out)))
    .catch(() => process.stdout.write("{}"));
}
