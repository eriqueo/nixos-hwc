/**
 * Transition decision engine + audit-store semantics.
 *
 * One file rather than several: every case here is one behaviour of the same
 * feature (decide → reserve → deliver → settle → sweep), and the SQLite cases
 * need the same temp-database fixture as the wiring cases. The existing sibling
 * `executive-contract.test.ts` covers rendering contracts and shares nothing
 * with this fixture, so it could not hold these.
 *
 * The store cases use a real on-disk SQLite database, not a fake: the ordering
 * guarantee under test (reserve before the external effect, exactly one claim)
 * is a property of the transaction, and a fake would assert our own mock.
 */

import assert from "node:assert/strict";
import test from "node:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  MAX_DELIVERY_ATTEMPTS,
  REMINDER_AFTER_MS,
  RESERVATION_TIMEOUT_MS,
  decideTransition,
  isFullyDelivered,
  transitionTagOf,
  type TransitionState,
} from "../core/transition.js";
import { webhookToNotifications } from "../core/from-alertmanager.js";
import {
  makeSqliteAuditLog,
  NOTIFICATION_RETENTION_DAYS,
  RESOLVED_TRANSITION_RETENTION_DAYS,
} from "../adapters/audit-sqlite.js";
import { makeNoopAuditLog } from "../adapters/audit-noop.js";
import type { AuditPort } from "../ports/audit.js";
import type { Logger } from "../ports/log.js";
import type { Notification, TransitionTag } from "../core/types.js";

const T0 = Date.UTC(2026, 8, 1, 0, 0, 0);
const DAY_MS = 24 * 60 * 60 * 1000;

const silentLog: Logger = {
  debug() {}, info() {}, warn() {}, error() {},
  child(): Logger { return silentLog; },
};

const firing: TransitionTag = { key: "alertmanager:abc123", state: "firing" };
const resolved: TransitionTag = { key: "alertmanager:abc123", state: "resolved" };

function priorState(over: Partial<TransitionState> = {}): TransitionState {
  return {
    key: firing.key,
    state: "firing",
    firstSeenAt: T0,
    lastDecidedAt: T0,
    announcedAt: T0,
    deliveryAttempts: 0,
    delivered: true,
    reserved: false,
    lastReason: "new-firing",
    ...over,
  };
}

function withStore(fn: (store: AuditPort) => void): void {
  const dir = mkdtempSync(join(tmpdir(), "hwc-notify-test-"));
  const store = makeSqliteAuditLog({ dbPath: join(dir, "audit.sqlite"), log: silentLog });
  try {
    fn(store);
  } finally {
    store.close();
    rmSync(dir, { recursive: true, force: true });
  }
}

function notification(over: Partial<Notification> = {}): Notification {
  return {
    id: "n-1",
    title: "Disk usage is critical",
    body: "95% of /mnt/media is used.",
    priority: 1,
    topic: "monitoring",
    source: "alertmanager",
    tags: [],
    context: {},
    occurredAt: new Date(T0).toISOString(),
    ...over,
  };
}

// ── Decision states ───────────────────────────────────────────────────────

test("a firing alert we have never seen is new-firing", () => {
  const d = decideTransition({ tag: firing, priority: 1, now: T0, prior: null });
  assert.deepEqual(d, { outcome: "announce", reason: "new-firing", attempt: 1 });
});

test("a resolved alert we never announced is suppressible noise", () => {
  const unknown = decideTransition({ tag: resolved, priority: 1, now: T0, prior: null });
  assert.equal(unknown.outcome, "suppress");
  assert.equal(unknown.reason, "unknown-resolved");

  // Same verdict when we have a row but never got the firing out the door.
  const neverAnnounced = decideTransition({
    tag: resolved, priority: 1, now: T0,
    prior: priorState({ announcedAt: null, delivered: false, deliveryAttempts: 3 }),
  });
  assert.equal(neverAnnounced.reason, "unknown-resolved");
});

test("firing → resolved of an announced alert is a state transition", () => {
  const d = decideTransition({ tag: resolved, priority: 1, now: T0 + DAY_MS, prior: priorState() });
  assert.deepEqual(d, { outcome: "announce", reason: "state-transition", attempt: 1 });
});

test("a failed delivery retries, bounded at MAX_DELIVERY_ATTEMPTS", () => {
  for (let attempts = 1; attempts < MAX_DELIVERY_ATTEMPTS; attempts += 1) {
    const d = decideTransition({
      tag: firing, priority: 3, now: T0 + 1000,
      prior: priorState({ announcedAt: null, delivered: false, deliveryAttempts: attempts }),
    });
    assert.deepEqual(d, {
      outcome: "announce", reason: "failed-delivery-retry", attempt: attempts + 1,
    });
  }
  const exhausted = decideTransition({
    tag: firing, priority: 3, now: T0 + 1000,
    prior: priorState({
      announcedAt: null, delivered: false, deliveryAttempts: MAX_DELIVERY_ATTEMPTS,
    }),
  });
  assert.equal(exhausted.outcome, "suppress");
  assert.equal(exhausted.reason, "retry-exhausted");
});

test("an unchanged P1 reminds after 24h; an unchanged P3 never does", () => {
  const before = decideTransition({
    tag: firing, priority: 1, now: T0 + REMINDER_AFTER_MS - 1, prior: priorState(),
  });
  assert.equal(before.reason, "unchanged");

  const after = decideTransition({
    tag: firing, priority: 1, now: T0 + REMINDER_AFTER_MS, prior: priorState(),
  });
  assert.deepEqual(after, { outcome: "announce", reason: "priority-reminder", attempt: 1 });

  const p3 = decideTransition({
    tag: firing, priority: 3, now: T0 + 30 * DAY_MS, prior: priorState(),
  });
  assert.equal(p3.outcome, "suppress");
  assert.equal(p3.reason, "unchanged");
});

test("an open reservation blocks a second decision for the same key", () => {
  const d = decideTransition({
    tag: firing, priority: 1, now: T0 + 5, prior: priorState({ reserved: true }),
  });
  assert.deepEqual(d, { outcome: "suppress", reason: "already-reserved", attempt: 0 });
});

test("an abandoned claim expires instead of muting the alert forever", () => {
  const stale = priorState({
    reserved: true,
    lastDecidedAt: T0,
    announcedAt: null,
    delivered: false,
    deliveryAttempts: 1,
  });
  // Still in flight.
  assert.equal(
    decideTransition({
      tag: firing, priority: 1, now: T0 + RESERVATION_TIMEOUT_MS - 1, prior: stale,
    }).reason,
    "already-reserved",
  );
  // The process died between reserve and settle: the claim is not live, and the
  // attempt it represented counts as failed.
  assert.equal(
    decideTransition({
      tag: firing, priority: 1, now: T0 + RESERVATION_TIMEOUT_MS, prior: stale,
    }).reason,
    "failed-delivery-retry",
  );
});

test("a 207 partial delivery is not a delivery", () => {
  assert.equal(isFullyDelivered({ attempted: 2, succeeded: 2 }), true);
  assert.equal(isFullyDelivered({ attempted: 2, succeeded: 1 }), false);
  assert.equal(isFullyDelivered({ attempted: 0, succeeded: 0 }), false);
});

// ── Status-independent keys, unchanged ids ────────────────────────────────

test("firing and resolved share one key while keeping their distinct ids", () => {
  const payload = {
    alerts: [
      { status: "firing" as const, labels: { alertname: "HighDiskUsage", severity: "P5" },
        annotations: {}, startsAt: "2026-09-01T00:00:00Z", fingerprint: "abc123" },
      { status: "resolved" as const, labels: { alertname: "HighDiskUsage", severity: "P5" },
        annotations: {}, startsAt: "2026-09-01T00:00:00Z", fingerprint: "abc123" },
    ],
    groupLabels: {}, commonLabels: {}, commonAnnotations: {},
  };
  const notifs = webhookToNotifications(payload);
  const fire = notifs[0];
  const clear = notifs[1];
  if (!fire || !clear) throw new Error("converter must emit one notification per alert");

  // The id contract is byte-for-byte what it was before the gate existed.
  assert.equal(fire.id, "alertmanager-abc123-firing");
  assert.equal(clear.id, "alertmanager-abc123-resolved");
  // The transition key is the same on both sides of the lifecycle.
  assert.equal(fire.transition?.key, "alertmanager:abc123");
  assert.equal(clear.transition?.key, "alertmanager:abc123");
  assert.equal(fire.transition?.state, "firing");
  assert.equal(clear.transition?.state, "resolved");
});

// ── Shadow-mode wiring ────────────────────────────────────────────────────

test("only tagged notifications are eligible, and never when the gate is off", () => {
  const tagged = notification({ transition: firing });
  const untagged = notification();

  assert.deepEqual(transitionTagOf(tagged, "shadow"), firing);
  // A /notify, CLI or MCP message carries no tag and can never be gated.
  assert.equal(transitionTagOf(untagged, "shadow"), null);
  assert.equal(transitionTagOf(tagged, "off"), null);
});

test("the no-op audit port returns no decision rather than a suppression", () => {
  const noop = makeNoopAuditLog();
  assert.equal(noop.reserveTransition({ tag: firing, priority: 1, now: T0 }), null);
  assert.deepEqual(noop.cleanup(T0), { notifications: 0, deliveries: 0, transitions: 0 });
});

// ── Durable store ─────────────────────────────────────────────────────────

test("reserve claims the attempt and a second reserve cannot claim it again", () => {
  withStore((store) => {
    const first = store.reserveTransition({ tag: firing, priority: 1, now: T0 });
    assert.equal(first?.outcome, "announce");
    assert.equal(first?.reason, "new-firing");

    // No settle in between: the claim is still open, exactly as it would be
    // while the Discord POST is in flight.
    const second = store.reserveTransition({ tag: firing, priority: 1, now: T0 + 1 });
    assert.equal(second?.outcome, "suppress");
    assert.equal(second?.reason, "already-reserved");

    const state = store.getTransition(firing.key);
    assert.equal(state?.reserved, true);
    assert.equal(state?.deliveryAttempts, 1);
    assert.equal(state?.announcedAt, null);
  });
});

test("an observation that arrives during a live claim leaves the row alone", () => {
  withStore((store) => {
    store.reserveTransition({ tag: firing, priority: 1, now: T0 });
    // The alert resolves while the firing notification is still being delivered.
    const during = store.reserveTransition({ tag: resolved, priority: 5, now: T0 + 1 });
    assert.equal(during?.reason, "already-reserved");

    const state = store.getTransition(firing.key);
    assert.equal(state?.state, "firing", "the in-flight attempt still owns the state");
    assert.equal(state?.reserved, true, "its claim was not cleared");
    assert.equal(state?.deliveryAttempts, 1);

    // The in-flight attempt can still settle its own state.
    store.settleTransition({ tag: firing, now: T0 + 2, delivered: true });
    const settled = store.getTransition(firing.key);
    assert.equal(settled?.reserved, false);
    assert.equal(settled?.announcedAt, T0 + 2);
  });
});

test("duplicates during a live claim cannot extend its expiry", () => {
  withStore((store) => {
    store.reserveTransition({ tag: firing, priority: 1, now: T0 });
    const claimed = store.getTransition(firing.key);

    // A duplicate every minute — Alertmanager retrying a POST it never got a
    // 200 for, or the resolve arriving while the firing is still in flight.
    for (let t = 60_000; t < RESERVATION_TIMEOUT_MS; t += 60_000) {
      assert.equal(
        store.reserveTransition({ tag: firing, priority: 1, now: T0 + t })?.reason,
        "already-reserved",
      );
    }
    assert.deepEqual(
      store.getTransition(firing.key), claimed,
      "a suppressed duplicate must leave the claim row byte-identical",
    );

    // Expiry is measured from the CLAIM, not from the last thing that touched
    // the row. The `already-reserved` branch used to stamp last_decided_at with
    // `now`, and last_decided_at is the same column RESERVATION_TIMEOUT_MS is
    // measured against — so any drip of repeats faster than five minutes kept a
    // CRASHED attempt claimed forever. That is the permanent mute the timeout
    // exists to prevent, reintroduced by the code meant to honour it.
    assert.equal(
      store.reserveTransition({
        tag: firing, priority: 1, now: T0 + RESERVATION_TIMEOUT_MS,
      })?.reason,
      "failed-delivery-retry",
    );
  });
});

test("a duplicate does not overwrite the reason the in-flight attempt settles with", () => {
  withStore((store) => {
    store.reserveTransition({ tag: firing, priority: 1, now: T0 });
    store.reserveTransition({ tag: firing, priority: 1, now: T0 + 1 });
    store.settleTransition({ tag: firing, now: T0 + 2, delivered: true });

    // settleTransition writes the row's reason back when it releases the claim.
    // A duplicate that had overwritten it made a delivered announcement record
    // itself as a suppression — and reading these records against real traffic
    // is the whole purpose of the shadow slice.
    assert.equal(store.getTransition(firing.key)?.lastReason, "new-firing");
  });
});

test("settling a delivery stamps the announcement and clears the retry counter", () => {
  withStore((store) => {
    store.reserveTransition({ tag: firing, priority: 1, now: T0 });
    store.settleTransition({ tag: firing, now: T0 + 500, delivered: true });

    const state = store.getTransition(firing.key);
    assert.equal(state?.reserved, false);
    assert.equal(state?.delivered, true);
    assert.equal(state?.announcedAt, T0 + 500);
    assert.equal(state?.deliveryAttempts, 0);

    // Same state, already delivered, low urgency → nothing new to say.
    const repeat = store.reserveTransition({ tag: firing, priority: 3, now: T0 + 600 });
    assert.equal(repeat?.reason, "unchanged");
  });
});

test("a failed settle leaves the counter, so the next observation is a bounded retry", () => {
  withStore((store) => {
    let now = T0;
    for (let i = 1; i <= MAX_DELIVERY_ATTEMPTS; i += 1) {
      const d = store.reserveTransition({ tag: firing, priority: 3, now });
      assert.equal(d?.outcome, "announce", `attempt ${i} should be announced`);
      assert.equal(d?.attempt, i);
      // 207 partial or outright failure — same verdict for the notification.
      store.settleTransition({ tag: firing, now: now + 10, delivered: false });
      now += 1000;
    }
    const stopped = store.reserveTransition({ tag: firing, priority: 3, now });
    assert.equal(stopped?.outcome, "suppress");
    assert.equal(stopped?.reason, "retry-exhausted");
  });
});

test("a resolve after a delivered firing transitions; the counters start over", () => {
  withStore((store) => {
    store.reserveTransition({ tag: firing, priority: 1, now: T0 });
    store.settleTransition({ tag: firing, now: T0 + 10, delivered: true });

    const d = store.reserveTransition({ tag: resolved, priority: 5, now: T0 + DAY_MS });
    assert.equal(d?.reason, "state-transition");
    const state = store.getTransition(firing.key);
    assert.equal(state?.state, "resolved");
    assert.equal(state?.announcedAt, null);
    assert.equal(state?.firstSeenAt, T0, "first observation is never rewritten");
  });
});

test("the first observation of a notification id survives re-arrival", () => {
  withStore((store) => {
    const notif = notification({ id: "alertmanager-abc123-firing" });
    store.record({
      notification: notif,
      matchedRule: "first-rule",
      receivedAt: new Date(T0).toISOString(),
      results: [{ channelId: "discord-ops", ok: false, durationMs: 5, message: "boom" }],
    });
    store.record({
      notification: { ...notif, title: "REWRITTEN" },
      matchedRule: "second-rule",
      receivedAt: new Date(T0 + DAY_MS).toISOString(),
      results: [{ channelId: "discord-ops", ok: true, durationMs: 7 }],
    });

    const rows = store.recent({ limit: 10 });
    assert.equal(rows.length, 1, "one id is still one audit row");
    const row = rows[0];
    if (!row) throw new Error("expected exactly one audit row");
    assert.equal(row.title, "Disk usage is critical", "the first observation wins");
    assert.equal(row.matchedRule, "first-rule");
    assert.equal(row.receivedAt, new Date(T0).toISOString());
    assert.equal(row.deliveries.length, 2, "every attempt is retained");
  });
});

test("cleanup is bounded by the injected clock and keeps live state", () => {
  withStore((store) => {
    const old = new Date(T0 - (NOTIFICATION_RETENTION_DAYS + 5) * DAY_MS).toISOString();
    const recent = new Date(T0 - 1 * DAY_MS).toISOString();

    store.record({
      notification: notification({ id: "old-1", occurredAt: old }),
      matchedRule: null, receivedAt: old,
      results: [{ channelId: "discord-ops", ok: true, durationMs: 3 }],
    });
    store.record({
      notification: notification({ id: "recent-1", occurredAt: recent }),
      matchedRule: null, receivedAt: recent,
      results: [{ channelId: "discord-ops", ok: true, durationMs: 3 }],
    });

    // A long-resolved alert, and a still-firing one.
    const staleResolved: TransitionTag = { key: "alertmanager:stale", state: "resolved" };
    const liveFiring: TransitionTag = { key: "alertmanager:live", state: "firing" };
    const staleAt = T0 - (RESOLVED_TRANSITION_RETENTION_DAYS + 5) * DAY_MS;
    store.reserveTransition({ tag: { ...staleResolved, state: "firing" }, priority: 1, now: staleAt });
    store.settleTransition({ tag: { ...staleResolved, state: "firing" }, now: staleAt, delivered: true });
    store.reserveTransition({ tag: staleResolved, priority: 5, now: staleAt });
    store.reserveTransition({ tag: liveFiring, priority: 1, now: staleAt });

    const counts = store.cleanup(T0);
    assert.deepEqual(counts, { notifications: 1, deliveries: 1, transitions: 1 });

    const rows = store.recent({ limit: 10 });
    assert.deepEqual(rows.map((r) => r.id), ["recent-1"]);
    assert.equal(store.getTransition(staleResolved.key), null);
    assert.ok(store.getTransition(liveFiring.key), "a firing alert is live state, never swept");
  });
});
