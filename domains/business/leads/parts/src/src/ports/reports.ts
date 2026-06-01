/**
 * ReportStore port — outbound persistence interface for Report records.
 *
 * The adapter today is PostgresReportStore writing to hwc.reports in
 * the heartwood_business database. Lead.save accepts an optional
 * report parameter for transactional Lead + Report writes; the
 * dedicated methods here handle read paths and lifecycle updates
 * (view tracking, revoke).
 */

import type { Report } from "../core/report.js";

export interface ReportStore {
  /**
   * Look up a live report by its public id. Returns undefined when
   * the report doesn't exist; callers that need to distinguish
   * not-found from revoked should check Report.revokedAt themselves.
   */
  byId(reportId: string): Promise<Report | undefined>;

  /**
   * Append now() to viewed_at. Idempotent in the loose sense — every
   * call appends an entry. Phase 4.3's GET handler invokes this once
   * per uncached fetch.
   */
  recordView(reportId: string): Promise<void>;

  /**
   * Soft-delete a report. After this call, byId still returns the row
   * but with revokedAt set; the HTTP handler returns 410 Gone.
   */
  revoke(reportId: string): Promise<void>;

  /** Release pooled connections. */
  close(): Promise<void>;
}
