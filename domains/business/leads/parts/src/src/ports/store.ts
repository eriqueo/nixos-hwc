/**
 * LeadStore port — outbound persistence interface for canonical Lead
 * records. Adapter today is PostgresLeadStore writing to
 * hwc.calculator_leads in heartwood_business; an InMemoryLeadStore
 * would be trivial for tests.
 *
 * The Phase 2.3 contract: idempotent `save` keyed by Lead.id (UUID
 * UNIQUE in the DB), `byId` lookup, paged `recent` for the MCP and
 * audit views.
 */

import type { Lead, LeadStatus } from "../core/types.js";
import type { Report } from "../core/report.js";

/**
 * What a capture did, as a tagged union (D33).
 *
 * Was `{ inserted: boolean; existing?: {...} }`, which let
 * `{ inserted: true, existing: {...} }` be constructed — meaningless — and,
 * worse, quietly permitted "neither": no fingerprint match AND a no-op insert.
 * Callers read that as "fresh lead" and re-sent the acknowledgment. Modelling
 * the outcomes as variants means a new one breaks every consumer that forgot
 * it instead of falling through a boolean.
 *
 * `leadId` is on both arms because it is what every downstream effect must
 * address: on `matched` it is the EXISTING case, and using the submitted
 * `lead.id` there would attach the report, JT graph and notification to a row
 * that was never written.
 */
export type SaveResult =
  | {
      readonly kind: "inserted";
      readonly leadId: string;
      /** SERIAL row id from hwc.calculator_leads. */
      readonly rowId?: number;
    }
  | {
      readonly kind: "matched";
      readonly leadId: string;
      /** The case this collapsed into: its source and last submission time. */
      readonly existing: {
        readonly source: string;
        readonly receivedAt: string;
      };
    };

export interface RecentQuery {
  readonly limit?: number;
  readonly source?: "contact" | "calculator" | "appointment";
  readonly status?: LeadStatus;
}

export interface JtIdUpdate {
  readonly accountId?: string;
  readonly locationId?: string;
  readonly contactId?: string;
  readonly jobId?: string;
}

export interface LeadStore {
  /**
   * Assert the store satisfies the D33 case-identity contract. Called once at
   * boot; throwing here must stop the service rather than degrade it.
   */
  verifySchema(): Promise<void>;

  /**
   * Idempotent insert. ON CONFLICT (lead_id) DO NOTHING.
   *
   * When `report` is provided, both rows are written in a single
   * transaction — Lead + Report succeed together or roll back together.
   * No orphan reports (a report with a non-existent lead) or orphan
   * "calculator submissions with no report row" can result from a
   * partial-write crash.
   */
  save(lead: Lead, report?: Report): Promise<SaveResult>;
  /** Look up by Lead.id (UUID). */
  byId(leadId: string): Promise<Lead | undefined>;
  /** Most-recent-first paged view, with optional source/status filters. */
  recent(query: RecentQuery): Promise<readonly Lead[]>;
  /** Set JT IDs + jt_synced_at. Only non-null fields are written. */
  updateJtIds(leadId: string, ids: JtIdUpdate, status: LeadStatus): Promise<void>;
  /** Stamp notify_sent_at = now(). */
  markNotified(leadId: string): Promise<void>;
  /** Stamp email_sent_at = now(). */
  markEmailSent(leadId: string): Promise<void>;
  /** Release pooled connections. */
  close(): Promise<void>;
}
