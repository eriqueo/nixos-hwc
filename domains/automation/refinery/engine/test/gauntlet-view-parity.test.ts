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
import { buildGauntletExport, gauntletViewByKey } from "../src/sources/gauntlet-views.js";
import { gauntletInvestigationProjects } from "../src/sources/gauntlet-investigations.js";
import { Item } from "../src/contracts.js";

const golden = (name: string) =>
  readFileSync(fileURLToPath(new URL(`../../test/golden/${name}`, import.meta.url)), "utf8");

// Goldens carry the current chrome (DX1 nav tab + fleet CSS) as of the
// 2026-08-17 regeneration — each regeneration was diffed first (nav tab, then
// the .fleet style block; content never changed) — so every comparison is
// straight byte equality.

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

test("parity — SR board via the generic component is byte-identical to the goldens", () => {
  assert.equal(renderSr(SR_ITEMS, 5, [], undefined), golden("golden-sr-board.html"));
  assert.equal(renderSr([], 5, [], undefined), golden("golden-sr-board-empty.html"));
});

test("parity — SR detail is byte-identical to the goldens", () => {
  const full = renderSrDetail(SR_ITEMS[0]!, { gameplan: "# Report\n\nfix **this**", thread: "- msg", context: "ctx here" });
  assert.equal(full, golden("golden-sr-detail-full.html"));
  const empty = renderSrDetail(SR_ITEMS[1]!, { gameplan: null, thread: null, context: null });
  assert.equal(empty, golden("golden-sr-detail-empty.html"));
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
  const html = renderGauntletDetail(view, item, {
    tabs: {
      gameplan: [{ name: "REPORT.md", content: "## Diagnosis" }],
      thread: [
        { name: "context.md", content: "evidence pack" },
        { name: "FINDINGS.md", content: "## Established\n\ncited dossier" },
      ],
    },
    context: null,
    detail: [{ name: "verdict.json", content: '{"impact":"High"}' }],
  });
  assert.ok(html.includes('id="srt-gameplan" checked'), "report is the default tab");
  assert.ok(html.includes(">Report</label>") && html.includes(">Evidence</label>") && html.includes(">Details</label>"));
  assert.ok(html.includes("agent:o:a:D2"), "fingerprint shown");
  assert.ok(html.includes('action="/dx1/run-now"'), "run-now form");
  assert.ok(html.includes('name="caseId"') && html.includes('value="agent:o:a:D2"'), "fingerprint carried in the form");

  assert.ok(html.includes("FINDINGS.md"), "dossier section named in the Evidence tab");
  assert.ok(html.includes("cited dossier"), "dossier content rendered");
  assert.ok(html.includes("verdict.json"), "verdict.json fenced into Details");
  assert.ok(html.includes('href="/dx1/export/all?id='), "combined export link");

  const emptyBundle = { tabs: {}, context: null, detail: [] };
  const noId: Item = { ...item, payload: { title: "x", readonly: true } };
  assert.ok(!renderGauntletDetail(view, noId, emptyBundle).includes('action="/dx1/run-now"'), "no fingerprint → no button");
  // Pre-rework run (no FINDINGS.md): Evidence renders context.md alone, no error.
  const preRework = renderGauntletDetail(view, item, {
    tabs: { gameplan: [], thread: [{ name: "context.md", content: "pack only" }] },
    context: null,
    detail: [],
  });
  assert.ok(preRework.includes("pack only"));
});

test("buildGauntletExport: per-tab, details, and combined compositions", () => {
  const view = gauntletViewByKey("dx1")!;
  const item: Item = {
    id: "dx1:agent:o:a:D2_h1", pipeline: "dx1-case", step: "investigated", state: "passed",
    payload: { title: "Receipt Bot · D2", caseFingerprint: "agent:o:a:D2", stateHash: "h1",
      verdict: "diagnosed", family: "D2", triage: "platform", agentName: "Receipt Bot", orgName: "Acme",
      run: "investigations/agent:o:a:D2_h1/", hasReport: true, readonly: true }, history: [],
  };
  const bundle = {
    tabs: {
      gameplan: [{ name: "REPORT.md", content: "# Brief" }],
      thread: [
        { name: "context.md", content: "the pack" },
        { name: "FINDINGS.md", content: "## Established" },
      ],
    },
    context: null,
    detail: [{ name: "verdict.json", content: '{"impact":"High"}\n' }],
  };

  const report = buildGauntletExport(view, item, bundle, "gameplan")!;
  assert.equal(report.filename, "agent+o+a+D2_h1-gameplan.md");
  assert.equal(report.markdown, "# Brief"); // single-file tab: bare content

  const evidence = buildGauntletExport(view, item, bundle, "thread")!;
  assert.ok(evidence.markdown.startsWith("# context.md\n\nthe pack"));
  assert.ok(evidence.markdown.includes("# FINDINGS.md\n\n## Established"), "dossier sectioned after the pack");

  const details = buildGauntletExport(view, item, bundle, "details")!;
  assert.ok(details.markdown.includes("**Case:** `agent:o:a:D2`"));
  assert.ok(details.markdown.includes("## verdict.json") && details.markdown.includes('```json'));

  const all = buildGauntletExport(view, item, bundle, "all")!;
  assert.equal(all.filename, "agent+o+a+D2_h1-all.md");
  for (const chunk of ["# Report\n", "# Brief", "# Evidence\n", "# FINDINGS.md", "# Details\n", "## verdict.json"]) {
    assert.ok(all.markdown.includes(chunk), `combined export carries ${JSON.stringify(chunk)}`);
  }

  // Pre-rework run: FINDINGS.md absent → evidence exports context.md alone.
  const sparse = { ...bundle, tabs: { ...bundle.tabs, thread: [{ name: "context.md", content: "the pack" }] } };
  assert.equal(buildGauntletExport(view, item, sparse, "thread")!.markdown, "the pack");
  // Nothing at all → placeholder body, never a 404 from a rendered button.
  const empty = { tabs: {}, context: null, detail: [] };
  assert.ok(buildGauntletExport(view, item, empty, "thread")!.markdown.startsWith("_no evidence"));
  assert.equal(buildGauntletExport(view, item, bundle, "nope"), null);
});
