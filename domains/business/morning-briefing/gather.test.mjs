import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile, mkdtemp, cp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { spawn, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

import { gatherLive } from "./gather-live.mjs";
import { gatherToday } from "./gather-today.mjs";
import { gatherResearch } from "./gather-research.mjs";
import { gatherRefinery } from "./gather-refinery.mjs";
import { gatherProjects } from "./gather-projects.mjs";
import { createMcpClient } from "./dashboard/mcp-client.mjs";
import { createServer } from "node:http";
import { once } from "node:events";

function load(name, overrides) {
  const deps = { fetch: overrides.fetch, readFile: overrides.readFile ?? (async () => "test-key"),
    readdir: overrides.readdir, now: new Date("2026-11-04T12:00:00-07:00") };
  const gathers = {
    "gather-live.mjs": () => gatherLive({ ...deps, gatewayUrl: "http://gateway/mcp", orgId: "test", grantKeyFile: "test-key", proposalsList: "Mail" }),
    "gather-research.mjs": () => gatherResearch({ ...deps, baseUrl: "http://research", publicUrl: "http://research/public", timeoutMs: 8000, staleIngestHours: 36 }),
    "gather-refinery.mjs": () => gatherRefinery({ ...deps, itemsDir: "/items", publicUrl: "http://refinery" }),
    "gather-projects.mjs": () => gatherProjects({ ...deps, baseUrl: "http://tracker", publicUrl: "http://tracker/public", waitDays: 7, requestTimeoutMs: 10000, totalTimeoutMs: 25000 }),
  };
  return gathers[name];
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

test("live reads overlap independently and preserve partial data and error order", async () => {
  const gate = deferred();
  const started = [];
  let initialized = false;
  const run = await load("gather-live.mjs", {
    fetch: async (url, options) => {
      const body = JSON.parse(options.body);
      if (body.method === "initialize") return response({ id: body.id, result: { protocolVersion: "2025-06-18" } });
      if (body.method === "notifications/initialized") { initialized = true; return response(null); }
      const section = url.includes("jobtread")
        ? (body.query.organization.jobs ? "jobs" : "overdue") : "tasks";
      if (section === "tasks") assert.equal(initialized, true);
      started.push(section);
      await gate.promise;
      if (section !== "tasks") throw new Error(`${section} unavailable`);
      return response({ id: body.id, result: { content: [{ type: "text", text: JSON.stringify({ data: { tasks: [] } }) }] } });
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

async function withGateway(handler, run) {
  const server = createServer(async (request, response) => {
    let body = "";
    for await (const chunk of request) body += chunk;
    await handler(body ? JSON.parse(body) : null, request, response);
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try { return await run(`http://127.0.0.1:${server.address().port}`); }
  finally { server.closeAllConnections(); await new Promise((resolve) => server.close(resolve)); }
}
function reply(res, body, headers = {}) {
  res.writeHead(200, { "content-type": "application/json", ...headers });
  res.end(JSON.stringify(body));
}
const clientAt = (url, name = "fixture") => createMcpClient({ url, fetch, timeoutMs: 1000,
  clientInfo: { name, version: "1" } });

test("real HTTP clients share one initialization per instance and bind negotiated sessions", async () => {
  const calls = [];
  let serial = 0;
  await withGateway(async (body, req, res) => {
    calls.push(body);
    if (body.method === "initialize") {
      return reply(res, { id: body.id, result: { protocolVersion: "2025-03-26" } }, { "mcp-session-id": `session-${++serial}` });
    }
    assert.equal(req.headers["mcp-protocol-version"], "2025-03-26");
    assert.match(req.headers["mcp-session-id"], /^session-[12]$/);
    if (body.method === "notifications/initialized") { res.writeHead(202); res.end(); return; }
    reply(res, { id: body.id, result: { content: [{ type: "text", text: JSON.stringify({ session: req.headers["mcp-session-id"], args: body.params.arguments }) }] } });
  }, async (url) => {
    const first = clientAt(url, "first"), second = clientAt(url, "second");
    const result = await Promise.all([first.callTool("fixture", { n: 1 }), first.callTool("fixture", { n: 2 }), second.callTool("fixture", { n: 3 })]);
    assert.equal(calls.filter((c) => c.method === "initialize").length, 2);
    assert.equal(calls.filter((c) => c.method === "notifications/initialized").length, 2);
    assert.equal(result[0].session, result[1].session);
    assert.notEqual(result[0].session, result[2].session);
    assert.deepEqual(result.map((r) => r.args.n), [1, 2, 3]);
  });
});

test("SSE replies must match the request ID even when unrelated results follow", async () => {
  await withGateway(async (body, _req, res) => {
    if (body.method === "initialize") return reply(res, { id: body.id, result: {} });
    if (body.method === "notifications/initialized") { res.writeHead(202); res.end(); return; }
    res.writeHead(200, { "content-type": "text/event-stream" });
    const value = (id, text) => JSON.stringify({ id, result: { content: [{ type: "text", text }] } });
    res.end(`: keepalive\n\ndata: ${value(body.id, '{"matched":true}')}\n\ndata: ${value(body.id + 1, '{"matched":false}')}\n\n`);
  }, async (url) => assert.deepEqual(await clientAt(url).callTool("fixture", {}), { matched: true }));
});

test("wrong JSON response IDs fail and tool calls are never retried", async () => {
  let effects = 0;
  await withGateway(async (body, _req, res) => {
    if (body.method === "initialize") return reply(res, { id: body.id, result: {} });
    if (body.method === "notifications/initialized") { res.writeHead(202); res.end(); return; }
    effects++;
    reply(res, { id: body.id + 1, result: { content: [] } });
  }, async (url) => {
    await assert.rejects(clientAt(url).callTool("mutation", {}), /no JSON-RPC response/);
    assert.equal(effects, 1);
  });
});

test("failed initialized acknowledgement blocks actions; a later caller can recover", async () => {
  const calls = [];
  await withGateway(async (body, _req, res) => {
    calls.push(body.method);
    if (body.method === "initialize") return reply(res, { id: body.id, result: {} });
    res.writeHead(503); res.end("unavailable");
  }, async (url) => {
    const client = clientAt(url);
    await assert.rejects(client.callTool("mutation", {}), { code: "MCP_INITIALIZATION_FAILED" });
    assert.deepEqual(calls, ["initialize", "notifications/initialized"]);
  });
});

test("live JobTread data survives an unavailable MCP gateway", async () => {
  const out = await gatherLive({ gatewayUrl: "http://gateway", orgId: "org", grantKeyFile: "fixture",
    proposalsList: "Mail", now: new Date("2026-11-04T12:00:00-07:00"), readFile: async () => "key",
    fetch: async (url, options) => {
      if (!url.includes("jobtread")) throw new Error("gateway down");
      const body = JSON.parse(options.body);
      const kind = body.query.organization.jobs ? "jobs" : "documents";
      return response({ organization: { [kind]: { nodes: kind === "jobs" ? [{ id: "job", name: "Kitchen" }] : [] } } });
    },
  });
  assert.equal(out.sections.jobs.active[0].name, "Kitchen");
  assert.equal(out.sections.overdue.count, 0);
  assert.equal(out.sections.weekly_snapshot.active_job_count, 1);
  assert.deepEqual(out.errors.map((e) => e.section), ["gateway"]);
});

test("Today board survives a failed delta and uses the shared session", async () => {
  const actions = [];
  await withGateway(async (body, _req, res) => {
    if (body.method === "initialize") return reply(res, { id: body.id, result: {} });
    if (body.method === "notifications/initialized") { res.writeHead(202); res.end(); return; }
    actions.push(body.params.arguments);
    const board = body.params.arguments.action === "board";
    reply(res, { id: body.id, result: { isError: !board, content: [{ type: "text", text: board ? '{"data":{"items":[{"id":"x"}],"spillover":2}}' : "delta unavailable" }] } });
  }, async (url) => {
    const out = await gatherToday({ gatewayUrl: url, fetch });
    assert.deepEqual(out, { items: [{ id: "x" }], spillover: 2, generated_at: null, changes: null });
    assert.deepEqual(actions, [{ action: "board", limit: 50 }, { action: "delta" }]);
  });
});

test("project page deadlines retain the portfolio and stop at the total budget", { timeout: 5000 }, async () => {
  const projects = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [String(i), { id: String(i), status: "active", open: 1, waits: [] }]));
  // Real sockets keep Node alive while AbortSignal.timeout's unref'ed timer
  // fires, matching the fetch adapter rather than relying on other tests' I/O.
  await withGateway((_body, request, res) => {
    if (request.url === "/api/portfolio") reply(res, { projects: { 0: projects[0], 1: projects[1] }, today: "2026-11-04", counts: { live: 2 } });
    else if (request.url === "/api/projects/1") reply(res, { cards: [{ id: "next", title: "Next", status: "open", expires: "2026-11-05" }] });
    // The first project never responds; the next must remain reachable.
  }, async (url) => {
    const result = await gatherProjects({ baseUrl: url, publicUrl: "http://public", waitDays: 7,
      requestTimeoutMs: 100, totalTimeoutMs: 2000, fetch });
    assert.equal(result.counts.live, 2);
    assert.deepEqual(result.expiring.map((card) => card.card), ["next"]);
  });

  let requests = 0;
  await withGateway((_body, request, res) => {
    if (request.url === "/api/portfolio") reply(res, { projects, today: "2026-11-04", counts: { live: 20 } });
    else requests++;
  }, async (url) => {
    const result = await gatherProjects({ baseUrl: url, publicUrl: "http://public", waitDays: 7,
      requestTimeoutMs: 1000, totalTimeoutMs: 250, fetch });
    assert.equal(result.available, true);
    assert.equal(result.counts.live, 20);
    assert.deepEqual(result.expiring, []);
    assert.ok(requests > 0 && requests < 20, requests);
  });
});


test("a later caller can initialize after gateway recovery without replaying an action", async () => {
  let available = false, actions = 0;
  await withGateway(async (body, _req, res) => {
    if (!available) { res.writeHead(503); res.end("down"); return; }
    if (body.method === "initialize") return reply(res, { id: body.id, result: {} });
    if (body.method === "notifications/initialized") { res.writeHead(202); res.end(); return; }
    actions++;
    reply(res, { id: body.id, result: { content: [{ type: "text", text: '{"ok":true}' }] } });
  }, async (url) => {
    const client = clientAt(url);
    await assert.rejects(client.callTool("mutation", {}), { code: "MCP_INITIALIZATION_FAILED" });
    assert.equal(actions, 0);
    available = true;
    assert.deepEqual(await client.callTool("mutation", {}), { ok: true });
    assert.equal(actions, 1);
  });
});

test("actual shell entry skips a held kernel lock and releases it when the owner exits", { timeout: 10000 }, async () => {
  const root = await mkdtemp(join(tmpdir(), "briefing-lock-"));
  const script = join(root, "run.sh"), lock = join(root, "briefing.lock"), effect = join(root, "effect");
  await cp(new URL("run.sh", import.meta.url), script);
  const owner = spawn("bash", ["-c", 'source "$1"; acquire_briefing_lock "$2"; printf "ready\n"; read -r release', "fixture", script, lock], { stdio: ["pipe", "pipe", "pipe"], env: { ...process.env, FLOCK_BIN: "flock" } });
  let ownerClosed = false;
  const ownerExit = once(owner, "close").then((result) => { ownerClosed = true; return result; });
  try {
    assert.match((await once(owner.stdout, "data"))[0].toString(), /ready/);
    const attempt = () => spawnSync("bash", ["-c", 'source "$1"; host_exec() { printf reached > "$EFFECT"; kill -TERM "$$"; }; main', "fixture", script],
      { env: { ...process.env, BRIEFING_LOCK_FILE: lock, EFFECT: effect, FLOCK_BIN: "flock" }, encoding: "utf8", timeout: 3000 });
    const blocked = attempt();
    assert.equal(blocked.status, 0, blocked.stderr);
    assert.match(await readFile(join(root, "logs/run.log"), "utf8"), /SKIP: Previous run still active/);
    await assert.rejects(readFile(effect), { code: "ENOENT" });
    owner.stdin.end("release\n");
    assert.equal((await ownerExit)[0], 0);
    const unblocked = attempt();
    assert.equal(unblocked.signal, "SIGTERM");
    assert.equal(await readFile(effect, "utf8"), "reached");
  } finally {
    owner.stdin.end();
    if (!ownerClosed) { owner.kill("SIGTERM"); await ownerExit; }
    await rm(root, { recursive: true, force: true });
  }
});

test("real backup probe uses authoritative systemd result, status and timestamp for both owners", () => {
  const script = fileURLToPath(new URL("run.sh", import.meta.url));
  const result = spawnSync("bash", ["-c", `source "$1"
SYSTEMCTL=fixture
host_exec() {
  case "$3/$5" in
    borg.service/Result) echo success;;
    borg.service/ExecMainStatus) echo 0;;
    borg.service/ExecMainExitTimestamp) echo '2026-11-04 08:30:00 UTC';;
    postgres.service/Result) echo success;;
    postgres.service/ExecMainStatus) echo 2;;
  esac
}
backup_unit_status borg
backup_unit_status postgres
backup_unit_status absent`, "fixture", script], { encoding: "utf8", env: { ...process.env, TZ: "UTC" } });
  assert.equal(result.status, 0, result.stderr);
  const results = result.stdout.trim().split(/(?<=})\s*(?={)/).map(JSON.parse);
  assert.deepEqual(results, [
    { exit_status: "success", unit: "borg", service_result: "success", last_run: "2026-11-04T08:30:00+00:00" },
    { exit_status: "error", unit: "postgres", service_result: "success", last_run: null }, {},
  ]);
});

const emailFixture = () => ({
  generated_at: "2026-11-04T06:00:00-07:00",
  sections: {
    today: { items: Array.from({ length: 7 }, (_, i) => ({ id: String(i), source: "invoice", severity: "red", title: `Action ${i}`, why: "Pay <vendor>", url: "https://example.com/job", actions: [] })), spillover: 2 },
    config_drift: { dirty_files: 1 }, system: { services_active: 20, services_failed: 0, containers_running: 4, storage: [{ mount: "/", percent: 34 }] },
    backup: { exit_status: "success", postgres: { exit_status: "success" } },
    ops: { since: "2026-11-03 17:00", service_failures: [{ service: "fixture", time: "2026-11-04 01:00" }], services_down: [{ service: "flaky", down_now: false, downtime_pct_24h: 2 }],
      journal_errors_top: [{ unit: "fixture", errors: 6 }], prometheus_targets_down: [{ job: "fixture", instance: "example" }], disk_forecast: [{ mount: "/", days_to_full: 9 }], nightly_builds_finished: ["card.md"] },
    calendar: { events: [{ summary: 'Review <A> & "B"', date: "2026-11-04", start: "2026-11-04T09:00", location: "Office" }] },
    tasks: { due_today: [{ name: "Measure" }], overdue: [], due_this_week: [] },
    mail_proposals: { list: "Mail", items: [{ name: "Review invite" }] },
    leads: { items: [{ name: "Client", days_old: 4 }] }, overdue: { count: 1, total_amount: 42, items: [{ name: "Invoice", amount: 42 }] },
    jobs: { active: [{ number: "1", name: "Kitchen", phase: "Build", status: "Active" }] },
    mail: { summary: "2 inbox unread" }, refinery: { counts: { total: 1, action: 1 }, stages: { action: [{ id: "r", title: "Refine", state: "failed", reason: "fixture" }] } },
    agents: { line: "fixture agents" }, research: { counts: { awaiting: 1 }, queue: [{ title: "Paper", tier: "A" }], health: { staleIngest: true, ingestAgeHours: 40 }, lessons: { kept: 2, skipped: 1, themes: ["Joinery"] } },
    weekly_snapshot: { active_job_count: 1, leads_received_this_week: 1, invoices_outstanding: 1, invoices_outstanding_amount: 42 },
    weather: { current_temp_f: 32, high_f: 40, low_f: 20, conditions: "Clear" },
    website: { visitors_24h: 2, visitors_7d: 10, pageviews_7d: 14, top_pages_7d: [{ url: "/", views: 14 }] },
  },
  mail_triage: { states: ["do", "dont-know", "did", "look", "junk"], state_display_names: { "dont-know": "DONT KNOW" }, stats: { "dont-know_count": 1 }, threads_by_state: { do: [{ sender: "A", subject: "Reply", summary: "Review" }], look: [] }, routing_rules: [{ sender: "fixture", subject_contains: "review", state: "do", domain: "hwc" }] },
  alerts: [{ section: "overdue", level: "warning", message: "represented" }, { section: "ops", level: "critical", message: "Inspect <service>" }],
});

function email(format, snapshot) {
  const root = fileURLToPath(new URL(".", import.meta.url));
  const result = spawnSync("jq", ["-r", "--arg", "format", format, "--arg", "slot", "Morning", "--slurpfile", "policy", join(root, "dashboard/view-policy.json"), "-f", join(root, "email.jq")],
    { input: JSON.stringify(snapshot), encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}

test("actual email renderers share watchlist policy, cap priorities and escape HTML data", () => {
  const plain = email("plain", emailFixture()), html = email("html", emailFixture());
  assert.match(plain, /NEEDS YOU — top 5/);
  assert.match(plain, /Explore 4 more/);
  assert.doesNotMatch(plain, /Action 5/);
  assert.doesNotMatch(plain, /represented/);
  assert.match(plain, /Inspect <service>/);
  assert.match(html, /Inspect &lt;service&gt;/);
  assert.match(html, /Review &lt;A&gt; &amp; &quot;B&quot;/);
  assert.doesNotMatch(html, /Action 5|represented/);
  assert.match(plain, /DONT KNOW: 1/);
  assert.match(html, /DONT KNOW 1/);
  const snapshot = emailFixture();
  snapshot.sections.today.items = [{ source: "nightly", title: "Build", why: "Review" }];
  snapshot.alerts = [{ section: "nightly-builds", level: "warning", message: "already in Today" }, { section: "unknown", level: "warning", message: "unknown source retained" }];
  for (const format of ["plain", "html"]) {
    const rendered = email(format, snapshot);
    assert.doesNotMatch(rendered, /already in Today/);
    assert.match(rendered, /unknown source retained/);
  }
});

test("Today CLI binds its configured gateway and emits one JSON snapshot", async () => {
  await withGateway(async (body, _req, res) => {
    if (body.method === "initialize") return reply(res, { id: body.id, result: {} });
    if (body.method === "notifications/initialized") { res.writeHead(202); res.end(); return; }
    const data = body.params.arguments.action === "board" ? { items: [{ id: "cli" }], spillover: 1 } : { new: [], reopened: [] };
    reply(res, { id: body.id, result: { content: [{ type: "text", text: JSON.stringify({ data }) }] } });
  }, async (url) => {
    const child = spawn(process.execPath, [fileURLToPath(new URL("gather-today.mjs", import.meta.url))], { env: { ...process.env, HWC_GATEWAY_URL: url } });
    const exited = once(child, "close");
    let output = "", errors = "";
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { errors += chunk; });
    assert.equal((await exited)[0], 0, errors);
    assert.deepEqual(JSON.parse(output), { items: [{ id: "cli" }], spillover: 1, generated_at: null, changes: { new: [], reopened: [] } });
  });
});
