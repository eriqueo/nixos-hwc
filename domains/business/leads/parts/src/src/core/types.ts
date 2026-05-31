/**
 * Core domain types — placeholder for Phase 2.2.
 *
 * Phase 2.2 will introduce:
 *   - Lead (the canonical entity, FK-aligned with the existing
 *     hwc.calculator_leads Postgres table)
 *   - LeadSource discriminated union ("contact" | "calculator" | "appointment")
 *   - ProjectType discriminated union (bathroom / kitchen / deck / addition)
 *   - LeadEstimate (low / high range for calc-driven leads)
 *   - Pure functions: priorityFor(lead), summarizeLead(lead)
 *
 * Phase 2.1 only needs LeadSource so /health can report which sources
 * the service is configured to accept (today: none — POST /leads
 * returns 501 until 2.2).
 */

export type LeadSource = "contact" | "calculator" | "appointment";

/**
 * Per-channel delivery result aliasing the Phase 1 shape. Re-declared
 * here rather than imported so hwc-leads remains source-decoupled
 * from hwc-notify (services talk over HTTP, not source).
 */
export interface NotifyResult {
  readonly notificationId: string;
  readonly attempted: number;
  readonly succeeded: number;
  readonly failed: number;
}
