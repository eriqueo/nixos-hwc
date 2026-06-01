/**
 * Report domain types.
 *
 * A Report is the customer-facing artifact of a calculator submission:
 * a sanitised view of the lead's calc selections + estimate that the
 * customer can revisit at https://iheartwoodcraft.com/report/<id>.
 *
 * Reports are derived from Leads; they exist only when source =
 * "calculator" AND the inbound payload carried a reportId. Phase 4.3's
 * GET /api/reports/<id> reads from this shape.
 *
 * Sanitisation rule: NO contact PII beyond firstName, NO attribution,
 * NO full email/phone/notes. The lead row keeps all of that; the
 * report intentionally doesn't.
 */

export interface ReportPayload {
  /** Calculator slug — bathroom / deck / ... */
  readonly calculator: string;
  /** Greeting target only — first token of contact.name. Never the full name. */
  readonly firstName: string;
  /** Per-calculator selections (bathroom_size, fixtures, deck_height, ...). */
  readonly projectState: Readonly<Record<string, unknown>>;
  /** Estimate range — present when the calc derived one. */
  readonly estimate?: { readonly low: number; readonly high: number };
}

export interface Report {
  readonly id: string;                 // public report_id slug
  readonly leadId: string;             // FK to Lead.id
  readonly payload: ReportPayload;
  readonly templateId: string;
  readonly viewedAt: readonly string[];
  readonly revokedAt?: string;
  readonly createdAt: string;
}
