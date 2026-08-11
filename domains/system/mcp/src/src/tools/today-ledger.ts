/**
 * today-ledger — the pure case-ledger state machine behind hwc_today
 * (engineering-principles Principle 21; canonical spec: brain
 * `_library/ai-ml/case_ledger_pattern.md`).
 *
 * Pure logic only: no fs, no ambient time — `now` is always a parameter
 * (Principle 4). today.ts owns all I/O (read/write today-state.json) and the
 * gateway process stays the single writer of that file (Principle 8).
 *
 * State file v2 (`{ schemaVersion: 2, cases }`) replaces the v1
 * `{ dismissed, dispatched }` maps. Expand-then-contract (R1):
 *  - read either — migrateState() upgrades a v1 file transparently on first
 *    read; write only v2.
 *  - v1-READ PATH IS TEMPORARY: remove the v1 branch of migrateState once the
 *    live file on hwc-server carries `schemaVersion: 2` (checkable predicate:
 *    `jq .schemaVersion output/today-state.json` == 2).
 *
 * The item ids minted by today.ts (`<source>:<entity>`, digit-stripped system
 * slugs) are already content-derived — they ARE the case fingerprints (ledger
 * law 1); this module keys cases by them and mints nothing.
 */

/* ── vocabulary ───────────────────────────────────────────────────── */

export type Severity = "red" | "amber";
export type CaseState = "open" | "snoozed" | "resolved";
export type CaseEventType = "observation" | "action" | "transition";

/**
 * Event-body prefixes — the closed vocabulary computeDelta routes on
 * (Principle 12). The event shape is fixed at {at, type, body}, so the prefix
 * is the machine-readable channel inside `body`; emitters and the delta view
 * both import these, never restate them.
 */
export const REOPENED = "reopened:";
export const RESOLVED = "resolved:";
export const SNOOZED = "snoozed:";
export const WORSENED = "worsened:";

export interface CaseEvent {
  at: string; // ISO
  type: CaseEventType;
  body: string;
}

export interface Snooze {
  until?: string; // ISO — expiry fallback (TTL is the fallback, not the mechanism)
  reason?: string;
  severityAtSnooze?: Severity; // wake condition for system: cases
}

export interface Case {
  state: CaseState;
  snooze?: Snooze;
  firstSeen: string;
  lastSeen: string;
  timesSurfaced: number;
  timesReopened: number;
  /** Capped at EVENTS_CAP — oldest dropped first. */
  events: CaseEvent[];
  /* Extensions beyond the minimum case shape, each earning its field:
   * title — human-readable delta summaries for cases no longer in the
   *   briefing (a resolved case's item is gone; the id alone is opaque).
   * lastSeverity — worsened-detection needs the previous run's severity.
   * resolvedAt — guards reopen-on-resurface against the STALE briefing the
   *   resolution happened under (complete must clear immediately even though
   *   the item stays in briefing.json until the next gather). */
  title?: string;
  lastSeverity?: Severity;
  resolvedAt?: string;
}

export interface LedgerState {
  schemaVersion: 2;
  cases: Record<string, Case>;
  /** Default delta window cursor — advanced by each parameterless delta call. */
  lastDeltaAt?: string;
}

/** What today.ts observed on this render — one entry per derived item. */
export interface ObservedItem {
  id: string;
  title: string;
  severity: Severity;
  source: string;
}

export interface ReconcileOptions {
  /** briefing.generated_at — gates reopen-after-resolution and absence sweep. */
  observedAt?: Date;
  /**
   * Only sweep absent cases to resolved when the briefing is trustworthy
   * (non-empty, no error marker). A degraded briefing must not mass-resolve.
   */
  sweepAbsent: boolean;
}

export interface DeltaEntry {
  id: string;
  summary: string;
}

export interface Delta {
  since: string;
  new: DeltaEntry[];
  reopened: DeltaEntry[];
  worsened: DeltaEntry[];
  resolved: DeltaEntry[];
}

/* ── bounds (Principle 13 — every store states its limit) ─────────── */

export const EVENTS_CAP = 30;
/** Snooze expiry fallback — parity with the v1 30-day dismissal TTL. */
export const SNOOZE_DEFAULT_DAYS = 30;
/** Resolved cases prune this long after resolution (AUTO-MANAGED retention). */
export const RESOLVED_RETENTION_DAYS = 30;
/** A snoozed case unseen this long resolves — its source stopped emitting. */
export const STALE_SNOOZE_RESOLVE_DAYS = 30;

const DAY_MS = 86_400_000;

/* ── helpers ──────────────────────────────────────────────────────── */

function sevRank(s: Severity): number {
  return s === "red" ? 1 : 0;
}

function pushEvent(c: Case, ev: CaseEvent): void {
  c.events.push(ev);
  if (c.events.length > EVENTS_CAP) c.events = c.events.slice(-EVENTS_CAP);
}

function newCase(atIso: string, title?: string): Case {
  return {
    state: "open",
    firstSeen: atIso,
    lastSeen: atIso,
    timesSurfaced: 0,
    timesReopened: 0,
    events: [],
    ...(title !== undefined ? { title } : {}),
  };
}

function reopen(c: Case, cause: string, atIso: string): void {
  c.state = "open";
  c.timesReopened += 1;
  delete c.snooze;
  delete c.resolvedAt;
  pushEvent(c, { at: atIso, type: "transition", body: `${REOPENED} ${cause}` });
}

function resolve(c: Case, cause: string, atIso: string): void {
  c.state = "resolved";
  c.resolvedAt = atIso;
  delete c.snooze;
  pushEvent(c, { at: atIso, type: "transition", body: `${RESOLVED} ${cause}` });
}

/** Parse an ISO string to epoch ms, NaN-safe (0 when absent/invalid). */
function t(iso: string | undefined): number {
  if (!iso) return 0;
  const ms = Date.parse(iso);
  return Number.isFinite(ms) ? ms : 0;
}

/* ── migration: v1 → v2, pure, run transparently on read ──────────── */

/**
 * Accepts anything found in today-state.json and returns a valid v2 ledger:
 *  - v2 passes through untouched (idempotent);
 *  - v1 `{dismissed, dispatched}` maps become cases with a migration
 *    transition — dismissed → snoozed with until = dismissal + 30d (exact
 *    behavioral parity with the v1 TTL prune), dispatched → an action event;
 *  - garbage / missing → empty ledger.
 */
export function migrateState(raw: unknown, now: Date): LedgerState {
  const out: LedgerState = { schemaVersion: 2, cases: {} };
  if (typeof raw !== "object" || raw === null) return out;
  const r = raw as Record<string, unknown>;

  if (r["schemaVersion"] === 2 && typeof r["cases"] === "object" && r["cases"] !== null) {
    out.cases = r["cases"] as Record<string, Case>;
    if (typeof r["lastDeltaAt"] === "string") out.lastDeltaAt = r["lastDeltaAt"];
    return out;
  }

  const atIso = now.toISOString();
  const dismissed =
    typeof r["dismissed"] === "object" && r["dismissed"] !== null
      ? (r["dismissed"] as Record<string, unknown>)
      : {};
  const dispatched =
    typeof r["dispatched"] === "object" && r["dispatched"] !== null
      ? (r["dispatched"] as Record<string, unknown>)
      : {};

  for (const [id, iso] of Object.entries(dismissed)) {
    if (typeof iso !== "string") continue;
    const dismissedMs = t(iso) || now.getTime();
    const untilIso = new Date(dismissedMs + SNOOZE_DEFAULT_DAYS * DAY_MS).toISOString();
    const c = newCase(iso);
    c.state = "snoozed";
    c.snooze = { until: untilIso, reason: "migrated from v1 dismissal" };
    pushEvent(c, {
      at: atIso,
      type: "transition",
      body: `${SNOOZED} migrated from v1 dismissed map (dismissed ${iso})`,
    });
    out.cases[id] = c;
  }

  for (const [id, iso] of Object.entries(dispatched)) {
    if (typeof iso !== "string") continue;
    const c = out.cases[id] ?? newCase(iso);
    pushEvent(c, {
      at: atIso,
      type: "action",
      body: `migrated from v1 dispatched map (agent queued ${iso})`,
    });
    out.cases[id] = c;
  }

  return out;
}

/* ── reconcile: one render's lifecycle pass ───────────────────────── */

/**
 * Folds the current render's observed items into the ledger (mutates the
 * passed ledger; caller owns persistence). Rules:
 *  - unknown item → new open case (creation observation);
 *  - known item → lastSeen refresh; open + worsened → observation event;
 *  - snoozed + system severity above severityAtSnooze → reopen (wake-worse);
 *  - snoozed + snooze.until passed while still emitting → reopen (expiry);
 *  - resolved + present in a briefing NEWER than resolvedAt → reopen
 *    (the fix didn't take — this is the trust-verification mechanic);
 *  - absent + open → resolved "no longer emitted" (only when sweepAbsent);
 *  - absent + snoozed for STALE_SNOOZE_RESOLVE_DAYS → resolved;
 *  - resolved + RESOLVED_RETENTION_DAYS past → pruned.
 *
 * Returns the ids whose case is `open` after the pass — the board's
 * visibility filter.
 */
export function reconcile(
  ledger: LedgerState,
  items: ObservedItem[],
  now: Date,
  opts: ReconcileOptions,
): Set<string> {
  const nowIso = now.toISOString();
  const obsMs = opts.observedAt ? opts.observedAt.getTime() : 0;
  const present = new Set<string>();

  for (const item of items) {
    present.add(item.id);
    let c = ledger.cases[item.id];

    if (!c) {
      c = newCase(nowIso, item.title);
      c.lastSeverity = item.severity;
      pushEvent(c, {
        at: nowIso,
        type: "observation",
        body: `first seen: ${item.title} [${item.severity}]`,
      });
      ledger.cases[item.id] = c;
      continue;
    }

    c.lastSeen = nowIso;
    c.title = item.title;
    const prevSev = c.lastSeverity;
    const worse = prevSev !== undefined && sevRank(item.severity) > sevRank(prevSev);

    if (c.state === "open" && worse) {
      pushEvent(c, {
        at: nowIso,
        type: "observation",
        body: `${WORSENED} ${prevSev}→${item.severity}`,
      });
    } else if (c.state === "snoozed") {
      const sn = c.snooze ?? {};
      const wakeWorse =
        item.source === "system" &&
        sn.severityAtSnooze !== undefined &&
        sevRank(item.severity) > sevRank(sn.severityAtSnooze);
      const wakeExpired = sn.until !== undefined && now.getTime() >= t(sn.until);
      if (wakeWorse) {
        reopen(c, `resurfaced worse (${sn.severityAtSnooze}→${item.severity})`, nowIso);
      } else if (wakeExpired) {
        reopen(c, "snooze expired while still emitted", nowIso);
      }
    } else if (c.state === "resolved") {
      if (obsMs > t(c.resolvedAt)) {
        reopen(c, "resurfaced after resolution", nowIso);
      }
      // else: the stale briefing the resolution happened under — stay resolved.
    }

    c.lastSeverity = item.severity;
  }

  for (const [id, c] of Object.entries(ledger.cases)) {
    if (present.has(id)) continue;
    if (c.state === "open" && opts.sweepAbsent) {
      resolve(c, "no longer emitted by source", nowIso);
    } else if (
      c.state === "snoozed" &&
      now.getTime() - t(c.lastSeen) >= STALE_SNOOZE_RESOLVE_DAYS * DAY_MS
    ) {
      resolve(c, "snoozed and not emitted for 30d", nowIso);
    } else if (
      c.state === "resolved" &&
      now.getTime() - t(c.resolvedAt) >= RESOLVED_RETENTION_DAYS * DAY_MS
    ) {
      delete ledger.cases[id];
    }
  }

  const visible = new Set<string>();
  for (const id of present) {
    if (ledger.cases[id]?.state === "open") visible.add(id);
  }
  return visible;
}

/* ── verbs ────────────────────────────────────────────────────────── */

/**
 * timesSurfaced tracking: call with the ids the rendered board actually
 * SHOWED (post-filter, post-cap). Counter bumps every render; the observation
 * event is bounded to one per case per day.
 */
export function bumpSurfaced(ledger: LedgerState, ids: string[], now: Date): void {
  const nowIso = now.toISOString();
  for (const id of ids) {
    const c = ledger.cases[id];
    if (!c) continue;
    c.timesSurfaced += 1;
    const lastObs = [...c.events].reverse().find((e) => e.type === "observation");
    if (!lastObs || now.getTime() - t(lastObs.at) >= DAY_MS) {
      pushEvent(c, {
        at: nowIso,
        type: "observation",
        body: `surfaced on board (total ${c.timesSurfaced})`,
      });
    }
  }
}

export interface SnoozeInput {
  reason?: string;
  severityAtSnooze?: Severity;
  title?: string;
}

/**
 * The dismiss verb: snooze with an optional reason and a recorded wake
 * condition. Creates the case if the id is unknown (v1 dismiss accepted any
 * id — preserved). until defaults to now + 30d: the TTL fallback.
 */
export function snoozeCase(
  ledger: LedgerState,
  id: string,
  input: SnoozeInput,
  now: Date,
): void {
  const nowIso = now.toISOString();
  const c = ledger.cases[id] ?? newCase(nowIso, input.title);
  ledger.cases[id] = c;
  delete c.resolvedAt;
  c.state = "snoozed";
  c.snooze = {
    until: new Date(now.getTime() + SNOOZE_DEFAULT_DAYS * DAY_MS).toISOString(),
    ...(input.reason !== undefined ? { reason: input.reason } : {}),
    ...(input.severityAtSnooze !== undefined
      ? { severityAtSnooze: input.severityAtSnooze }
      : {}),
  };
  pushEvent(c, {
    at: nowIso,
    type: "action",
    body: `dismissed${input.reason ? `: ${input.reason}` : ""}`,
  });
  pushEvent(c, {
    at: nowIso,
    type: "transition",
    body:
      `${SNOOZED} until ${c.snooze.until}` +
      (input.severityAtSnooze !== undefined
        ? `, wakes if worse than ${input.severityAtSnooze}`
        : ""),
  });
}

/** Resolution by operator/agent action (e.g. complete via CalDAV). */
export function resolveCase(
  ledger: LedgerState,
  id: string,
  cause: string,
  now: Date,
): void {
  const nowIso = now.toISOString();
  const c = ledger.cases[id] ?? newCase(nowIso);
  ledger.cases[id] = c;
  pushEvent(c, { at: nowIso, type: "action", body: cause });
  resolve(c, cause, nowIso);
}

/** Record a human/agent action (e.g. agent dispatch queued) on a case. */
export function recordAction(
  ledger: LedgerState,
  id: string,
  body: string,
  now: Date,
): void {
  const nowIso = now.toISOString();
  const c = ledger.cases[id] ?? newCase(nowIso);
  ledger.cases[id] = c;
  pushEvent(c, { at: nowIso, type: "action", body });
}

/* ── delta view: what changed since `since` ───────────────────────── */

/**
 * The brief's delta view (ledger law 6 — every consumer is a view; alerts on
 * transitions, not state). Classification per case:
 *  - firstSeen inside the window → new;
 *  - latest transition inside the window decides reopened vs resolved;
 *  - a worsened observation inside the window (case not resolved) → worsened.
 */
export function computeDelta(ledger: LedgerState, since: Date): Delta {
  const s = since.getTime();
  const out: Delta = {
    since: since.toISOString(),
    new: [],
    reopened: [],
    worsened: [],
    resolved: [],
  };

  for (const [id, c] of Object.entries(ledger.cases)) {
    const label = c.title ?? id;

    if (t(c.firstSeen) >= s) {
      out.new.push({
        id,
        summary: `${label}${c.lastSeverity ? ` [${c.lastSeverity}]` : ""} — first seen ${c.firstSeen}`,
      });
      continue;
    }

    const inWindow = c.events.filter((e) => t(e.at) >= s);
    const lastTransition = [...inWindow]
      .reverse()
      .find(
        (e) =>
          e.type === "transition" &&
          (e.body.startsWith(REOPENED) || e.body.startsWith(RESOLVED)),
      );

    if (lastTransition?.body.startsWith(REOPENED)) {
      out.reopened.push({
        id,
        summary: `${label} — ${lastTransition.body} (reopened ×${c.timesReopened})`,
      });
    } else if (lastTransition?.body.startsWith(RESOLVED) && c.state === "resolved") {
      out.resolved.push({ id, summary: `${label} — ${lastTransition.body}` });
    }

    if (c.state !== "resolved") {
      const worsened = [...inWindow]
        .reverse()
        .find((e) => e.type === "observation" && e.body.startsWith(WORSENED));
      if (worsened) out.worsened.push({ id, summary: `${label} — ${worsened.body}` });
    }
  }

  return out;
}
