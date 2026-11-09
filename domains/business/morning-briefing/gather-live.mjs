#!/usr/bin/env node
// domains/business/morning-briefing/gather-live.mjs
//
// Live business data for the morning briefing. Tasks come from the local HWC
// MCP gateway (StreamableHTTP, :6200/mcp); jobs, leads and overdue invoices
// come straight from JobTread's PAVE API with the jobtread-grant-key secret,
// because the gateway's jt_* tools were retired with jt-mcp on 2026-10-09.
// Runs headless as eric with NO Claude and NO tool-permission prompts.
//
// Emits ONE JSON object on stdout:
//   { sections: {jobs, leads, overdue, tasks, weekly_snapshot}, alerts: [...], errors: [...] }
// Every section is best-effort: a tool failure lands in `errors` (surfaced as a
// dashboard alert by run.sh) instead of killing the run, including when
// a particular source is unavailable.

import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { createMcpClient } from "./dashboard/mcp-client.mjs";

export async function gatherLive({ gatewayUrl, orgId, grantKeyFile, proposalsList, fetch: fetchRequest, readFile: readText, now }) {
const GATEWAY = gatewayUrl;
const FETCH_TIMEOUT_MS = 30_000;
const JT_JOB_URL = (id) => `https://app.jobtread.com/jobs/${id}`;
const PAVE_URL = "https://api.jobtread.com/pave";
const JT_ORG_ID = orgId;
const JT_GRANT_KEY_FILE = grantKeyFile;
const client = createMcpClient({ url: GATEWAY, fetch: fetchRequest, timeoutMs: FETCH_TIMEOUT_MS,
  clientInfo: { name: "morning-briefing-gather", version: "1.0" } });
const callTool = client.callTool;

// One organization-scoped list query. PAVE answers HTTP 413 for query
// complexity (size × nested fields), so callers keep size ≤ 50.
async function paveNodes(entityPlural, nodes, where) {
  if (!JT_ORG_ID || !JT_GRANT_KEY_FILE) throw new Error("JobTread not configured (HWC_JT_ORG_ID / HWC_JT_GRANT_KEY_FILE)");
  const grantKey = (await readText(JT_GRANT_KEY_FILE, "utf8")).trim();
  const body = {
    query: {
      $: { grantKey, notify: false },
      organization: { $: { id: JT_ORG_ID }, [entityPlural]: { $: { where, size: 50 }, nodes } },
    },
  };
  const res = await fetchRequest(PAVE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`PAVE ${entityPlural}: HTTP ${res.status} ${text.slice(0, 150)}`);
  const list = JSON.parse(text)?.organization?.[entityPlural]?.nodes;
  if (!Array.isArray(list)) throw new Error(`PAVE ${entityPlural}: no nodes in response`);
  return list;
}

const JOB_FIELDS = {
  id: {}, name: {}, number: {}, description: {}, createdAt: {},
  location: { city: {}, account: { name: {} } },
  customFieldValues: { nodes: { value: {}, customField: { name: {} } } },
};
const DOCUMENT_FIELDS = {
  id: {}, name: {}, type: {}, description: {}, price: {}, balance: {}, dueDate: {},
  job: { id: {}, name: {}, number: {} },
  account: { name: {} },
};

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

const out = { sections: {}, alerts: [], errors: [] };
function fail(out, section, err) {
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

async function gatherJobs(out) {
  // Pave rejects size>~50 with the nested JOB_FIELDS as HTTP 413 (query
  // complexity, not body bytes). 18 open jobs today; 50 keeps headroom.
  // Open = closedOn null (PAVE jobs have no status field).
  const raw = await paveNodes("jobs", JOB_FIELDS, { "=": [{ field: ["closedOn"] }, { value: null }] });
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
    // Test data marks itself in the job name, the account name ("Token Test
    // Client"), or a "TT-" job-name prefix.
    is_test: /test/i.test(`${j.name || ""} ${j.location?.account?.name || ""}`) || /^TT-/.test(j.name || ""),
  }));

  const lost = (j) => /closed\s*lost/i.test(j.status);
  const active = mapped.filter((j) => !j.is_test && !lost(j))
    .sort((a, b) => (a.phase || "9").localeCompare(b.phase || "9"));
  out.sections.jobs = { ok: true, active };

  const leads = mapped
    .filter((j) => !j.is_test && /1\.\s*Contacted/i.test(j.phase) && /new\s*lead/i.test(j.status))
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

  // Split by age so the alert stays actionable: a lead a few days old needs a
  // first touch TODAY; one sitting 5+ weeks is backlog hygiene — naming the
  // same four people every morning trains Eric to ignore the whole alert.
  const needsTouch = leads.filter((l) => l.days_old > 2 && l.days_old <= 14);
  const backlog = leads.filter((l) => l.days_old > 14);
  if (needsTouch.length) {
    out.alerts.push({
      level: "warning",
      section: "leads",
      message: `${needsTouch.length} lead(s) need a first touch (in "1. Contacted" >2 days): ${needsTouch.map((l) => `${l.name} (${l.days_old}d)`).join(", ")}`,
    });
  }
  if (backlog.length) {
    out.alerts.push({
      level: "warning",
      section: "leads",
      message: `${backlog.length} stale lead(s) >14d in "1. Contacted" (oldest ${backlog[0].days_old}d) — review for Closed Lost`,
    });
  }
  // The Wednesday threshold comes from the standing business briefing rule.
  if (now.getDay() >= 3 && leadsThisWeek === 0) {
    out.alerts.push({ level: "warning", section: "leads", message: "0 leads received this week (as of Wednesday)" });
  }
}

async function gatherOverdue(out) {
  // Same rule jt-mcp's list_overdue used: past due, money still owed, not a draft.
  const docs = await paveNodes("documents", DOCUMENT_FIELDS, {
    and: [
      { "<": [{ field: ["dueDate"] }, { value: todayYmd }] },
      { ">": [{ field: ["balance"] }, { value: 0 }] },
      { "!=": [{ field: ["status"] }, { value: "draft" }] },
    ],
  });
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
  const total = items.reduce((s, i) => s + (i.amount || 0), 0);
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

async function gatherTasks(out) {
  const raw = await callTool("hwc_tasks_list", { status: "active" });
  const items = raw?.data?.tasks ?? [];
  const week = plusDays(7);
  // uid rides along so hwc_today's `complete` verb can address the CalDAV item
  const task = (t) => ({ name: t.summary, uid: t.uid || null, due_date: t.due || null, list: t.list || "", completed: false });
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
  // Proposed tasks from the mail dates rule wait in one list for Eric to keep, move or delete.
  // The list name has one producer (the classifier contract) and reaches us through the unit's env.
  const proposals = items.filter((t) => (t.list || "") === proposalsList).map(task).sort(byDue);
  out.sections.mail_proposals = { ok: true, list: proposalsList, items: proposals };
  if (overdue.length) {
    out.alerts.push({
      level: "warning",
      section: "tasks",
      message: `${overdue.length} overdue task(s): ${overdue.slice(0, 3).map((t) => t.name).join(" · ")}${overdue.length > 3 ? " …" : ""}`,
    });
  }
}

// Fixed three-source fan-out. Merge in source order so alert/error order stays stable.
const gathered = await Promise.all([
  ["jobs", gatherJobs], ["overdue", gatherOverdue], ["tasks", gatherTasks],
].map(async ([section, gather]) => {
  const partial = { sections: {}, alerts: [], errors: [] };
  await gather(partial).catch((e) => fail(partial, e.code === "MCP_INITIALIZATION_FAILED" ? "gateway" : section, e));
  return partial;
}));
for (const partial of gathered) {
  Object.assign(out.sections, partial.sections);
  out.alerts.push(...partial.alerts);
  out.errors.push(...partial.errors);
  if (partial._snapshot) out._snapshot = partial._snapshot;
  if (partial._outstanding) out._outstanding = partial._outstanding;
}

out.sections.weekly_snapshot = {
  ok: true,
  week_start: out._snapshot?.week_start ?? weekStart().toISOString(),
  active_job_count: out._snapshot?.active_job_count ?? null,
  leads_received_this_week: out._snapshot?.leads_received_this_week ?? null,
  // The overdue query has no created-since filter and lists oldest-first, so a
  // cheap "estimates sent this week" isn't available — null renders as "—".
  estimates_sent_this_week: null,
  invoices_outstanding: out._outstanding?.count ?? null,
  invoices_outstanding_amount: out._outstanding?.amount ?? null,
};
delete out._snapshot;
delete out._outstanding;

return out;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const out = await gatherLive({
    gatewayUrl: process.env.HWC_GATEWAY_URL || "http://127.0.0.1:6200/mcp",
    orgId: process.env.HWC_JT_ORG_ID, grantKeyFile: process.env.HWC_JT_GRANT_KEY_FILE,
    proposalsList: process.env.HWC_MAIL_PROPOSALS_LIST || "Mail",
    fetch, readFile, now: new Date(),
  });
  process.stdout.write(JSON.stringify(out));
}
