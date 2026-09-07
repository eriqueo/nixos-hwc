/**
 * Production wiring of the transition gate.
 *
 * WHY THIS FILE EXISTS, SEPARATELY FROM transition-shadow.test.ts
 *
 * That file pins the DECISIONS (`decideTransition`) and the STORE
 * (`reserveTransition` / `settleTransition` against a real SQLite file). It does
 * not pin the CALLS. Measured 2026-09-07: deleting both gate calls from the
 * dispatch path left all 22 of its cases green — a gate that is never invoked
 * still passes every test of what it would have decided. Everything here is
 * about invocation and order, which is why it uses recording fakes rather than
 * the on-disk database: the property under test is "who called what, when", and
 * a real store would only re-answer questions the sibling file already answers.
 *
 * The four properties, each asserted as an exact event sequence rather than a
 * count, because "reserve happened" and "reserve happened FIRST" are different
 * claims and only the second one is safe:
 *
 *   1. the claim is taken before the routing table is read and before any
 *      channel is touched — a reservation made after the Discord POST cannot
 *      stop a second POST;
 *   2. the claim is released only after the delivery result AND the audit row
 *      exist — releasing early loses the outcome the row is supposed to carry;
 *   3. exactly one decision per NOTIFICATION, never one per channel — a P1 that
 *      fans out to Discord + SMTP is one alert, not two;
 *   4. shadow mode suppresses nothing: a `suppress` verdict, and a store that
 *      fails outright, both still deliver to every routed channel.
 */

import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { CircuitBreaker } from "../core/circuit.js";
import { webhookToNotifications } from "../core/from-alertmanager.js";
import { dispatchNotification, type PipelineDeps } from "../core/pipeline.js";
import type { TransitionDecision, TransitionMode, TransitionState } from "../core/transition.js";
import type { DeliveryResult, Notification } from "../core/types.js";
import type {
  AuditPort,
  AuditRecord,
  CleanupCounts,
  RecentNotification,
  ReserveTransitionInput,
  SettleTransitionInput,
} from "../ports/audit.js";
import type { Channel } from "../ports/channel.js";
import type { Logger } from "../ports/log.js";
import type { RoutingRule } from "../schemas/runtime-config.js";

/** Injected clock base. Any wall-clock read inside core lands far outside it. */
const T0 = Date.UTC(2026, 8, 1, 0, 0, 0);

const silentLog: Logger = {
  debug() {}, info() {}, warn() {}, error() {},
  child(): Logger { return silentLog; },
};

const KEY = "alertmanager:abc123";
const ID = "alertmanager-abc123-firing";
const RULE = "alerts-both-channels";

const announce: TransitionDecision = { outcome: "announce", reason: "new-firing", attempt: 1 };

/** One firing alert, built by the real converter so the tag is the real tag. */
function firingAlert(): Notification {
  const notifs = webhookToNotifications({
    alerts: [
      {
        status: "firing" as const,
        labels: { alertname: "HighDiskUsage", severity: "P5" },
        annotations: { summary: "Disk usage is critical" },
        startsAt: "2026-09-01T00:00:00Z",
        fingerprint: "abc123",
      },
    ],
    groupLabels: {}, commonLabels: {}, commonAnnotations: {},
  });
  const notif = notifs[0];
  if (!notif) throw new Error("converter must emit one notification per alert");
  return notif;
}

interface HarnessOpts {
  /** What the fake store returns from reserveTransition. Null = store failed. */
  readonly decision: TransitionDecision | null;
  /** Channel ids whose send() succeeds. Absent ⇒ all of them. */
  readonly okChannels?: ReadonlySet<string>;
  readonly mode?: TransitionMode;
}

interface Harness {
  readonly deps: PipelineDeps;
  /** Ordered log of every observable effect, in the order it happened. */
  readonly events: readonly string[];
  readonly reserves: readonly ReserveTransitionInput[];
  readonly settles: readonly SettleTransitionInput[];
}

function makeHarness(opts: HarnessOpts): Harness {
  const events: string[] = [];
  const reserves: ReserveTransitionInput[] = [];
  const settles: SettleTransitionInput[] = [];

  const audit: AuditPort = {
    record(rec: AuditRecord): void {
      events.push(`record:${rec.notification.id}`);
    },
    recent(): RecentNotification[] { return []; },
    reserveTransition(input: ReserveTransitionInput): TransitionDecision | null {
      reserves.push(input);
      events.push(`reserve:${input.tag.key}:${input.tag.state}`);
      return opts.decision;
    },
    settleTransition(input: SettleTransitionInput): void {
      settles.push(input);
      events.push(`settle:${input.tag.key}:${input.delivered ? "delivered" : "failed"}`);
    },
    getTransition(): TransitionState | null { return null; },
    cleanup(): CleanupCounts {
      return { notifications: 0, deliveries: 0, transitions: 0 };
    },
    close(): void {},
  };

  const makeChannel = (id: string): Channel => ({
    id,
    name: id,
    adapter: "log-only",
    async send(notification: Notification): Promise<DeliveryResult> {
      events.push(`send:${id}:${notification.id}`);
      return { channelId: id, ok: opts.okChannels?.has(id) ?? true, durationMs: 1 };
    },
  });

  const channels = new Map<string, Channel>([
    ["discord-ops", makeChannel("discord-ops")],
    ["smtp-eric", makeChannel("smtp-eric")],
  ]);

  // The routing table is handed over behind a Proxy so "the claim was taken
  // before routing" is an OBSERVATION and not a comment: `route` cannot read the
  // rule list without this trap firing. Only the first read is recorded — the
  // array iterator touches the list several times per call and the count is not
  // the point, the position in the sequence is.
  const rules: RoutingRule[] = [
    { name: RULE, match: { topic: "monitoring" }, channels: ["discord-ops", "smtp-eric"] },
  ];
  let routeSeen = false;
  const routes = new Proxy(rules, {
    get(target, prop, receiver): unknown {
      if (!routeSeen) {
        routeSeen = true;
        events.push("route");
      }
      return Reflect.get(target, prop, receiver);
    },
  });

  // Monotonic injected clock. Every value stays within a few ms of T0, so a
  // stray Date.now() anywhere under the composition root is visible as a
  // timestamp decades away rather than as a silent pass.
  let tick = 0;
  const now = (): number => {
    tick += 1;
    return T0 + tick;
  };

  return {
    deps: {
      audit,
      channels,
      routes,
      defaultChannels: [],
      transitionMode: opts.mode ?? "shadow",
      breaker: new CircuitBreaker({ failureThreshold: 5, cooldownMs: 60_000 }),
      now,
    },
    events,
    reserves,
    settles,
  };
}

// ── Order ─────────────────────────────────────────────────────────────────

test("the claim is taken before routing and released after the audit record", async () => {
  const h = makeHarness({ decision: announce });
  const outcome = await dispatchNotification(h.deps, firingAlert(), silentLog);

  // The whole sequence, exactly. Delete the openTransition call and the first
  // element disappears; delete closeTransition and the last one does; move the
  // settle above auditLog.record and the last two swap. Each is a distinct
  // failure with a readable diff.
  assert.deepEqual([...h.events], [
    `reserve:${KEY}:firing`,
    "route",
    `send:discord-ops:${ID}`,
    `send:smtp-eric:${ID}`,
    `record:${ID}`,
    `settle:${KEY}:delivered`,
  ]);

  // Routing is untouched by the gate.
  assert.equal(outcome.matchedRule, RULE);
  assert.deepEqual(
    { attempted: outcome.result.attempted, succeeded: outcome.result.succeeded },
    { attempted: 2, succeeded: 2 },
  );
});

test("one decision per notification, not one per channel", async () => {
  const h = makeHarness({ decision: announce });
  await dispatchNotification(h.deps, firingAlert(), silentLog);

  assert.equal(h.events.filter((e) => e.startsWith("send:")).length, 2, "two channels");
  assert.equal(h.reserves.length, 1, "…and still exactly one reservation");
  assert.equal(h.settles.length, 1, "…and exactly one settle");
  assert.equal(h.reserves[0]?.tag.key, KEY);
  assert.equal(h.reserves[0]?.priority, 1, "P5 severity reaches the engine as priority 1");
  assert.equal(h.settles[0]?.tag.key, KEY);
});

test("the clock is injected, and the settle reads it after the reservation", async () => {
  const h = makeHarness({ decision: announce });
  await dispatchNotification(h.deps, firingAlert(), silentLog);

  const reserved = h.reserves[0];
  const settled = h.settles[0];
  if (!reserved || !settled) throw new Error("both halves of the gate must have run");

  assert.ok(settled.now > reserved.now, "the claim is released after it is taken");
  // A Date.now() left anywhere under the pipeline would put this in real time —
  // years, not milliseconds, from the injected base.
  assert.ok(settled.now - T0 < 1000, `injected clock leaked: settle read ${settled.now}`);
});

// ── Outcome fidelity ──────────────────────────────────────────────────────

test("a 207 partial delivery settles as not-delivered", async () => {
  const h = makeHarness({ decision: announce, okChannels: new Set(["discord-ops"]) });
  const outcome = await dispatchNotification(h.deps, firingAlert(), silentLog);

  assert.equal(outcome.result.succeeded, 1);
  assert.equal(outcome.result.attempted, 2);
  assert.equal(h.settles[0]?.delivered, false, "some channels got it ⇒ the alert did not");
  assert.equal(h.events.at(-1), `settle:${KEY}:failed`);
});

// ── Shadow mode suppresses nothing ────────────────────────────────────────

test("a suppress verdict still routes to every channel", async () => {
  const h = makeHarness({
    decision: { outcome: "suppress", reason: "unchanged", attempt: 2 },
  });
  const outcome = await dispatchNotification(h.deps, firingAlert(), silentLog);

  assert.deepEqual([...h.events], [
    `reserve:${KEY}:firing`,
    "route",
    `send:discord-ops:${ID}`,
    `send:smtp-eric:${ID}`,
    `record:${ID}`,
  ]);
  assert.equal(outcome.result.attempted, 2, "shadow mode delivers what it would have suppressed");
  assert.equal(outcome.matchedRule, RULE);
  // No settle: recording a delivery the engine called suppressible would refresh
  // announced_at on every repeat and the 24h reminder could never come due.
  assert.equal(h.settles.length, 0);
});

test("a store failure is the absence of a decision, never a suppression", async () => {
  const h = makeHarness({ decision: null });
  const outcome = await dispatchNotification(h.deps, firingAlert(), silentLog);

  assert.equal(h.reserves.length, 1, "the store was asked");
  assert.equal(h.settles.length, 0, "there is no claim to release");
  assert.equal(outcome.result.succeeded, 2, "and the alert went out anyway");
});

// ── Eligibility ───────────────────────────────────────────────────────────

test("an untagged notification never reaches the gate", async () => {
  const h = makeHarness({ decision: announce });
  const manual: Notification = {
    id: "n-1",
    title: "Deploy finished",
    body: "hwc-crm is live.",
    priority: 3,
    topic: "monitoring",
    source: "cli",
    tags: [],
    context: {},
    occurredAt: new Date(T0).toISOString(),
  };
  await dispatchNotification(h.deps, manual, silentLog);

  assert.equal(h.reserves.length, 0, "nothing a human can POST is ever deduplicated");
  assert.deepEqual([...h.events], [
    "route",
    "send:discord-ops:n-1",
    "send:smtp-eric:n-1",
    "record:n-1",
  ]);
});

test("transitionMode=off skips the engine and changes nothing else", async () => {
  const h = makeHarness({ decision: announce, mode: "off" });
  const outcome = await dispatchNotification(h.deps, firingAlert(), silentLog);

  assert.equal(h.reserves.length, 0);
  assert.equal(h.settles.length, 0);
  assert.equal(outcome.result.succeeded, 2);
});

// ── The last hole: the shells must not rebuild the pipeline themselves ─────

test("both HTTP handlers dispatch through the pipeline and nothing else", () => {
  // dist/__tests__/ → the package root → src/main.ts. Present both in the repo
  // and inside buildNpmPackage's checkPhase, which runs from the source root.
  const mainTs = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "src", "main.ts");
  const src = readFileSync(mainTs, "utf8");

  // The tests above cover the gate calls inside core/pipeline.ts. This covers
  // the edge they cannot see: a handler that stops calling the pipeline and
  // orchestrates dispatch itself. It is checked structurally, by the absence of
  // the imports such a handler would need — a stray comment or string cannot
  // satisfy an absence.
  assert.ok(
    !src.includes('from "./core/dispatch.js"'),
    "main.ts must not import dispatch directly — a handler that can fan out on its "
      + "own can fan out without reserving first",
  );
  assert.ok(
    !src.includes('from "./core/router.js"'),
    "main.ts must not import route directly; core/pipeline.ts owns routing",
  );
  assert.ok(src.includes('from "./core/pipeline.js"'), "main.ts must import the pipeline");

  const marker = 'url === "/webhook/alertmanager"';
  const split = src.indexOf(marker);
  assert.ok(split > 0, `main.ts no longer mounts ${marker} — this check has lost its subject`);
  assert.ok(
    src.slice(0, split).includes("dispatchNotification(pipeline"),
    "the /notify handler must dispatch through the pipeline",
  );
  assert.ok(
    src.slice(split).includes("dispatchNotification(pipeline"),
    "the /webhook/alertmanager handler must dispatch through the pipeline",
  );
});
