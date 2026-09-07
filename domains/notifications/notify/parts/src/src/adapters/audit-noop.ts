/**
 * No-op AuditLog — for dev / disabled state. record() is a no-op,
 * recent() always returns []. close() is idempotent.
 *
 * The transition half is no-op too: `reserveTransition` returns null, which the
 * port defines as "no decision" rather than "suppress", so wiring this adapter
 * can never make a notification disappear.
 */

import type {
  AuditPort,
  AuditRecord,
  CleanupCounts,
  RecentNotification,
} from "../ports/audit.js";
import type { TransitionDecision, TransitionState } from "../core/transition.js";

export function makeNoopAuditLog(): AuditPort {
  return {
    record(_rec: AuditRecord): void {},
    recent(): RecentNotification[] { return []; },
    reserveTransition(): TransitionDecision | null { return null; },
    settleTransition(): void {},
    getTransition(): TransitionState | null { return null; },
    cleanup(): CleanupCounts {
      return { notifications: 0, deliveries: 0, transitions: 0 };
    },
    close(): void {},
  };
}
