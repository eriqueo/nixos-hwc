/**
 * No-op AuditLog — for dev / disabled state. record() is a no-op,
 * recent() always returns []. close() is idempotent.
 */

import type { AuditLog, AuditRecord, RecentNotification } from "../ports/audit.js";

export function makeNoopAuditLog(): AuditLog {
  return {
    record(_rec: AuditRecord): void {},
    recent(): RecentNotification[] { return []; },
    close(): void {},
  };
}
