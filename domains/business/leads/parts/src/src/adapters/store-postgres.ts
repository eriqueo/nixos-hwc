/**
 * Postgres-backed LeadStore writing to hwc.leads in the hwc database
 * on hwc-server. Schema: parts/migrations/001-canonical-lead-extensions.sql.
 *
 * Connection: pool via `pg`. DSN comes from config; Unix-socket peer
 * auth as eric is the expected production form (DSN like
 * `postgresql:///hwc`). Pool size kept small (max = 10) because lead
 * volume is low and the connection itself is cheap on a local socket.
 *
 * Writes denormalise the contact fields onto top-level columns for
 * cheap filtering/sorting; per-source fields stay in payload JSONB.
 * Idempotent: `id` is PK; ON CONFLICT DO NOTHING. Replaying the same
 * Lead.id is a no-op.
 *
 * Note: hwc.calculator_leads (the existing 21-row table) is NOT
 * touched by this adapter. That table belongs to the legacy n8n
 * workflow until Phase 2.6 cutover.
 */

import pg from "pg";
import type {
  LeadStore,
  SaveResult,
  RecentQuery,
  JtIdUpdate,
} from "../ports/store.js";
import type {
  Lead,
  LeadStatus,
  LeadPayload,
} from "../core/types.js";
import type { Report } from "../core/report.js";
import type { Logger } from "../ports/log.js";

export interface PostgresLeadStoreOpts {
  readonly dsn: string;
  readonly log: Logger;
}

interface LeadRow {
  id: string;
  source: string;
  status: string;
  payload: unknown;
  received_at: string;
  jt_account_id?: string | null;
  jt_location_id?: string | null;
  jt_contact_id?: string | null;
  jt_job_id?: string | null;
}

function asLeadStatus(s: string): LeadStatus {
  switch (s) {
    case "received":
    case "validated":
    case "pending_jt":
    case "complete":
    case "failed":
      return s;
    default:
      return "validated";
  }
}

function rowToLead(row: LeadRow): Lead {
  const payload = row.payload as LeadPayload;
  const jt: { -readonly [K in keyof Lead["jt"]]: Lead["jt"][K] } = {};
  if (row.jt_account_id)  jt.accountId  = row.jt_account_id;
  if (row.jt_location_id) jt.locationId = row.jt_location_id;
  if (row.jt_contact_id)  jt.contactId  = row.jt_contact_id;
  if (row.jt_job_id)      jt.jobId      = row.jt_job_id;
  return {
    id: row.id,
    payload,
    receivedAt: row.received_at,
    status: asLeadStatus(row.status),
    jt,
  };
}

const INSERT_SQL = `
  INSERT INTO hwc.leads (
    id, source, status, payload, received_at,
    contact_name, contact_email, contact_phone, contact_notes
  ) VALUES (
    $1::uuid, $2, $3, $4::jsonb, $5::timestamptz,
    $6, $7, $8, $9
  )
  ON CONFLICT (id) DO NOTHING
  RETURNING id
`;

const INSERT_REPORT_SQL = `
  INSERT INTO hwc.reports (report_id, lead_id, payload, template_id)
  VALUES ($1, $2::uuid, $3::jsonb, $4)
  ON CONFLICT (report_id) DO NOTHING
`;

const SELECT_BY_ID_SQL = `
  SELECT id::text AS id, source, status, payload, received_at::text AS received_at,
         jt_account_id, jt_location_id, jt_contact_id, jt_job_id
  FROM hwc.leads
  WHERE id = $1::uuid
`;

export function makePostgresLeadStore(opts: PostgresLeadStoreOpts): LeadStore {
  const pool = new pg.Pool({ connectionString: opts.dsn, max: 10 });

  pool.on("error", (err: Error) => {
    opts.log.error("postgres pool error", { err: err.message });
  });

  return {
    async save(lead: Lead, report?: Report): Promise<SaveResult> {
      const contact = lead.payload.contact;
      const leadParams = [
        lead.id,                          // $1  id
        lead.payload.source,              // $2  source
        lead.status,                      // $3  status
        JSON.stringify(lead.payload),     // $4  payload
        lead.receivedAt,                  // $5  received_at
        contact.name,                     // $6  contact_name
        contact.email,                    // $7  contact_email
        contact.phone ?? null,            // $8  contact_phone
        contact.notes ?? null,            // $9  contact_notes
      ];

      // Fast path: no report → single statement, no tx ceremony.
      if (!report) {
        const result = await pool.query<{ id: string }>(INSERT_SQL, leadParams);
        return { inserted: result.rowCount !== 0 };
      }

      // Slow path: lead + report in one transaction. Both succeed or
      // both roll back; no orphan reports possible from a partial crash.
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const leadRes = await client.query<{ id: string }>(INSERT_SQL, leadParams);
        await client.query(INSERT_REPORT_SQL, [
          report.id,                        // $1  report_id
          report.leadId,                    // $2  lead_id
          JSON.stringify(report.payload),   // $3  payload
          report.templateId,                // $4  template_id
        ]);
        await client.query("COMMIT");
        return { inserted: leadRes.rowCount !== 0 };
      } catch (err) {
        try { await client.query("ROLLBACK"); } catch { /* swallowed — primary error is what matters */ }
        throw err;
      } finally {
        client.release();
      }
    },

    async byId(leadId: string): Promise<Lead | undefined> {
      const result = await pool.query<LeadRow>(SELECT_BY_ID_SQL, [leadId]);
      if (result.rows.length === 0) return undefined;
      const row = result.rows[0];
      if (!row) return undefined;
      return rowToLead(row);
    },

    async recent(query: RecentQuery): Promise<readonly Lead[]> {
      const limit = Math.min(query.limit ?? 50, 500);
      const conds: string[] = [];
      const params: Array<string | number> = [];
      if (query.source) {
        params.push(query.source);
        conds.push(`source = $${params.length}`);
      }
      if (query.status) {
        params.push(query.status);
        conds.push(`status = $${params.length}`);
      }
      params.push(limit);
      const limitParam = `$${params.length}`;
      const whereClause = conds.length > 0 ? `WHERE ${conds.join(" AND ")}` : "";
      const sql = `
        SELECT id::text AS id, source, status, payload, received_at::text AS received_at,
         jt_account_id, jt_location_id, jt_contact_id, jt_job_id
        FROM hwc.leads
        ${whereClause}
        ORDER BY received_at DESC
        LIMIT ${limitParam}
      `;
      const result = await pool.query<LeadRow>(sql, params);
      return result.rows.map(rowToLead);
    },

    async updateJtIds(leadId: string, ids: JtIdUpdate, status: LeadStatus): Promise<void> {
      // Build dynamic SET clause from the non-undefined keys. status +
      // jt_synced_at always written; jt_* only when present so a
      // partial-completion call doesn't clobber a later success.
      const sets: string[] = ["status = $2", "jt_synced_at = now()"];
      const params: Array<string | null> = [leadId, status];
      const push = (col: string, val: string | undefined): void => {
        if (val === undefined) return;
        params.push(val);
        sets.push(`${col} = $${params.length}`);
      };
      push("jt_account_id",  ids.accountId);
      push("jt_location_id", ids.locationId);
      push("jt_contact_id",  ids.contactId);
      push("jt_job_id",      ids.jobId);

      const sql = `UPDATE hwc.leads SET ${sets.join(", ")} WHERE id = $1::uuid`;
      await pool.query(sql, params);
    },

    async markNotified(leadId: string): Promise<void> {
      await pool.query(`UPDATE hwc.leads SET notify_sent_at = now() WHERE id = $1::uuid`, [leadId]);
    },

    async markEmailSent(leadId: string): Promise<void> {
      await pool.query(`UPDATE hwc.leads SET email_sent_at = now() WHERE id = $1::uuid`, [leadId]);
    },

    async close(): Promise<void> {
      await pool.end();
    },
  };
}
