import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { cohortCleanDelta, readFleetSnapshots, type FleetSnapshot } from "../src/sources/dx1-fleet.js";
import { renderDx1Fleet } from "../src/shells/render.js";

// Fixture mirrors the real 2026-08-17 snapshot's Landis Receipt Processor row
// (the live verification target: 27 agents / clean 88.8% / burn median 0.27M).
function snapshot(date: string, clean = 88.8): FleetSnapshot {
  return {
    date,
    generatedAt: `${date}T05:24:53.686Z`,
    windowDays: 30,
    method: {
      similarity: "token-set Sørensen–Dice over instructions vs libraryAgents",
      assignThreshold: 0.6,
      divergedFloor: 0.35,
      note: "outcome/health rates, not task quality; auto-resolved never counts as clean; quota errors excluded from excl-quota denominators",
      tokenBurn: "UPPER BOUND: subscription-cumulative monthlyTokens delta per task (≥2 checks, 336h logs); concurrent tasks bleed into the delta",
    },
    fleet: { productionAgents: 330, unassignedCount: 144, unassigned: [] },
    templates: [
      {
        rootId: "x9vAYFxKAroRjcnRlaMQ",
        name: "Receipt Processor",
        author: "Mike Landis",
        downloads: 22,
        cohortSize: 27,
        byteIdentical: 11,
        divergedForks: 5,
        members: [
          // Quiet first in snapshot order — the renderer must sort actives up.
          { id: "a3", name: "Receipt Processor", orgDocId: "orgC", ratio: 1, org: "Ogden Decks", stats: null },
          { id: "a1", name: "Bill Payable Entry", orgDocId: "orgA", ratio: 0.94, org: "FTD Homes",
            stats: { tasks: 7, cleanPct: 85.7, needsHelp: 1, errors: 0, stalls: 0, runtimeMedianMin: 0.7, burnMaxM: null } },
          // Legacy shape (pre-2026-08-17 snapshot): no org/stats keys at all.
          { id: "a4", name: "Receipts Legacy", orgDocId: "orgD", ratio: 0.88 },
        ],
        // Diverged forks are a SEPARATE list (verified against the live
        // snapshot — NOT a subset of members) and must render as full rows.
        divergedMembers: [
          { id: "a2", name: "Receipts B (fork)", orgDocId: "orgB", ratio: 0.41, org: "RD Electric LLC",
            stats: { tasks: 2, cleanPct: 50, needsHelp: 0, errors: 1, stalls: 1, runtimeMedianMin: 3.2, burnMaxM: 1.1 } },
        ],
        rates: {
          agents: 27, agentsWithTasks: 10, tasks: 116,
          cleanPooledPct: clean, cleanPooledExclQuotaPct: clean,
          needsHelpErrExclQuotaPct: 11.2, cleanMedianPct: 95.7,
          runtime: { n: 103, medianMin: 1.2, p90Min: 2.8, p99Min: 9.8, maxMin: 17.5, over10Min: 2 },
          stallEvents: 4, tasksWithStall: 4,
          engineFamilies7d: { P5: 1 },
          tokenBurnUpperBound336h: { tasksMeasured: 3, medianM: 0.27, p90M: 0.27, maxM: 1.75 },
        },
        divergedRates: {
          agents: 5, agentsWithTasks: 5, tasks: 98,
          cleanPooledExclQuotaPct: 92.8, needsHelpErrExclQuotaPct: 7.2, cleanMedianPct: 100,
          runtime: { n: 90, medianMin: 0.9, p90Min: 2.8, p99Min: 5.2, maxMin: 8.1, over10Min: 0 },
          stallEvents: 6, tasksWithStall: 6, engineFamilies7d: null,
          tokenBurnUpperBound336h: { tasksMeasured: 10, medianM: 1.64, p90M: 8.5, maxM: 10.68 },
        },
      },
      {
        rootId: "quiet", name: "Quiet Template", cohortSize: 2,
        rates: { agents: 2, agentsWithTasks: 0, tasks: 0, runtime: null, engineFamilies7d: null, tokenBurnUpperBound336h: null },
      },
    ],
  };
}

test("readFleetSnapshots: latest + previous by date, corrupt day skipped, missing dir empty", () => {
  const root = mkdtempSync(join(tmpdir(), "fleet-"));
  try {
    assert.deepEqual(readFleetSnapshots(root), { latest: null, previous: null });
    const dir = join(root, "state", "fleet-history");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "2026-08-15.json"), JSON.stringify(snapshot("2026-08-15", 80)));
    writeFileSync(join(dir, "2026-08-16.json"), "{ corrupt");
    writeFileSync(join(dir, "2026-08-17.json"), JSON.stringify(snapshot("2026-08-17")));
    writeFileSync(join(dir, "notes.txt"), "ignored");
    const { latest, previous } = readFleetSnapshots(root);
    assert.equal(latest?.date, "2026-08-17");
    assert.equal(previous?.date, "2026-08-15", "corrupt 08-16 skipped, older day still serves");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("cohortCleanDelta: latest vs previous by rootId; degrades to null", () => {
  const latest = snapshot("2026-08-17").templates[0]!;
  assert.equal(cohortCleanDelta(latest, snapshot("2026-08-16", 80.0))!.toFixed(1), "8.8");
  assert.equal(cohortCleanDelta(latest, null), null);
  const other = snapshot("2026-08-16");
  other.templates[0]!.rootId = "different";
  assert.equal(cohortCleanDelta(latest, { ...other, templates: [other.templates[1]!] }), null);
});

test("renderDx1Fleet: header totals, Landis row numbers, diverged sub-row, families, method honesty", () => {
  const html = renderDx1Fleet(snapshot("2026-08-17"), null, "2026-08-17T12:00:00Z");
  assert.ok(html.includes("330 production agents") && html.includes("2 cohorts") && html.includes("144 unassigned"));
  assert.ok(html.includes("snapshot 2026-08-17 (today)"));
  assert.ok(html.includes("no previous snapshot — no trend yet"), "single snapshot degrades cleanly");
  assert.ok(html.includes("Receipt Processor") && html.includes("Mike Landis"));
  assert.ok(html.includes("88.8%") && html.includes("95.7%") && html.includes("11.2%"));
  assert.ok(html.includes("≤0.27M / ≤1.75M"), "token burn labeled as upper bound");
  assert.ok(html.includes("↳ diverged forks") && html.includes("92.8%"), "diverged sub-row");
  assert.ok(/border-color:#fbbf24[^>]*>P5×1/.test(html), "P5 family badge with catalog color");
  // Member rows are REAL table rows aligned under the cohort columns.
  const memRows = html.match(/<tr class="mem[^"]*" data-group="x9vAYFxKAroRjcnRlaMQ">[\s\S]*?<\/tr>/g) ?? [];
  assert.equal(memRows.length, 4, "3 assigned + 1 diverged fork all render as rows");
  const ftd = memRows.find((r) => r.includes("FTD Homes"))!;
  const cells = [...ftd.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map((m) => m[1]!.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim());
  assert.equal(cells.length, 10, "member row spans all 10 columns");
  assert.deepEqual(cells.slice(1, 8), ["—", "7", "85.7%", "—", "1+0", "0.7m", "0"], "numbers under their designated columns");
  assert.ok(cells[9] === "—", "no burn → em dash");
  // Agent name links to the dx1-health executions drill.
  assert.ok(ftd.includes('href="https://datax.to/x/admin/dx1-health?tab=executions&agent=a1"') && ftd.includes('target="_blank"'));
  // id + ratio demoted to the second-line mono suffix.
  assert.ok(ftd.includes("a1 · ratio 0.94"));
  // Diverged fork: full row, ⑂ flag, own org + stats in the grid.
  const fork = memRows.find((r) => r.includes("RD Electric LLC"))!;
  assert.ok(fork.includes("⑂") && fork.includes("≤1.10M") && fork.includes("0+1"), "fork row flagged with aligned stats");
  // Quiet member: dim row, all numerics em-dash, state named.
  const quiet = memRows.find((r) => r.includes("Ogden Decks"))!;
  assert.ok(quiet.includes('class="mem quiet"') && quiet.includes("no runs in window"));
  assert.ok(!/data-group="x9vAYFxKAroRjcnRlaMQ"[^>]*>[\s\S]{0,400}orgA/.test(ftd), "raw orgDocId gone");
  // Legacy member renders name + suffix with em-dash numerics, no crash.
  const legacy = memRows.find((r) => r.includes("Receipts Legacy"))!;
  assert.ok(legacy.includes("a4 · ratio 0.88"));
  // Both toggles present: cohort row + diverged sub-row, same group.
  assert.equal((html.match(/mtoggle" data-group="x9vAYFxKAroRjcnRlaMQ"/g) ?? []).length, 2, "main + sub-row toggles");
  // Actives first by tasks desc (FTD 7 > fork 2), then quiet, then legacy.
  const order = ["FTD Homes", "RD Electric LLC", "Ogden Decks", "Receipts Legacy"].map((s) => html.indexOf(s));
  assert.ok(order[0]! < order[1]! && order[1]! < order[2]! && order[2]! < order[3]!, "actives first, tasks desc");
  assert.ok(html.includes("outcome/health rates, NOT task quality"), "method honesty rendered");
  assert.ok(html.includes("concurrent tasks bleed into the delta"), "token-burn caveat rendered");
  // Tasks-desc sort: Receipt Processor (116) before Quiet Template (0).
  assert.ok(html.indexOf("Receipt Processor") < html.indexOf("Quiet Template"));
});

test("renderDx1Fleet: trend arrow when a previous snapshot exists; empty state without any", () => {
  const withTrend = renderDx1Fleet(snapshot("2026-08-17"), snapshot("2026-08-16", 80.0), "2026-08-17T12:00:00Z");
  assert.ok(withTrend.includes("↑8.8"), "clean% delta arrow");
  assert.ok(withTrend.includes("trend vs 2026-08-16"));

  const empty = renderDx1Fleet(null, null, "2026-08-17T12:00:00Z");
  assert.ok(empty.includes("no fleet snapshots yet"));
});

test("ledgerAgentRuns: agentId keyed off the fingerprint's agent segment", async () => {
  const { ledgerAgentRuns } = await import("../src/sources/dx1-fleet.js");
  const runs = ledgerAgentRuns([
    { caseFingerprint: "agent:22PU:8MapVUD0NuEuuvolwkq8:D2", run: "agent:22PU:8MapVUD0NuEuuvolwkq8:D2_dcf9", verdict: "diagnosed" },
    { caseFingerprint: "platform:failure-rate", run: "x" }, // non-agent fingerprint ignored
  ]);
  assert.deepEqual(runs.get("8MapVUD0NuEuuvolwkq8"), { run: "agent:22PU:8MapVUD0NuEuuvolwkq8:D2_dcf9", verdict: "diagnosed" });
  assert.equal(runs.size, 1);
});

test("member investigation link renders only for agents with a ledger run", () => {
  const runs = new Map([["a1", { run: "agent:o:a1:D2_h1", verdict: "diagnosed" }]]);
  const html = renderDx1Fleet(snapshot("2026-08-17"), null, "2026-08-17T12:00:00Z", runs);
  const memRows = html.match(/<tr class="mem[^"]*"[\s\S]*?<\/tr>/g) ?? [];
  const ftd = memRows.find((r) => r.includes("FTD Homes"))!;
  assert.ok(ftd.includes(`href="/project/${encodeURIComponent("dx1:agent:o:a1:D2_h1")}"`), "investigation link to the run detail");
  assert.ok(ftd.includes("investigation →"));
  const quiet = memRows.find((r) => r.includes("Ogden Decks"))!;
  assert.ok(!quiet.includes("investigation →"), "no ledger run → no link");
});
