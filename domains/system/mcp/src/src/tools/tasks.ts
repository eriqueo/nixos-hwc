/**
 * hwc_tasks_* — task management over the self-hosted Radicale CalDAV backend
 * (the same tasks shown in todui on the laptop and Apple Reminders on the
 * phone via its CalDAV account).
 *
 * Changes are visible on the phone within seconds (it talks to the same
 * server); the laptop's todui/todoman pick them up on the next vdirsyncer
 * run (15-min timer, or `R` in todui).
 */

import { randomUUID } from "node:crypto";
import { hostname } from "node:os";
import { catchError, mcpError } from "../errors.js";
import { contract } from "../result.js";
import type { ToolDef, ToolResult } from "../types.js";
import {
  buildVtodo,
  createTaskList,
  deleteItem,
  editVtodo,
  fetchRawItem,
  listAllTodos,
  listTaskLists,
  listTodosIn,
  putItem,
  type Task,
} from "../executors/caldav.js";

const DEFAULT_LIST = "Reminders";

/* ── one-line dialect (mirrors todui's core/dialect.py) ───────────────── */

const PRI_RE = /^\(([A-Za-z])\)$/;
const DUE_RE = /^due:(.+)$/i;

function parseDialect(line: string): {
  summary: string;
  categories: string[];
  priority: number;
  due: string | null;
} {
  const words: string[] = [];
  const categories: string[] = [];
  let priority = 0;
  let due: string | null = null;

  for (const tok of line.split(/\s+/)) {
    const pri = tok.match(PRI_RE);
    if (pri) {
      priority = Math.min(pri[1].toUpperCase().charCodeAt(0) - 64, 9);
      continue;
    }
    const d = tok.match(DUE_RE);
    if (d) {
      const parsed = parseDue(d[1]);
      if (parsed) {
        due = parsed;
        continue;
      }
    }
    if (tok.length > 1 && (tok[0] === "+" || tok[0] === "@")) {
      categories.push(tok);
      continue;
    }
    if (tok) words.push(tok);
  }
  return { summary: words.join(" "), categories, priority, due };
}

function parseDue(raw: string): string | null {
  const v = raw.trim().toLowerCase();
  const day = 24 * 60 * 60 * 1000;
  if (v === "today") return new Date().toISOString().slice(0, 10);
  if (v === "tomorrow" || v === "tom")
    return new Date(Date.now() + day).toISOString().slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null;
}

/* ── helpers ──────────────────────────────────────────────────────── */

function taskRow(t: Task) {
  return {
    uid: t.uid,
    summary: t.summary,
    list: t.list,
    status: t.status,
    ...(t.priority ? { priority: t.priority } : {}),
    ...(t.due ? { due: t.due } : {}),
    ...(t.categories.length ? { categories: t.categories } : {}),
    ...(t.description ? { description: t.description } : {}),
    ...(t.recurring ? { recurring: true } : {}),
  };
}

function sortTasks(tasks: Task[]): Task[] {
  return tasks.sort((a, b) => {
    const pa = a.priority || 10;
    const pb = b.priority || 10;
    if (pa !== pb) return pa - pb;
    return (a.due || "9999").localeCompare(b.due || "9999");
  });
}

async function findTask(uid: string): Promise<Task | null> {
  const { tasks } = await listAllTodos();
  return tasks.find((t) => t.uid === uid) || null;
}

/* ── tools ────────────────────────────────────────────────────────── */

export function tasksTools(): ToolDef[] {
  return [
    {
      name: "hwc_tasks_list",
      description:
        "List Eric's tasks (self-hosted Radicale CalDAV — same tasks as todui " +
        "on the laptop and Apple Reminders on the phone). Categories follow " +
        "the todo.txt convention: +name = project (outcome), @name = context " +
        "(where/when doable). Default shows active tasks across all lists.",
      inputSchema: {
        type: "object",
        properties: {
          list: { type: "string", description: "Filter to one list (e.g. Reminders, Family)" },
          status: {
            type: "string",
            enum: ["active", "completed", "all"],
            default: "active",
            description: "active = NEEDS-ACTION/IN-PROCESS (default)",
          },
          category: { type: "string", description: "Filter by exact tag, e.g. '+hwc' or '@errand'" },
          grep: { type: "string", description: "Case-insensitive substring match on summary" },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const { tasks, lists } = await listAllTodos();
          const status = (args.status as string) || "active";
          const listFilter = args.list as string | undefined;
          const category = args.category as string | undefined;
          const grep = (args.grep as string | undefined)?.toLowerCase();

          let out = tasks;
          if (listFilter) out = out.filter((t) => t.list === listFilter);
          if (status === "active")
            out = out.filter((t) => t.status === "NEEDS-ACTION" || t.status === "IN-PROCESS");
          else if (status === "completed") out = out.filter((t) => t.status === "COMPLETED");
          if (category) out = out.filter((t) => t.categories.includes(category));
          if (grep) out = out.filter((t) => t.summary.toLowerCase().includes(grep));

          const rows = sortTasks(out).map(taskRow);
          const listNames = lists.map((l) => l.name);
          return {
            status: "ok",
            message: `${out.length} task(s) across ${lists.length} list(s)`,
            data: { tasks: rows, lists: listNames },
            // Universal Result Contract view (list): id=uid, label=summary; the
            // rest rides along as the entity data bag (renderer reads time||due).
            view: contract("list", "Tasks", {
              items: rows.map((r) => ({
                kind: "task",
                id: r.uid,
                label: r.summary,
                ...(r.due ? { due: r.due } : {}),
                list: r.list,
                status: r.status,
                ...(r.priority ? { priority: r.priority } : {}),
              })),
            }, { count: out.length, lists: listNames, source: "hwc_tasks_list" }),
          };
        } catch (err) {
          return catchError("NETWORK_ERROR", "Failed to list tasks", err,
            "Check the radicale service on hwc-server and /run/agenix/radicale-htpasswd readability");
        }
      },
    },

    {
      name: "hwc_tasks_add",
      description:
        "Add a task. The summary supports the inline todui dialect — " +
        "'Order hinges +hardware @shop (A) due:2026-06-20' sets project, " +
        "context, priority (A=highest..I) and due date — or pass explicit " +
        "fields. Appears in Apple Reminders within seconds.",
      inputSchema: {
        type: "object",
        properties: {
          summary: { type: "string", description: "Task text, optionally with +project @context (A) due:YYYY-MM-DD inline" },
          list: { type: "string", default: DEFAULT_LIST, description: `Target list (default: ${DEFAULT_LIST})` },
          categories: { type: "array", items: { type: "string" }, description: "Tags (keep +/@ sigils); merged with inline ones" },
          priority: { type: "number", description: "1 (highest) … 9; overrides inline (A)-(I)" },
          due: { type: "string", description: "YYYY-MM-DD, 'today' or 'tomorrow'; overrides inline due:" },
          description: { type: "string", description: "Longer notes body" },
        },
        required: ["summary"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const parsed = parseDialect(args.summary as string);
          if (!parsed.summary)
            return mcpError({ type: "VALIDATION_ERROR", message: "summary is empty after parsing" });

          const listName = (args.list as string) || DEFAULT_LIST;
          const lists = await listTaskLists();
          const list = lists.find((l) => l.name === listName);
          if (!list)
            return mcpError({
              type: "NOT_FOUND",
              message: `No task list named '${listName}'`,
              suggestion: `Existing lists: ${lists.map((l) => l.name).join(", ")}. Use hwc_tasks_lists action=create to add one.`,
            });

          const categories = [
            ...parsed.categories,
            ...(((args.categories as string[]) || []).filter((c) => !parsed.categories.includes(c))),
          ];
          const due = (args.due ? parseDue(args.due as string) : null) || parsed.due;
          const priority = (args.priority as number) ?? parsed.priority;

          const uid = `${randomUUID().replace(/-/g, "")}@${hostname()}`;
          const ics = buildVtodo({
            uid,
            summary: parsed.summary,
            categories,
            priority,
            due,
            description: (args.description as string) || "",
          });
          await putItem(`${list.href}${uid}.ics`, ics);

          return {
            status: "ok",
            message: `Added '${parsed.summary}' to ${listName} (phone sees it now; laptop todui on next sync)`,
            data: { uid, list: listName, summary: parsed.summary, categories, priority, due },
          };
        } catch (err) {
          return catchError("NETWORK_ERROR", "Failed to add task", err);
        }
      },
    },

    {
      name: "hwc_tasks_update",
      description:
        "Update a task by uid (get uids from hwc_tasks_list): edit fields, " +
        "complete, reopen, or delete. Edits are surgical — untouched fields " +
        "and foreign properties (recurrence, Apple metadata) are preserved. " +
        "Note: completing a recurring task here just marks it completed (no " +
        "next-instance spawning).",
      inputSchema: {
        type: "object",
        properties: {
          uid: { type: "string", description: "Task UID from hwc_tasks_list" },
          action: { type: "string", enum: ["edit", "complete", "reopen", "delete"] },
          summary: { type: "string", description: "(edit) new summary — plain text, no inline dialect" },
          categories: { type: "array", items: { type: "string" }, description: "(edit) replaces all tags; [] clears" },
          priority: { type: "number", description: "(edit) 1-9, 0 clears" },
          due: { type: "string", description: "(edit) YYYY-MM-DD / today / tomorrow; '' clears" },
          description: { type: "string", description: "(edit) replaces notes; '' clears" },
        },
        required: ["uid", "action"],
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const uid = args.uid as string;
          const action = args.action as string;
          const task = await findTask(uid);
          if (!task)
            return mcpError({
              type: "NOT_FOUND",
              message: `No task with uid ${uid}`,
              suggestion: "List tasks first with hwc_tasks_list (status=all to include completed)",
            });

          if (action === "delete") {
            await deleteItem(task.href);
            return { status: "ok", message: `Deleted '${task.summary}'` };
          }

          const props: Record<string, string | null> = {};
          if (action === "complete") {
            props.STATUS = ":COMPLETED";
            props["PERCENT-COMPLETE"] = ":100";
            props.COMPLETED = `:${new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "")}`;
          } else if (action === "reopen") {
            props.STATUS = ":NEEDS-ACTION";
            props["PERCENT-COMPLETE"] = null;
            props.COMPLETED = null;
          } else if (action === "edit") {
            if (args.summary !== undefined) props.SUMMARY = `:${icsEscape(args.summary as string)}`;
            if (args.categories !== undefined) {
              const cats = (args.categories as string[]).filter(Boolean);
              props.CATEGORIES = cats.length ? `:${cats.map(icsEscape).join(",")}` : null;
            }
            if (args.priority !== undefined)
              props.PRIORITY = (args.priority as number) > 0 ? `:${args.priority}` : null;
            if (args.due !== undefined) {
              const due = (args.due as string) === "" ? null : parseDue(args.due as string);
              if ((args.due as string) !== "" && !due)
                return mcpError({ type: "VALIDATION_ERROR", message: `Bad due date '${args.due}' (YYYY-MM-DD/today/tomorrow)` });
              props.DUE = due ? `;VALUE=DATE:${due.replace(/-/g, "")}` : null;
            }
            if (args.description !== undefined)
              props.DESCRIPTION = (args.description as string) ? `:${icsEscape(args.description as string)}` : null;
            if (Object.keys(props).length === 0)
              return mcpError({ type: "VALIDATION_ERROR", message: "edit needs at least one field" });
          } else {
            return mcpError({ type: "VALIDATION_ERROR", message: `Unknown action '${action}'` });
          }

          const raw = await fetchRawItem(task.href);
          await putItem(task.href, editVtodo(raw, props));
          return {
            status: "ok",
            message: `${action === "edit" ? "Edited" : action === "complete" ? "Completed" : "Reopened"} '${task.summary}'`,
            data: { uid },
          };
        } catch (err) {
          return catchError("NETWORK_ERROR", "Failed to update task", err);
        }
      },
    },

    {
      name: "hwc_tasks_lists",
      description:
        "List or create task lists. New lists appear in Apple Reminders " +
        "immediately; the laptop's todui sees them after its next vdirsyncer " +
        "discover (automatic on todui's N flow, or `vdirsyncer discover tasks_radicale`).",
      inputSchema: {
        type: "object",
        properties: {
          action: { type: "string", enum: ["list", "create"], default: "list" },
          name: { type: "string", description: "(create) display name for the new list" },
        },
      },
      handler: async (args): Promise<ToolResult> => {
        try {
          const action = (args.action as string) || "list";
          if (action === "create") {
            const name = (args.name as string)?.trim();
            if (!name) return mcpError({ type: "VALIDATION_ERROR", message: "create needs a name" });
            const existing = await listTaskLists();
            if (existing.some((l) => l.name === name))
              return mcpError({ type: "VALIDATION_ERROR", message: `List '${name}' already exists` });
            await createTaskList(name);
            return { status: "ok", message: `Created list '${name}'` };
          }
          const lists = await listTaskLists();
          const counts = await Promise.all(
            lists.map(async (l) => ({
              name: l.name,
              active: (await listTodosIn(l)).filter(
                (t) => t.status === "NEEDS-ACTION" || t.status === "IN-PROCESS",
              ).length,
            })),
          );
          return { status: "ok", message: `${lists.length} list(s)`, data: { lists: counts } };
        } catch (err) {
          return catchError("NETWORK_ERROR", "Failed task-list operation", err);
        }
      },
    },
  ];
}

function icsEscape(s: string): string {
  return s
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}
