#!/usr/bin/env node
// domains/business/morning-briefing/gather-refinery.mjs
//
// Reads the Refinery engine's item store directly — one .md per Item, with the
// canonical Item JSON in a fenced ```json block (same format
// MarkdownItemStore.load parses) — and buckets the items for the briefing,
// TRIAGED LIKE MAIL:
//
//   action  — needs Eric: parked (a decision unblocks it), failed (a gate/run
//             broke), or a hopper idea matured to stage=ready (promote it).
//   active  — in-flight pipeline work (pending/running/passed on a real pipeline).
//   hopper  — raw untriaged ideas still captured/shaping (the idea backlog).
//
// This is a LOCAL FILE READ, not a service call — the board at :8060 exposes
// only HTML, but the .md store is the source of truth and is readable by eric.
// Emits {} on any failure so the briefing degrades gracefully (never throws).

import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const DIR = process.env.REFINERY_ITEMS_DIR || "/var/lib/refinery/items";
const BASE = process.env.REFINERY_URL || "https://refinery.hwc.iheartwoodcraft.com";
const UNTRIAGED = "untriaged";

// Same fenced-block extraction the engine's markdown-store uses.
function extractItem(md) {
  const m = md.match(/```json\n([\s\S]*?)\n```/);
  if (!m) return null;
  try {
    const it = JSON.parse(m[1]);
    return it && typeof it === "object" && it.id ? it : null;
  } catch {
    return null;
  }
}

function payload(it) {
  return it.payload && typeof it.payload === "object" ? it.payload : {};
}
function titleOf(it) {
  const p = payload(it);
  return String(p.title || p.input || it.id || "untitled").trim().slice(0, 140);
}
function domainOf(it) {
  const p = payload(it);
  const d = p.domain || (p.traits && p.traits.domain) || "";
  return d ? String(d) : null;
}

// A single human-meaningful status word so the renders don't have to
// reconstruct one from (state, pipeline, stage). A ready hopper idea reads
// "ready to promote", not the raw "pending".
function labelOf(it) {
  if (it.state === "failed") return "failed";
  if (it.state === "parked") return "parked";
  if (it.pipeline === UNTRIAGED) {
    if (it.stage === "ready") return "ready to promote";
    return it.stage || "idea";
  }
  return it.state || "?";
}

function card(it) {
  return {
    id: it.id,
    title: titleOf(it),
    pipeline: it.pipeline || null,
    step: it.step || null,
    stage: it.stage || null,
    state: it.state || null,
    label: labelOf(it),
    domain: domainOf(it),
    reason: it.parkedReason || null,
    url: `${BASE}/project/${encodeURIComponent(it.id)}`,
  };
}

async function main() {
  let items = [];
  let available = true;
  try {
    const files = await readdir(DIR);
    for (const f of files) {
      if (!f.endsWith(".md")) continue;
      const raw = await readFile(join(DIR, f), "utf8").catch(() => "");
      const it = extractItem(raw);
      if (it) items.push(it);
    }
  } catch {
    available = false; // dir missing (e.g. reading from the laptop) — degrade quietly
  }

  const action = [];
  const active = [];
  const hopper = [];
  for (const it of items) {
    const untriaged = it.pipeline === UNTRIAGED;
    if (it.state === "parked" || it.state === "failed") {
      action.push(card(it));
    } else if (untriaged && it.stage === "ready") {
      action.push(card(it)); // matured idea awaiting a promote decision
    } else if (untriaged) {
      hopper.push(card(it));
    } else if (it.state === "pending" || it.state === "running" || it.state === "passed") {
      active.push(card(it));
    }
  }

  // failed first, then parked, then ready-to-promote — most-actionable on top.
  const rank = (s) => (s === "failed" ? 0 : s === "parked" ? 1 : 2);
  action.sort((a, b) => rank(a.state) - rank(b.state));

  process.stdout.write(JSON.stringify({
    url: BASE,
    available,
    counts: {
      action: action.length,
      active: active.length,
      hopper: hopper.length,
      total: items.length,
    },
    buckets: { action, active, hopper },
  }));
}

main().catch(() => process.stdout.write("{}"));
