// Parity gate for the sr→generic gauntlet-page refactor: the SR view rendered
// through GauntletPage(shim) must be BYTE-IDENTICAL to the pre-refactor
// renderSr/renderSrDetail output (test/golden/*, generated from the last
// bespoke build), except for the one intended chrome change — the DX1 nav tab.
// Plus the DX1 shim's own behavior over the same component.

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { renderSr, renderSrDetail, renderGauntletBoard, renderGauntletDetail } from "../src/shells/render.js";
import { gauntletViewByKey } from "../src/sources/gauntlet-views.js";
import { gauntletInvestigationProjects } from "../src/sources/gauntlet-investigations.js";
import { Item } from "../src/contracts.js";

const golden = (name: string) =>
  readFileSync(fileURLToPath(new URL(`../../test/golden/${name}`, import.meta.url)), "utf8");

// The single intended nav change: the DX1 tab (inactive on SR pages).
const DX1_TAB = '<a href="/dx1" class="">DX1</a>';
const stripDx1Tab = (html: string) => {
  assert.ok(html.includes(DX1_TAB), "DX1 nav tab present");
  return html.replace(DX1_TAB, "");
};

const SR_ITEMS: Item[] = [
  { id: "sr:2026-08-10-abc123", pipeline: "datax-sr", step: "investigated", state: "passed",
    payload: { title: "Agent keeps failing on receipts", srId: "abc123", srStatus: "new", srPhase: "engaged",
      customer: "Jane Builder", email: "jane@example.com", run: "investigations/2026-08-10-abc123/", hasReport: true,
      readonly: true, source: "sr_gauntlet investigation" }, history: [] },
  { id: "sr:2026-08-09-def456", pipeline: "datax-sr", step: "investigated", state: "passed",
    payload: { title: "Cannot connect Dropbox", srId: "def456", srStatus: "", srPhase: "",
      customer: "", email: "", run: "investigations/2026-08-09-def456/", hasReport: false,
      readonly: true, source: "sr_gauntlet investigation" }, history: [] },
];

test("parity — SR board via the generic component is byte-identical (modulo the DX1 nav tab)", () => {
  assert.equal(stripDx1Tab(renderSr(SR_ITEMS, 5, [], undefined)), golden("golden-sr-board.html"));
  assert.equal(stripDx1Tab(renderSr([], 5, [], undefined)), golden("golden-sr-board-empty.html"));
});

test("parity — SR detail via the generic component is byte-identical (modulo the DX1 nav tab)", () => {
  const full = renderSrDetail(SR_ITEMS[0]!, { gameplan: "# Report\n\nfix **this**", thread: "- msg", context: "ctx here" });
  assert.equal(stripDx1Tab(full), golden("golden-sr-detail-full.html"));
  const empty = renderSrDetail(SR_ITEMS[1]!, { gameplan: null, thread: null, context: null });
  assert.equal(stripDx1Tab(empty), golden("golden-sr-detail-empty.html"));
});

test("dx1 board: verdict lanes, empty state, cap form on /dx1", () => {
  const view = gauntletViewByKey("dx1")!;
  const cases: Item[] = [
    { id: "dx1:agent+o+a+D2_h1", pipeline: "dx1-case", step: "investigated", state: "passed",
      payload: { title: "Receipt Bot · D2", caseFingerprint: "agent:o:a:D2", stateHash: "h1",
        verdict: "diagnosed", family: "D2", triage: "platform", agentName: "Receipt Bot", orgName: "Acme",
        run: "investigations/agent+o+a+D2_h1/", hasReport: true, readonly: true,
        source: "dx1_gauntlet investigation" }, history: [] },
    { id: "dx1:agent+o+b+P5_h2", pipeline: "dx1-case", step: "investigated", state: "passed",
      payload: { title: "Daily Logger · P5", caseFingerprint: "agent:o:b:P5", stateHash: "h2",
        verdict: "", run: "investigations/agent+o+b+P5_h2/", hasReport: false, readonly: true,
        source: "dx1_gauntlet investigation" }, history: [] },
  ];
  const html = renderGauntletBoard(view, cases, 3, [], undefined);
  assert.ok(html.includes(">diagnosed <span"), "verdict lane");
  assert.ok(html.includes(">pending <span"), "missing verdict → pending lane");
  assert.ok(html.includes('action="/dx1/config"') && html.includes('value="3"'), "cap form");
  assert.ok(html.includes('href="/project/dx1:agent+o+a+D2_h1"'), "card → detail");

  const empty = renderGauntletBoard(view, [], 3, [], undefined);
  assert.ok(empty.includes("no case investigations yet"), "clean empty state");
});

test("dx1 mirror reads the LIVE runner's run-dir shape: case.json identity + ledger verdict join", () => {
  // Fixture mirrors ~/700_datax/dx1_gauntlet exactly (verified 2026-08-16):
  // run dir keeps the fingerprint's colons; verdict lives ONLY in the ledger.
  const root = mkdtempSync(join(tmpdir(), "dx1g-"));
  try {
    const fp = "agent:22PU:8Map:D2";
    const runName = `${fp}_dcf98635`;
    mkdirSync(join(root, "investigations", runName), { recursive: true });
    writeFileSync(
      join(root, "investigations", runName, "case.json"),
      JSON.stringify({ caseFingerprint: fp, stateHash: "dcf98635", agentId: "8Map", agentName: "Photo Processor",
        orgId: "22PU", orgName: "True Grit Roofing", family: "D2", triage: "platform", state: "resolved" }),
    );
    writeFileSync(join(root, "investigations", runName, "REPORT.md"), "# report");
    mkdirSync(join(root, "state"), { recursive: true });
    writeFileSync(
      join(root, "state", "ledger.json"),
      JSON.stringify({ [fp]: { caseFingerprint: fp, stateHash: "dcf98635", verdict: "diagnosed", investigatedAt: "2026-08-16", run: runName } }),
    );

    const items = gauntletInvestigationProjects(gauntletViewByKey("dx1")!, root);
    assert.equal(items.length, 1);
    const p = items[0]!.payload as Record<string, unknown>;
    assert.equal(items[0]!.id, `dx1:${runName}`);
    assert.equal(p.caseFingerprint, fp);
    assert.equal(p.title, "Photo Processor · D2");
    assert.equal(p.verdict, "diagnosed", "verdict joined from state/ledger.json by run name");
    assert.equal(p.hasReport, true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("dx1 detail: report default tab, evidence tab, case meta in Details, run-now by fingerprint", () => {
  const view = gauntletViewByKey("dx1")!;
  const item: Item = {
    id: "dx1:agent+o+a+D2_h1", pipeline: "dx1-case", step: "investigated", state: "passed",
    payload: { title: "Receipt Bot · D2", caseFingerprint: "agent:o:a:D2", stateHash: "h1",
      verdict: "diagnosed", family: "D2", triage: "platform", agentName: "Receipt Bot", orgName: "Acme",
      run: "investigations/agent+o+a+D2_h1/", hasReport: true, readonly: true }, history: [],
  };
  const html = renderGauntletDetail(view, item, { gameplan: "## Diagnosis", thread: "evidence pack", __context: "evidence pack" });
  assert.ok(html.includes('id="srt-gameplan" checked'), "report is the default tab");
  assert.ok(html.includes(">Report</label>") && html.includes(">Evidence</label>") && html.includes(">Details</label>"));
  assert.ok(html.includes("agent:o:a:D2"), "fingerprint shown");
  assert.ok(html.includes('action="/dx1/run-now"'), "run-now form");
  assert.ok(html.includes('name="caseId"') && html.includes('value="agent:o:a:D2"'), "fingerprint carried in the form");

  const noId: Item = { ...item, payload: { title: "x", readonly: true } };
  assert.ok(!renderGauntletDetail(view, noId, {}).includes('action="/dx1/run-now"'), "no fingerprint → no button");
});
