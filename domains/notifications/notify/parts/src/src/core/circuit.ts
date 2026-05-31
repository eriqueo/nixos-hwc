/**
 * Per-channel circuit breaker.
 *
 * Tracks consecutive failures per channel id. After N consecutive
 * failures the circuit OPENs and subsequent attempts are skipped for
 * a cool-down window. When the window expires the next attempt moves
 * the channel to HALF-OPEN — one try, success closes the circuit,
 * failure re-opens it for another cool-down.
 *
 * State is in-memory only. A restart resets every circuit to CLOSED;
 * acceptable because the alerting system itself is the canary — if
 * notifications dry up after a restart, the operator notices.
 *
 * `now` is injected so tests don't have to wait wall-clock seconds.
 */

export type CircuitState = "closed" | "open" | "half-open";

export interface CircuitStatus {
  readonly channelId: string;
  readonly state: CircuitState;
  readonly consecutiveFailures: number;
  readonly openUntil: number | null;
  readonly lastFailureAt: number | null;
  readonly lastSuccessAt: number | null;
}

export interface CircuitOpts {
  /** Consecutive failures before the circuit opens. */
  readonly failureThreshold: number;
  /** Milliseconds to stay open before attempting half-open. */
  readonly cooldownMs: number;
}

interface MutableStatus {
  channelId: string;
  state: CircuitState;
  consecutiveFailures: number;
  openUntil: number | null;
  lastFailureAt: number | null;
  lastSuccessAt: number | null;
}

export class CircuitBreaker {
  private readonly states = new Map<string, MutableStatus>();
  private readonly opts: CircuitOpts;

  constructor(opts: CircuitOpts) {
    this.opts = opts;
  }

  private getOrCreate(channelId: string): MutableStatus {
    let s = this.states.get(channelId);
    if (!s) {
      s = {
        channelId,
        state: "closed",
        consecutiveFailures: 0,
        openUntil: null,
        lastFailureAt: null,
        lastSuccessAt: null,
      };
      this.states.set(channelId, s);
    }
    return s;
  }

  /**
   * Returns true if a send attempt should proceed, false if the
   * circuit is open and the channel must be skipped. May mutate state
   * (open → half-open transition when cool-down expires).
   */
  shouldAttempt(channelId: string, now: number): boolean {
    const s = this.getOrCreate(channelId);
    if (s.state === "closed") return true;
    if (s.state === "half-open") return true;
    // state === "open"
    if (s.openUntil !== null && now >= s.openUntil) {
      s.state = "half-open";
      return true;
    }
    return false;
  }

  recordSuccess(channelId: string, now: number): void {
    const s = this.getOrCreate(channelId);
    s.state = "closed";
    s.consecutiveFailures = 0;
    s.openUntil = null;
    s.lastSuccessAt = now;
  }

  recordFailure(channelId: string, now: number): void {
    const s = this.getOrCreate(channelId);
    s.consecutiveFailures += 1;
    s.lastFailureAt = now;
    // Half-open + failure → straight back to open with a fresh cool-down.
    if (s.state === "half-open" || s.consecutiveFailures >= this.opts.failureThreshold) {
      s.state = "open";
      s.openUntil = now + this.opts.cooldownMs;
    }
  }

  status(): CircuitStatus[] {
    return [...this.states.values()].map((s) => ({
      channelId: s.channelId,
      state: s.state,
      consecutiveFailures: s.consecutiveFailures,
      openUntil: s.openUntil,
      lastFailureAt: s.lastFailureAt,
      lastSuccessAt: s.lastSuccessAt,
    }));
  }
}

/** Sentinel message in DeliveryResult.message when the breaker skipped. */
export const CIRCUIT_OPEN_MESSAGE = "circuit_open";
