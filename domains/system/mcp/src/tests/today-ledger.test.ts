/**
 * today-ledger — pure state-machine tests + a wiring test that drives the
 * real hwc_today handler against a temp HWC_BRIEFING_DIR (Part IV A #6:
 * the decision points in today.ts must be pinned, not only the extraction).
 *
 * Lives in tests/ because tsconfig.json excludes it from the dist build the
 * gateway ships; vitest's default glob picks it up regardless.
 */

import { describe, it, expect } from "vitest";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  migrateState,
  reconcile,
  bumpSurfaced,
  snoozeCase,
  resolveCase,
  recordAction,
  computeDelta,
  EVENTS_CAP,
  REOPENED,
  RESOLVED,
  WORSENED,
  type LedgerState,
  type ObservedItem,
} from "../src/tools/today-ledger.js";

const DAY_MS = 86_400_000;
const T0 = new Date("2026-08-10T06:00:00.000Z");
const at = (days: number) => new Date(T0.getTime() + days * DAY_MS);

function empty(): LedgerState {
  return { schemaVersion: 2, cases: {} };
}

const item = (id: string, over: Partial<ObservedItem> = {}): ObservedItem => ({
  id,
  title: `title of ${id}`,
  severity: "amber",
  source: id.split(":")[0] ?? "system",
  ...over,
});

/* ── migrateState ─────────────────────────────────────────────────── */

describe("migrateState", () => {
  it("migrates v1 dismissed → snoozed with until = dismissal + 30d", () => {
    const dismissedAt = at(-10).toISOString();
    const s = migrateState({ dismissed: { "invoice:a": dismissedAt }, dispatched: {} }, T0);
    const c = s.cases["invoice:a"]!;
    expect(c.state).toBe("snoozed");
    expect(c.snooze?.until).toBe(new Date(at(-10).getTime() + 30 * DAY_MS).toISOString());
    expect(c.snooze?.reason).toMatch(/migrated/);
    expect(c.firstSeen).toBe(dismissedAt);
    expect(c.events).toHaveLength(1);
    expect(c.events[0]!.type).toBe("transition");
  });

  it("migrates v1 dispatched → open case with an action event; merges with dismissed", () => {
    const iso = at(-2).toISOString();
    const s = migrateState(
      { dismissed: { "system:x": iso }, dispatched: { "system:x": iso, "refinery:r": iso } },
      T0,
    );
    expect(s.cases["system:x"]!.state).toBe("snoozed");
    expect(s.cases["system:x"]!.events.map((e) => e.type)).toEqual(["transition", "action"]);
    expect(s.cases["refinery:r"]!.state).toBe("open");
    expect(s.cases["refinery:r"]!.events[0]!.type).toBe("action");
  });

  it("passes v2 through untouched (idempotent) and keeps lastDeltaAt", () => {
    const v2 = empty();
    v2.cases["a:b"] = {
      state: "open",
      firstSeen: T0.toISOString(),
      lastSeen: T0.toISOString(),
      timesSurfaced: 3,
      timesReopened: 0,
      events: [],
    };
    v2.lastDeltaAt = T0.toISOString();
    const out = migrateState(v2, at(1));
    expect(out).toEqual(v2);
  });

  it("returns an empty ledger for garbage", () => {
    for (const raw of [null, 42, "x", [], { dismissed: "not-a-map" }]) {
      const out = migrateState(raw, T0);
      expect(out.schemaVersion).toBe(2);
      expect(Object.keys(out.cases)).toHaveLength(0);
    }
  });
});

/* ── reconcile ────────────────────────────────────────────────────── */

describe("reconcile", () => {
  it("creates an open case with a creation observation for a new item", () => {
    const s = empty();
    const visible = reconcile(s, [item("lead:x")], T0, { sweepAbsent: true });
    const c = s.cases["lead:x"]!;
    expect(c.state).toBe("open");
    expect(c.firstSeen).toBe(T0.toISOString());
    expect(c.events[0]!.body).toMatch(/first seen/);
    expect(visible.has("lead:x")).toBe(true);
  });

  it("keeps a snoozed case hidden at unchanged severity, refreshing lastSeen", () => {
    const s = empty();
    reconcile(s, [item("system:g")], T0, { sweepAbsent: true });
    snoozeCase(s, "system:g", { severityAtSnooze: "amber" }, at(1));
    const visible = reconcile(s, [item("system:g")], at(2), { sweepAbsent: true });
    expect(s.cases["system:g"]!.state).toBe("snoozed");
    expect(s.cases["system:g"]!.lastSeen).toBe(at(2).toISOString());
    expect(visible.has("system:g")).toBe(false);
  });

  it("wakes a snoozed system case that resurfaces worse", () => {
    const s = empty();
    reconcile(s, [item("system:g")], T0, { sweepAbsent: true });
    snoozeCase(s, "system:g", { severityAtSnooze: "amber" }, at(1));
    const visible = reconcile(s, [item("system:g", { severity: "red" })], at(2), {
      sweepAbsent: true,
    });
    const c = s.cases["system:g"]!;
    expect(c.state).toBe("open");
    expect(c.timesReopened).toBe(1);
    expect(c.snooze).toBeUndefined();
    expect(c.events.at(-1)!.body).toMatch(new RegExp(`^${REOPENED}.*worse`));
    expect(visible.has("system:g")).toBe(true);
  });

  it("does NOT wake a snoozed non-system case on severity alone", () => {
    const s = empty();
    reconcile(s, [item("task:t")], T0, { sweepAbsent: true });
    snoozeCase(s, "task:t", { severityAtSnooze: "amber" }, at(1));
    reconcile(s, [item("task:t", { severity: "red" })], at(2), { sweepAbsent: true });
    expect(s.cases["task:t"]!.state).toBe("snoozed");
  });

  it("wakes on snooze expiry while the item is still emitted", () => {
    const s = empty();
    reconcile(s, [item("mail:m")], T0, { sweepAbsent: true });
    snoozeCase(s, "mail:m", {}, T0); // until = T0 + 30d
    reconcile(s, [item("mail:m")], at(31), { sweepAbsent: true });
    const c = s.cases["mail:m"]!;
    expect(c.state).toBe("open");
    expect(c.events.at(-1)!.body).toMatch(/expired/);
  });

  it("resolves an absent open case when the sweep is trusted, not otherwise", () => {
    const s = empty();
    reconcile(s, [item("invoice:i"), item("lead:l")], T0, { sweepAbsent: true });
    // degraded render: absence must not resolve
    reconcile(s, [item("lead:l")], at(1), { sweepAbsent: false });
    expect(s.cases["invoice:i"]!.state).toBe("open");
    // trusted render: absence resolves with a transition
    reconcile(s, [item("lead:l")], at(2), { sweepAbsent: true });
    const c = s.cases["invoice:i"]!;
    expect(c.state).toBe("resolved");
    expect(c.resolvedAt).toBe(at(2).toISOString());
    expect(c.events.at(-1)!.body).toMatch(new RegExp(`^${RESOLVED}`));
  });

  it("reopens a resolved case only when observed in a briefing NEWER than the resolution", () => {
    const s = empty();
    reconcile(s, [item("task:t")], T0, { sweepAbsent: true });
    resolveCase(s, "task:t", "completed via CalDAV", at(1));
    // same (stale) briefing still lists the item → stays resolved (complete clears immediately)
    reconcile(s, [item("task:t")], at(1), { observedAt: at(0), sweepAbsent: true });
    expect(s.cases["task:t"]!.state).toBe("resolved");
    // a briefing generated AFTER the resolution still lists it → the fix didn't take
    reconcile(s, [item("task:t")], at(2), { observedAt: at(2), sweepAbsent: true });
    const c = s.cases["task:t"]!;
    expect(c.state).toBe("open");
    expect(c.events.at(-1)!.body).toMatch(/resurfaced after resolution/);
  });

  it("records a worsened observation on an open case", () => {
    const s = empty();
    reconcile(s, [item("lead:x")], T0, { sweepAbsent: true });
    reconcile(s, [item("lead:x", { severity: "red" })], at(1), { sweepAbsent: true });
    expect(
      s.cases["lead:x"]!.events.some(
        (e) => e.type === "observation" && e.body.startsWith(WORSENED),
      ),
    ).toBe(true);
  });

  it("prunes resolved cases after retention and resolves long-stale snoozes", () => {
    const s = empty();
    reconcile(s, [item("a:1"), item("b:2")], T0, { sweepAbsent: true });
    snoozeCase(s, "b:2", {}, T0);
    reconcile(s, [], at(1), { sweepAbsent: true }); // sweep skipped: empty render
    reconcile(s, [item("c:3")], at(1), { sweepAbsent: true }); // a:1 resolved here
    expect(s.cases["a:1"]!.state).toBe("resolved");
    // 31 days on: resolved a:1 pruned; snoozed b:2 (unseen 31d) resolves
    reconcile(s, [item("c:3")], at(32), { sweepAbsent: true });
    expect(s.cases["a:1"]).toBeUndefined();
    expect(s.cases["b:2"]!.state).toBe("resolved");
  });

  it("caps events at EVENTS_CAP", () => {
    const s = empty();
    reconcile(s, [item("x:y")], T0, { sweepAbsent: true });
    for (let d = 1; d <= EVENTS_CAP + 10; d++) {
      recordAction(s, "x:y", `action ${d}`, at(d));
    }
    expect(s.cases["x:y"]!.events).toHaveLength(EVENTS_CAP);
    expect(s.cases["x:y"]!.events.at(-1)!.body).toBe(`action ${EVENTS_CAP + 10}`);
  });
});

/* ── bumpSurfaced ─────────────────────────────────────────────────── */

describe("bumpSurfaced", () => {
  it("always counts, but bounds observation events to one per case per day", () => {
    const s = empty();
    reconcile(s, [item("x:y")], T0, { sweepAbsent: true });
    const before = s.cases["x:y"]!.events.length; // creation observation
    bumpSurfaced(s, ["x:y"], new Date(T0.getTime() + 60_000)); // same day as creation obs
    bumpSurfaced(s, ["x:y"], new Date(T0.getTime() + 120_000));
    expect(s.cases["x:y"]!.timesSurfaced).toBe(2);
    expect(s.cases["x:y"]!.events).toHaveLength(before); // no new events today
    bumpSurfaced(s, ["x:y"], at(1)); // next day
    expect(s.cases["x:y"]!.timesSurfaced).toBe(3);
    expect(s.cases["x:y"]!.events).toHaveLength(before + 1);
    expect(s.cases["x:y"]!.events.at(-1)!.body).toMatch(/surfaced on board \(total 3\)/);
  });

  it("ignores unknown ids", () => {
    const s = empty();
    bumpSurfaced(s, ["nope:x"], T0);
    expect(s.cases["nope:x"]).toBeUndefined();
  });
});

/* ── verbs ────────────────────────────────────────────────────────── */

describe("snoozeCase / resolveCase / recordAction", () => {
  it("snooze records reason + wake condition and creates unknown cases (v1 parity)", () => {
    const s = empty();
    snoozeCase(s, "system:ghost", { reason: "known issue", severityAtSnooze: "amber" }, T0);
    const c = s.cases["system:ghost"]!;
    expect(c.state).toBe("snoozed");
    expect(c.snooze).toEqual({
      until: new Date(T0.getTime() + 30 * DAY_MS).toISOString(),
      reason: "known issue",
      severityAtSnooze: "amber",
    });
    expect(c.events.map((e) => e.type)).toEqual(["action", "transition"]);
    expect(c.events[0]!.body).toBe("dismissed: known issue");
  });

  it("re-snoozing a resolved case clears resolvedAt", () => {
    const s = empty();
    resolveCase(s, "a:b", "done", T0);
    snoozeCase(s, "a:b", {}, at(1));
    expect(s.cases["a:b"]!.resolvedAt).toBeUndefined();
    expect(s.cases["a:b"]!.state).toBe("snoozed");
  });

  it("resolveCase records action + transition and stamps resolvedAt", () => {
    const s = empty();
    reconcile(s, [item("task:t")], T0, { sweepAbsent: true });
    resolveCase(s, "task:t", "completed via CalDAV", at(1));
    const c = s.cases["task:t"]!;
    expect(c.state).toBe("resolved");
    expect(c.resolvedAt).toBe(at(1).toISOString());
    expect(c.events.at(-1)!.body).toMatch(new RegExp(`^${RESOLVED}`));
  });
});

/* ── computeDelta ─────────────────────────────────────────────────── */

describe("computeDelta", () => {
  it("classifies new / reopened / worsened / resolved since the cutoff", () => {
    const s = empty();
    // old case, snoozed, reopens worse inside the window
    reconcile(s, [item("system:g")], at(-10), { sweepAbsent: true });
    snoozeCase(s, "system:g", { severityAtSnooze: "amber" }, at(-9));
    // old cases: one resolves inside the window, one worsens inside it
    reconcile(s, [item("system:g"), item("invoice:i"), item("lead:old")], at(-8), {
      sweepAbsent: true,
    });
    // window opens at T0
    reconcile(
      s,
      [item("system:g", { severity: "red" }), item("lead:old"), item("lead:new")],
      at(1),
      { sweepAbsent: true },
    ); // reopens system:g, creates lead:new, resolves invoice:i
    reconcile(
      s,
      [item("system:g", { severity: "red" }), item("lead:old", { severity: "red" }), item("lead:new")],
      at(2),
      { sweepAbsent: true },
    ); // lead:old worsens

    const d = computeDelta(s, T0);
    expect(d.new.map((e) => e.id)).toEqual(["lead:new"]);
    expect(d.reopened.map((e) => e.id)).toEqual(["system:g"]);
    expect(d.resolved.map((e) => e.id)).toEqual(["invoice:i"]);
    // a case NEW inside the window reports only as new (its existence is the
    // news); worsened is for pre-existing cases
    expect(d.worsened.map((e) => e.id)).toEqual(["lead:old"]);
    expect(d.new[0]!.summary).toContain("title of lead:new");
  });

  it("excludes changes before the cutoff and empty-windows to nothing", () => {
    const s = empty();
    reconcile(s, [item("a:1")], at(-5), { sweepAbsent: true });
    reconcile(s, [], at(-4), { sweepAbsent: true });
    reconcile(s, [item("b:2")], at(-4), { sweepAbsent: true }); // resolves a:1
    const d = computeDelta(s, T0);
    expect(d.new).toEqual([]);
    expect(d.reopened).toEqual([]);
    expect(d.worsened).toEqual([]);
    expect(d.resolved).toEqual([]);
  });

  it("uses the LATEST transition in the window (reopened then re-resolved → resolved)", () => {
    const s = empty();
    reconcile(s, [item("task:t")], at(-5), { sweepAbsent: true });
    resolveCase(s, "task:t", "completed", at(-4));
    reconcile(s, [item("task:t")], at(1), { observedAt: at(1), sweepAbsent: true }); // reopens
    reconcile(s, [], at(2), { sweepAbsent: false });
    reconcile(s, [item("other:o")], at(2), { sweepAbsent: true }); // resolves task:t again
    const d = computeDelta(s, T0);
    expect(d.reopened).toEqual([]);
    expect(d.resolved.map((e) => e.id)).toEqual(["task:t"]);
  });
});

/* ── wiring: the real hwc_today handler over a temp briefing dir ──── */

describe("hwc_today wiring (temp HWC_BRIEFING_DIR)", () => {
  const INVOICE_ID = "invoice:22-104-final-invoice";
  const SYSTEM_ID = "system:grafana-disk";

  function briefingJson(level: "warning" | "critical", generatedAt: string): string {
    return JSON.stringify({
      generated_at: generatedAt,
      sections: {
        overdue: {
          items: [
            {
              name: "Final Invoice",
              job_number: "22-104",
              job_name: "Smith",
              amount: 1200,
              days_past_due: 12,
            },
          ],
        },
      },
      alerts: [{ level, section: "system", message: "Grafana disk (89%)" }],
    });
  }

  it("migrates a v1 state file, honors dismiss+reason, and wakes on worse severity", async () => {
    const dir = await mkdtemp(join(tmpdir(), "today-ledger-"));
    await mkdir(join(dir, "output"), { recursive: true });
    const dismissedAt = new Date(Date.now() - 10 * DAY_MS).toISOString();
    await writeFile(
      join(dir, "output", "briefing.json"),
      briefingJson("warning", new Date().toISOString()),
    );
    await writeFile(
      join(dir, "output", "today-state.json"),
      JSON.stringify({ dismissed: { [INVOICE_ID]: dismissedAt }, dispatched: {} }),
    );

    process.env["HWC_BRIEFING_DIR"] = dir; // must be set before today.ts loads
    const { todayTools } = await import("../src/tools/today.js");
    const handler = todayTools()[0]!.handler;

    // board: migrated dismissal keeps the invoice hidden; system alert visible
    const board1 = await handler({ action: "board" });
    expect(board1.status).toBe("ok");
    const ids1 = (board1.data as any).items.map((i: any) => i.id);
    expect(ids1).toContain(SYSTEM_ID);
    expect(ids1).not.toContain(INVOICE_ID);

    // state file is now v2 on disk, invoice case snoozed via migration
    const disk1 = JSON.parse(await readFile(join(dir, "output", "today-state.json"), "utf8"));
    expect(disk1.schemaVersion).toBe(2);
    expect(disk1.cases[INVOICE_ID].state).toBe("snoozed");
    expect(disk1.cases[SYSTEM_ID].state).toBe("open");
    expect(disk1.cases[SYSTEM_ID].timesSurfaced).toBe(1);

    // dismiss with reason → same external message as v1, reason + wake recorded
    const res = await handler({ action: "dismiss", id: SYSTEM_ID, reason: "cleanup scheduled" });
    expect(res).toMatchObject({ status: "ok", message: `dismissed: ${SYSTEM_ID}` });
    const disk2 = JSON.parse(await readFile(join(dir, "output", "today-state.json"), "utf8"));
    expect(disk2.cases[SYSTEM_ID].state).toBe("snoozed");
    expect(disk2.cases[SYSTEM_ID].snooze.reason).toBe("cleanup scheduled");
    expect(disk2.cases[SYSTEM_ID].snooze.severityAtSnooze).toBe("amber");

    const board2 = await handler({ action: "board" });
    expect((board2.data as any).items.map((i: any) => i.id)).not.toContain(SYSTEM_ID);

    const between = new Date();
    await new Promise((r) => setTimeout(r, 10));

    // the alert escalates in a fresh briefing → the snoozed case wakes
    await writeFile(
      join(dir, "output", "briefing.json"),
      briefingJson("critical", new Date().toISOString()),
    );
    const board3 = await handler({ action: "board" });
    const ids3 = (board3.data as any).items.map((i: any) => i.id);
    expect(ids3).toContain(SYSTEM_ID);
    const disk3 = JSON.parse(await readFile(join(dir, "output", "today-state.json"), "utf8"));
    expect(disk3.cases[SYSTEM_ID].timesReopened).toBe(1);

    // delta sees the reopen
    const delta = await handler({ action: "delta", since: between.toISOString() });
    expect(delta.status).toBe("ok");
    expect((delta.data as any).reopened.map((e: any) => e.id)).toContain(SYSTEM_ID);
  });
});
