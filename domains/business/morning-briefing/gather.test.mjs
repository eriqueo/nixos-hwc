import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

// Gather scripts execute on load. Run their actual bodies with I/O bound here;
// no real gateway, credentials, network requests or output files are involved.
// gather-live.mjs cannot hold these tests because its top level performs reads.
async function load(name, overrides) {
  const source = (await readFile(new URL(name, import.meta.url), "utf8"))
    .replace(/^#![^\n]*\n/, "")
    .replace(/^import .*;\n/gm, "")
    .replace('await import("node:fs/promises")', "injectedFs")
    .replace('main().catch(() => process.stdout.write("{}"));', "await main();");
  const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
  const execute = new AsyncFunction("fetch", "process", "readFile", "readdir", "join", "injectedFs", source);
  let output = "";
  return () => execute(overrides.fetch, {
    env: { HWC_JT_ORG_ID: "test", HWC_JT_GRANT_KEY_FILE: "test-key" },
    stdout: { write: (s) => { output += s; } },
    exit: () => { throw new Error("unexpected exit"); },
  }, overrides.readFile ?? (async () => "test-key"), overrides.readdir, join, { readFile: overrides.readFile ?? (async () => "test-key") })
    .then(() => JSON.parse(output));
}

const deferred = () => {
  let resolve;
  const promise = new Promise((r) => { resolve = r; });
  return { promise, resolve };
};
const turn = () => new Promise((resolve) => setImmediate(resolve));
const response = (data) => ({
  ok: true, status: 200, headers: new Headers(),
  json: async () => data, text: async () => JSON.stringify(data),
});

test("live reads overlap after handshake and preserve partial data and error order", async () => {
  const gate = deferred();
  const started = [];
  let initialized = false;
  const run = await load("gather-live.mjs", {
    fetch: async (url, options) => {
      const body = JSON.parse(options.body);
      if (body.method === "initialize") return response({ result: { protocolVersion: "2025-06-18" } });
      if (body.method === "notifications/initialized") { initialized = true; return response(null); }
      assert.equal(initialized, true);
      const section = url.includes("jobtread")
        ? (body.query.organization.jobs ? "jobs" : "overdue") : "tasks";
      started.push(section);
      await gate.promise;
      if (section !== "tasks") throw new Error(`${section} unavailable`);
      return response({ result: { content: [{ type: "text", text: JSON.stringify({ data: { tasks: [] } }) }] } });
    },
  });
  const pending = run();
  try {
    await turn();
    assert.deepEqual(started.sort(), ["jobs", "overdue", "tasks"]);
  } finally { gate.resolve(); }
  const out = await pending;
  assert.deepEqual(out.errors.map((e) => e.section), ["jobs", "overdue"]);
  assert.equal(out.sections.tasks.ok, true);
  assert.equal(out.sections.weekly_snapshot.active_job_count, null);
});

test("research overlaps independent reads, bounds profile requests, and preserves profile order", async () => {
  const gate = deferred();
  const started = [];
  const run = await load("gather-research.mjs", {
    fetch: async (url, options) => {
      const body = JSON.parse(options.body);
      const tool = url.split("/").at(-1);
      if (tool === "research_profiles_list") return response({ profiles: Array.from({ length: 6 }, (_, i) => ({ id: String(i), enabled: true })) });
      started.push(tool);
      await gate.promise;
      if (tool === "research_review_queue") {
        if (body.profileId === "1") throw new Error("one failed profile");
        return response({ total: 1, items: [{ title: `Profile ${body.profileId}` }] });
      }
      if (tool === "research_lessons_report") { assert.equal(body.generate, false); throw new Error("no snapshot"); }
      return response({ recentIngestRuns: [] });
    },
  });
  const pending = run();
  try {
    await turn();
    assert.equal(started.filter((s) => s === "research_review_queue").length, 4);
    assert.equal(started.includes("research_lessons_report"), true);
    assert.equal(started.includes("research_stats"), true);
  } finally { gate.resolve(); }
  const out = await pending;
  assert.deepEqual(out.counts, { awaiting: 5, profiles: 6, showing: 3 });
  assert.deepEqual(out.queue.map((q) => q.profile), ["0", "2", "3"]);
  assert.equal(out.lessons, null);
  assert.equal(out.health.staleIngest, true);
});

test("refinery batches file reads and keeps file order with unreadable items", async () => {
  const gate = deferred();
  let started = 0;
  const run = await load("gather-refinery.mjs", {
    readdir: async () => [...Array.from({ length: 20 }, (_, i) => `${i}.md`), "ignore.txt"],
    readFile: async (path) => {
      started++;
      await gate.promise;
      const id = path.split("/").at(-1).replace(".md", "");
      if (id === "1") throw new Error("unreadable");
      return '```json\n' + JSON.stringify({ id, pipeline: "untriaged", stage: "captured" }) + '\n```';
    },
  });
  const pending = run();
  try {
    await turn();
    assert.equal(started, 16);
  } finally { gate.resolve(); }
  const out = await pending;
  assert.equal(started, 20);
  assert.equal(out.available, true);
  assert.equal(out.counts.total, 19);
  assert.deepEqual(out.stages.hopper.slice(0, 3).map((c) => c.id), ["0", "2", "3"]);
});

test("projects reduces the hub portfolio to overdue, waits and the cap, and survives a failed page", async () => {
  const today = "2026-11-04";
  const folio = { today, liveCap: 8, counts: { live: 3, products: 9, parked: 1, stale: 0 },
    groups: [{ label: "DataX", count: 3, needYou: 2, stale: 0, avgComplete: 0.5 }],
    projects: {
      a: { id: "a", title: "A", status: "active", kind: "product", overdue: true, overdueDays: 4, reviewBy: "2026-10-31", open: 0, replans: 3, progress: { terminalReached: false }, waits: [] },
      b: { id: "b", title: "B", status: "active", kind: "product", overdue: false, open: 1, replans: 0, progress: { terminalReached: false },
           waits: [{ on: "eric", days: 12, expired: true, ask: "Measure" }, { on: "external", days: 30, ask: "vendor" }, { on: "eric", days: 2, ask: "fresh" }] },
      c: { id: "c", title: "C", status: "complete", kind: "task", overdue: true, overdueDays: 9, open: 0, waits: [] } } };
  const page = { cards: [{ id: "C1", title: "Old", status: "open", expires: "2026-11-05" }, { id: "C2", status: "open", expires: "2026-12-01" }] };
  const run = await load("gather-projects.mjs", { fetch: async (url) => response(url.endsWith("/api/portfolio") ? folio : page) });
  const out = await run();
  assert.equal(out.available, true);
  assert.deepEqual(out.overdue.map((o) => [o.id, o.days]), [["a", 4]]);
  assert.deepEqual(out.waits.map((w) => [w.id, w.days, w.expired]), [["b", 12, true]]);
  assert.deepEqual(out.expiring.map((c) => [c.card, c.daysLeft]), [["C1", 1]]);
  assert.deepEqual(out.churn.map((c) => c.id), ["a"]);
  assert.deepEqual(out.cap, { products: 9, limit: 8, over: true });
  assert.equal(out.actionable, true);
  // A project page that fails must not drop the section: expiring stays bounded to the pages read.
  const partial = await load("gather-projects.mjs", { fetch: async (url) => { if (url.endsWith("/api/portfolio")) return response(folio); throw new Error("page down"); } });
  const degraded = await partial();
  assert.deepEqual(degraded.expiring, []);
  assert.deepEqual(degraded.overdue.map((o) => o.id), ["a"]);
});
