/**
 * Postgres-backed ReportStore writing to hwc.reports in the hwc
 * database on hwc-server. Schema: parts/migrations/002-reports.sql.
 *
 * The INSERT path lives on PostgresLeadStore.save (Lead + Report in a
 * single tx) because that's the only place reports are created — they
 * are derived from leads at the same instant. This adapter handles
 * the read paths and lifecycle updates: GET /api/reports/<id>,
 * view tracking, revoke.
 *
 * Connection: shares the pool style with store-postgres.ts but
 * instantiates its own pool because the public-facing GET endpoint
 * (Phase 4.3) is on a hotter request path and Eric may want to size
 * it independently later. Today both use max=10 on the same DSN.
 */

import pg from "pg";
import type { ReportStore } from "../ports/reports.js";
import type { Report, ReportPayload } from "../core/report.js";
import type { Logger } from "../ports/log.js";

export interface PostgresReportStoreOpts {
  readonly dsn: string;
  readonly log: Logger;
}

interface ReportRow {
  report_id: string;
  lead_id: string;
  payload: unknown;
  template_id: string;
  viewed_at: string[];
  revoked_at: string | null;
  created_at: string;
}

const SELECT_BY_ID_SQL = `
  SELECT report_id, lead_id::text AS lead_id, payload, template_id,
         COALESCE(viewed_at, '{}')::text[] AS viewed_at,
         revoked_at::text AS revoked_at,
         created_at::text AS created_at
  FROM hwc.reports
  WHERE report_id = $1
`;

const RECORD_VIEW_SQL = `
  UPDATE hwc.reports
  SET viewed_at = array_append(viewed_at, now())
  WHERE report_id = $1 AND revoked_at IS NULL
`;

const REVOKE_SQL = `
  UPDATE hwc.reports
  SET revoked_at = now()
  WHERE report_id = $1 AND revoked_at IS NULL
`;

function rowToReport(row: ReportRow): Report {
  return {
    id: row.report_id,
    leadId: row.lead_id,
    payload: row.payload as ReportPayload,
    templateId: row.template_id,
    viewedAt: row.viewed_at,
    ...(row.revoked_at ? { revokedAt: row.revoked_at } : {}),
    createdAt: row.created_at,
  };
}

export function makePostgresReportStore(opts: PostgresReportStoreOpts): ReportStore {
  const pool = new pg.Pool({ connectionString: opts.dsn, max: 10 });

  pool.on("error", (err: Error) => {
    opts.log.error("[reports-store] postgres pool error", { err: err.message });
  });

  return {
    async byId(reportId: string): Promise<Report | undefined> {
      const result = await pool.query<ReportRow>(SELECT_BY_ID_SQL, [reportId]);
      if (result.rows.length === 0) return undefined;
      const row = result.rows[0];
      if (!row) return undefined;
      return rowToReport(row);
    },

    async recordView(reportId: string): Promise<void> {
      await pool.query(RECORD_VIEW_SQL, [reportId]);
    },

    async revoke(reportId: string): Promise<void> {
      await pool.query(REVOKE_SQL, [reportId]);
    },

    async close(): Promise<void> {
      await pool.end();
    },
  };
}
