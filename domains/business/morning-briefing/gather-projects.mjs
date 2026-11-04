#!/usr/bin/env node
// domains/business/morning-briefing/gather-projects.mjs
//
// The project tracker's portfolio (hub /api/portfolio on hwc-work), reduced to
// the four lines Eric acts on: projects past their review date, waits on him
// older than the threshold, cards about to expire, and the live-product count
// against the cap. The hub derives every number; this file only selects and
// orders. Emits {} on any failure so the briefing degrades gracefully.
//
// TRACKER_URL      hub base (default http://127.0.0.1:8765)
// WAIT_DAYS        a wait on Eric older than this is reported (default 7)

const BASE = (process.env.TRACKER_URL || "http://127.0.0.1:8765").replace(/\/$/, "");
const PUBLIC = (process.env.TRACKER_PUBLIC_URL || "http://hwc-work:8765").replace(/\/$/, "");
const WAIT_DAYS = Number(process.env.WAIT_DAYS || 7);

async function main() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10000);
  let folio;
  try {
    const r = await fetch(`${BASE}/api/portfolio`, { signal: controller.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    folio = await r.json();
  } finally {
    clearTimeout(timer);
  }
  const P = folio.projects || {};
  const live = Object.values(P).filter((p) => p.status === "active");
  const url = (id, tab = "") => `${PUBLIC}/p/${encodeURIComponent(id)}${tab}`;

  const overdue = live.filter((p) => p.overdue)
    .sort((a, b) => b.overdueDays - a.overdueDays)
    .map((p) => ({ id: p.id, title: p.title, days: p.overdueDays, reviewBy: p.reviewBy, kind: p.kind, url: url(p.id, "/roadmap") }));

  const waits = [];
  for (const p of live) {
    for (const w of p.waits || []) {
      if (w.on !== "eric" || w.days == null || w.days < WAIT_DAYS) continue;
      waits.push({ id: p.id, title: p.title, ask: w.ask, days: w.days, expired: !!w.expired, url: url(p.id, "/roadmap") });
    }
  }
  waits.sort((a, b) => b.days - a.days);

  // Cards: the hub exposes the open count and expiry per card on the project
  // page; the portfolio carries only counts, so "expiring soon" is read per
  // project with open cards. Bounded: one fetch per project with open cards.
  const expiring = [];
  const withCards = live.filter((p) => p.open > 0).slice(0, 20);
  for (const p of withCards) {
    try {
      const r = await fetch(`${BASE}/api/projects/${encodeURIComponent(p.id)}`);
      if (!r.ok) continue;
      const page = await r.json();
      for (const c of page.cards || []) {
        if (c.status !== "open" || !c.expires) continue;
        const left = Math.round((new Date(c.expires + "T12:00:00") - new Date(folio.today + "T12:00:00")) / 86400000);
        if (left <= 3) expiring.push({ id: p.id, title: p.title, card: c.id, cardTitle: c.title, daysLeft: left, url: url(p.id, `/decisions?card=${encodeURIComponent(c.id)}`) });
      }
    } catch { /* one project's page failing must not drop the section */ }
  }
  expiring.sort((a, b) => a.daysLeft - b.daysLeft);

  // Re-plan drift: a product re-planned three or more times with nothing
  // finished since is the premortem's "gaming the clock" signal.
  const churn = live.filter((p) => p.kind === "product" && p.replans >= 3 && !p.progress.terminalReached)
    .map((p) => ({ id: p.id, title: p.title, replans: p.replans, url: url(p.id, "/roadmap") }));

  const c = folio.counts || {};
  process.stdout.write(JSON.stringify({
    url: PUBLIC,
    available: true,
    today: folio.today,
    cap: { products: c.products ?? 0, limit: folio.liveCap ?? 8, over: (c.products ?? 0) > (folio.liveCap ?? 8) },
    counts: { live: c.live ?? 0, overdue: overdue.length, waits: waits.length, expiring: expiring.length, parked: c.parked ?? 0, stale: c.stale ?? 0 },
    overdue, waits, expiring, churn,
    groups: (folio.groups || []).map((g) => ({ label: g.label, count: g.count, needYou: g.needYou, stale: g.stale, avgComplete: g.avgComplete })),
    actionable: overdue.length + waits.length + expiring.length + (c.products > folio.liveCap ? 1 : 0) > 0,
  }));
}

main().catch(() => process.stdout.write("{}"));
