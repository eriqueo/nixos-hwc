#!/usr/bin/env node
// domains/business/morning-briefing/gather-live.mjs
//
// Live business data for the morning briefing, fetched from the local HWC MCP
// gateway (StreamableHTTP, :6200/mcp). Runs headless as eric with NO Claude and
// NO tool-permission prompts — plain JSON-RPC over loopback HTTP, which is the
// path the README's "JobTread follow-up" prescribed.
//
// Emits ONE JSON object on stdout:
//   { sections: {jobs, leads, overdue, tasks, weekly_snapshot}, alerts: [...], errors: [...] }
// Every section is best-effort: a tool failure lands in `errors` (surfaced as a
// dashboard alert by run.sh) instead of killing the run. Exit code is 0 unless
// even the gateway handshake failed.

const GATEWAY = process.env.HWC_GATEWAY_URL || "http://127.0.0.1:6200/mcp";
const FETCH_TIMEOUT_MS = 30_000;
const JT_JOB_URL = (id) => `https://app.jobtread.com/jobs/${id}`;

// ── Minimal StreamableHTTP MCP client ────────────────────────────────────────
const session = { id: null, protocolVersion: "2025-06-18", seq: 0 };

async function rpc(method, params) {
  const isNotification = method.startsWith("notifications/");
  const body = { jsonrpc: "2.0", method, params };
  if (!isNotification) body.id = ++session.seq;

  const headers = {
    "content-type": "application/json",
    accept: "application/json, text/event-stream",
  };
  if (session.id) headers["mcp-session-id"] = session.id;
  if (session.protocolVersion) headers["mcp-protocol-version"] = session.protocolVersion;

  const res = await fetch(GATEWAY, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  const sid = res.headers.get("mcp-session-id");
  if (sid) session.id = sid;
  if (isNotification || res.status === 202) return null;

  const text = await res.text();
  if (!res.ok) throw new Error(`gateway HTTP ${res.status}: ${text.slice(0, 200)}`);

  let msg = null;
  if ((res.headers.get("content-type") || "").includes("text/event-stream")) {
    // Take the last data: line carrying a JSON-RPC response for our id.
    for (const line of text.split("\n")) {
      if (!line.startsWith("data:")) continue;
      try {
        const j = JSON.parse(line.slice(5).trim());
        if (j && (j.id === body.id || j.result !== undefined || j.error)) msg = j;
      } catch { /* ignore non-JSON keepalives */ }
    }
  } else {
    msg = JSON.parse(text);
  }
  if (!msg) throw new Error(`no JSON-RPC response for ${method}`);
  if (msg.error) throw new Error(msg.error.message || `rpc error on ${method}`);
  return msg.result;
}

async function callTool(name, args) {
  const r = await rpc("tools/call", { name, arguments: args });
  const text = (r.content || []).find((c) => c.type === "text")?.text ?? "";
  if (r.isError) throw new Error(`${name}: ${text.slice(0, 200) || "tool error"}`);
  try { return JSON.parse(text); } catch { return text; }
}

// ── Date helpers (local time — the box runs America/Denver) ──────────────────
const now = new Date();
const todayYmd = ymd(now);
function ymd(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
function daysAgo(iso) {
  return Math.floor((now - new Date(iso)) / 86_400_000);
}
function weekStart() {
  const d = new Date(now);
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); // Monday
  d.setHours(0, 0, 0, 0);
  return d;
}
function plusDays(n) {
  const d = new Date(now);
  d.setDate(d.getDate() + n);
  return ymd(d);
}

// ── Section gatherers ────────────────────────────────────────────────────────
const out = { sections: {}, alerts: [], errors: [] };
function fail(section, err) {
  out.errors.push({ section, message: String(err.message || err).slice(0, 200) });
}

// Last value wins: JT jobs can carry duplicate custom-field rows; the newest
// node is appended last.
function customField(job, name) {
  let v = null;
  for (const n of job.customFieldValues?.nodes ?? []) {
    if (n.customField?.name === name) v = n.value;
  }
  return v;
}

async function gatherJobs() {
  const raw = await callTool("jt_jobs", { action: "search", status: "open", format: "json", limit: 100 });
  if (!Array.isArray(raw)) throw new Error("jt_jobs returned non-array");
  const mapped = raw.map((j) => ({
    id: j.id,
    name: j.name || "(unnamed)",
    number: j.number || "",
    phase: customField(j, "Phase") || "",
    status: customField(j, "Status") || "",
    job_type: customField(j, "Job Type") || "",
    account: j.location?.account?.name || "",
    city: j.location?.city || "",
    description: j.description || null,
    created_at: j.createdAt || null,
    url: JT_JOB_URL(j.id),
    is_test: /test/i.test(j.name || ""),
  }));

  const lost = (j) => /closed\s*lost/i.test(j.status);
  const active = mapped.filter((j) => !j.is_test && !lost(j))
    .sort((a, b) => (a.phase || "9").localeCompare(b.phase || "9"));
  out.sections.jobs = { ok: true, active };

  const leads = mapped
    .filter((j) => /1\.\s*Contacted/i.test(j.phase) && /new\s*lead/i.test(j.status))
    .map((j) => ({
      name: j.account || j.name,
      job_name: j.name,
      job_number: j.number,
      job_type: j.job_type,
      created_at: j.created_at,
      days_old: j.created_at ? daysAgo(j.created_at) : 0,
      url: j.url,
    }))
    .sort((a, b) => b.days_old - a.days_old);
  out.sections.leads = { ok: true, new_count: leads.length, items: leads };

  const ws = weekStart();
  const leadsThisWeek = mapped.filter((j) => j.created_at && new Date(j.created_at) >= ws).length;
  out._snapshot = { active_job_count: active.length, leads_received_this_week: leadsThisWeek, week_start: ws.toISOString() };

  const stale = leads.filter((l) => l.days_old > 2);
  if (stale.length) {
    out.alerts.push({
      level: "warning",
      section: "leads",
      message: `${stale.length} lead(s) sitting in "1. Contacted" >2 days: ${stale.map((l) => `${l.name} (${l.days_old}d)`).join(", ")}`,
    });
  }
  // By Wednesday with zero new leads this week → flag it (CLAUDE.md alert rule)
  if (now.getDay() >= 3 && leadsThisWeek === 0) {
    out.alerts.push({ level: "warning", section: "leads", message: "0 leads received this week (as of Wednesday)" });
  }
}

async function gatherOverdue() {
  const raw = await callTool("jt_documents", { action: "list_overdue", format: "json" });
  const docs = raw?.documents ?? [];
  const items = docs.map((d) => ({
    name: d.name || d.type || "Document",
    description: d.description || null,
    amount: d.balance ?? d.price ?? 0,
    due_date: d.dueDate || null,
    days_past_due: d.dueDate ? daysAgo(d.dueDate) : null,
    job_name: d.job?.name || "",
    job_number: d.job?.number || "",
    account: d.account?.name || "",
    url: d.job?.id ? JT_JOB_URL(d.job.id) : null,
  }));
  const total = raw?.total_outstanding ?? items.reduce((s, i) => s + (i.amount || 0), 0);
  out.sections.overdue = { ok: true, count: items.length, total_amount: total, items };
  if (items.length) {
    out.alerts.push({
      level: "warning",
      section: "overdue",
      message: `${items.length} overdue invoice(s) — $${Math.round(total).toLocaleString("en-US")} outstanding (oldest: ${items[0].job_name || items[0].name})`,
    });
  }
  out._outstanding = { count: items.length, amount: total };
}

async function gatherTasks() {
  const raw = await callTool("hwc_tasks_list", { status: "active" });
  const items = raw?.data?.items ?? [];
  const week = plusDays(7);
  const task = (t) => ({ name: t.label, due_date: t.due || null, list: t.list || "", completed: false });
  const overdue = [], due_today = [], due_this_week = [], unscheduled = [];
  for (const t of items) {
    if (!t.due) { unscheduled.push(task(t)); continue; }
    if (t.due < todayYmd) overdue.push(task(t));
    else if (t.due === todayYmd) due_today.push(task(t));
    else if (t.due <= week) due_this_week.push(task(t));
  }
  const byDue = (a, b) => (a.due_date || "").localeCompare(b.due_date || "");
  overdue.sort(byDue); due_this_week.sort(byDue);
  out.sections.tasks = { ok: true, source: "caldav", due_today, due_this_week, overdue, unscheduled };
  if (overdue.length) {
    out.alerts.push({
      level: "warning",
      section: "tasks",
      message: `${overdue.length} overdue task(s): ${overdue.slice(0, 3).map((t) => t.name).join(" · ")}${overdue.length > 3 ? " …" : ""}`,
    });
  }
}

// ── Main ─────────────────────────────────────────────────────────────────────
try {
  await rpc("initialize", {
    protocolVersion: session.protocolVersion,
    capabilities: {},
    clientInfo: { name: "morning-briefing-gather", version: "1.0" },
  }).then((r) => { if (r?.protocolVersion) session.protocolVersion = r.protocolVersion; });
  await rpc("notifications/initialized", {});
} catch (err) {
  // No gateway → emit an explicit, dashboard-visible failure and bail.
  out.errors.push({ section: "gateway", message: `MCP gateway unreachable at ${GATEWAY}: ${String(err.message || err).slice(0, 150)}` });
  process.stdout.write(JSON.stringify(out));
  process.exit(0);
}

await gatherJobs().catch((e) => fail("jobs", e));
await gatherOverdue().catch((e) => fail("overdue", e));
await gatherTasks().catch((e) => fail("tasks", e));

out.sections.weekly_snapshot = {
  ok: true,
  week_start: out._snapshot?.week_start ?? weekStart().toISOString(),
  active_job_count: out._snapshot?.active_job_count ?? null,
  leads_received_this_week: out._snapshot?.leads_received_this_week ?? null,
  // jt_documents has no created-since filter and lists oldest-first, so a
  // cheap "estimates sent this week" isn't available — null renders as "—".
  estimates_sent_this_week: null,
  invoices_outstanding: out._outstanding?.count ?? null,
  invoices_outstanding_amount: out._outstanding?.amount ?? null,
};
delete out._snapshot;
delete out._outstanding;

process.stdout.write(JSON.stringify(out));
