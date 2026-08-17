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
  assert.ok(html.includes("88.8%") && html.includes("11.2%"));
  // ONE Clean % column: the per-agent median moved into the tooltip.
  assert.ok(html.includes('per-agent median: 95.7%'), "median in tooltip");
  assert.ok(!/<th[^>]*>Clean %<br><span[^>]*>median/.test(html), "no median column header");
  assert.equal((html.match(/>Clean %/g) ?? []).length, 1, "single Clean %% header");
  assert.ok(html.includes("≤0.27M / ≤1.75M"), "token burn labeled as upper bound");
  assert.ok(html.includes("⑂ diverged forks (1)") && html.includes("92.8%"), "diverged divider row carries the aggregate");
  assert.ok(/border-color:#fbbf24[^>]*>P5×1/.test(html), "P5 family badge with catalog color");
  // Member rows are REAL table rows aligned under the cohort columns.
  const memRows = html.match(/<tr class="mem[^"]*" data-group="x9vAYFxKAroRjcnRlaMQ">[\s\S]*?<\/tr>/g) ?? [];
  assert.equal(memRows.length, 5, "3 assigned + divider + 1 diverged fork all render as rows");
  const ftd = memRows.find((r) => r.includes("FTD Homes"))!;
  const cells = [...ftd.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)].map((m) => m[1]!.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim());
  assert.equal(cells.length, 9, "member row spans all 9 columns");
  assert.deepEqual(cells.slice(1, 7), ["—", "7", "85.7%", "1+0", "0.7m", "0"], "numbers under their designated columns");
  assert.ok(cells[8] === "—", "no burn → em dash");
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
  // ONE caret per cohort (the caret pair was the disappearing-rows bug).
  assert.equal((html.match(/mtoggle" data-group="x9vAYFxKAroRjcnRlaMQ"/g) ?? []).length, 1, "single toggle per cohort");
  // Assigned members (actives, then quiet, then legacy), THEN the divider,
  // THEN the ⑂ forks.
  const order = ["FTD Homes", "Ogden Decks", "Receipts Legacy", "⑂ diverged forks", "RD Electric LLC"].map((s) => html.indexOf(s));
  for (let i = 1; i < order.length; i++) assert.ok(order[i - 1]! < order[i]!, `expansion order position ${i}`);
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

test("caseStatusLabel: runner status tokens in plain words", async () => {
  const { caseStatusLabel } = await import("../src/sources/dx1-fleet.js");
  assert.equal(caseStatusLabel({ fingerprint: "f", status: "queue" }), "queued for the next run");
  assert.equal(caseStatusLabel({ fingerprint: "f", status: "skip: peak=1 < 5" }), "below threshold (1 of 5 failures)");
  assert.equal(caseStatusLabel({ fingerprint: "f", status: "skip: state=resolved" }), "resolved");
  assert.equal(caseStatusLabel({ fingerprint: "f", status: "skip: state=resolved", investigated: true }), "resolved — already investigated");
  assert.equal(caseStatusLabel({ fingerprint: "f", status: "skip: hash unchanged" }), "already investigated — unchanged");
  assert.equal(caseStatusLabel({ fingerprint: "f", status: "skip: something else" }), "something else");
});

test("cases panel: queue/skip/investigated states, investigate button, run link", async () => {
  const { renderDx1CasesPanel } = await import("../src/shells/render.js");
  const cases = {
    generatedAt: "2026-08-17T11:00:00Z",
    cases: [
      { fingerprint: "agent:o1:a1:D2", agentId: "a1", agentName: "Photo Processor", orgId: "o1", orgName: "True Grit Roofing",
        family: "D2", triage: "platform", state: "resolved", peakWindowFailures: 4, lastSeen: "2026-08-14T13:00:00Z",
        status: "skip: state=resolved", investigated: true },
      { fingerprint: "agent:o2:a2:P5", agentId: "a2", agentName: "Stage Guard", orgId: "o2", orgName: "",
        family: "P5", triage: "prompt", state: "open", peakWindowFailures: 1, lastSeen: "2026-08-17T13:00:00Z",
        status: "skip: peak=1 < 5", investigated: false },
      { fingerprint: "agent:o3:a3:D1", agentId: "a3", agentName: "Queued Agent", orgId: "o3", orgName: "Acme",
        family: "D1", state: "open", peakWindowFailures: 6, status: "queue", investigated: false },
    ],
  };
  const runMap = new Map([["agent:o1:a1:D2", "dx1:agent:o1:a1:D2_hash1"]]);
  const html = renderDx1CasesPanel(cases, runMap, "2026-08-17T12:00:00Z");
  assert.ok(html.includes("Live cases") && html.includes("3 tracked") && html.includes("feed 1h old"));
  // Every case gets a force button wired to the run-now spool form.
  assert.equal((html.match(/action="\/dx1\/run-now"/g) ?? []).length, 3, "investigate button per case");
  assert.ok(html.includes('value="agent:o2:a2:P5"'), "fingerprint carried in the form");
  // Plain-words statuses.
  assert.ok(html.includes("below threshold (1 of 5 failures)") && html.includes("resolved — already investigated") && html.includes("queued for the next run"));
  // People-readable lead: org bold, agent linked to the dx1-health drill, org fallback.
  assert.ok(html.includes("<b>True Grit Roofing</b>") && html.includes("agent=a1") && html.includes("<b>JT o2</b>"));
  // Completed case links to its run detail.
  assert.ok(html.includes(`href="/project/${encodeURIComponent("dx1:agent:o1:a1:D2_hash1")}"`), "report link");
  // Queued + open cases sort above resolved ones.
  assert.ok(html.indexOf("Queued Agent") < html.indexOf("Stage Guard") && html.indexOf("Stage Guard") < html.indexOf("Photo Processor"));
  // Empty state guidance, never an error.
  assert.ok(renderDx1CasesPanel(null, new Map(), "2026-08-17T12:00:00Z").includes("no case feed yet"));
});
