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

export interface SaveResult {
  /** True when a NEW row was written; false when this person already had a case. */
  readonly inserted: boolean;
  /** SERIAL row id from hwc.calculator_leads (only present for inserted=true). */
  readonly rowId?: number;
  /**
   * The case this submission belongs to (D33). Equals `lead.id` on an insert;
   * on a duplicate it is the id of the EXISTING case, and callers must use it
   * for every downstream effect. Using `lead.id` instead would attach the
   * report, JT graph and notification to a row that was never written.
   */
  readonly leadId: string;
  /** The existing case's source + last submission time — only when !inserted. */
  readonly existing?: {
    readonly source: string;
    readonly receivedAt: string;
  };
}

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
