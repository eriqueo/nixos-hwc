/**
 * JtClient port — outbound interface for JobTread Pave API.
 *
 * Phase 2.4 adapter (jt-jobtread.ts) speaks Pave-over-HTTPS to
 * https://api.jobtread.com/pave. A future test adapter would
 * implement the same interface without touching the network.
 *
 * The `createGraph` method is idempotent over the partial state in
 * existingIds: it runs only the steps that haven't been completed.
 * Failures along the way are returned in the result so the caller
 * can persist whatever IDs DID get assigned and surface partial
 * progress to the operator.
 */

import type { Lead } from "../core/types.js";

export interface JtIds {
  readonly accountId?: string;
  readonly locationId?: string;
  readonly contactId?: string;
  readonly jobId?: string;
  readonly commentId?: string;
}

export interface JtGraphResult {
  /** The IDs that exist after this call — union of incoming + newly created. */
  readonly ids: JtIds;
  /** Did EVERY step complete? false → partial progress; check `failedAt`. */
  readonly complete: boolean;
  /** Name of the step that failed (when complete = false). */
  readonly failedAt?: "account" | "location" | "contact" | "job" | "comment";
  /** Human-readable failure reason. */
  readonly error?: string;
  /** True when the failure was a network/timeout (retry-worthy). */
  readonly retryable?: boolean;
}

export interface JtClient {
  /**
   * Run the JT account → location → contact → job → comment chain,
   * skipping any step whose target id is already present in
   * existingIds. Returns the union of pre-existing and newly created
   * IDs even on partial failure.
   */
  createGraph(lead: Lead, existingIds: JtIds): Promise<JtGraphResult>;
}
