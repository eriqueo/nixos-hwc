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
} from "../ports/store.js";
import type {
  Lead,
  LeadStatus,
  LeadPayload,
} from "../core/types.js";
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
  return {
    id: row.id,
    payload,
    receivedAt: row.received_at,
    status: asLeadStatus(row.status),
    jt: {},
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

const SELECT_BY_ID_SQL = `
  SELECT id::text AS id, source, status, payload, received_at::text AS received_at
  FROM hwc.leads
  WHERE id = $1::uuid
`;

export function makePostgresLeadStore(opts: PostgresLeadStoreOpts): LeadStore {
  const pool = new pg.Pool({ connectionString: opts.dsn, max: 10 });

  pool.on("error", (err: Error) => {
    opts.log.error("postgres pool error", { err: err.message });
  });

  return {
    async save(lead: Lead): Promise<SaveResult> {
      const contact = lead.payload.contact;
      const result = await pool.query<{ id: string }>(INSERT_SQL, [
        lead.id,                          // $1  id
        lead.payload.source,              // $2  source
        lead.status,                      // $3  status
        JSON.stringify(lead.payload),     // $4  payload
        lead.receivedAt,                  // $5  received_at
        contact.name,                     // $6  contact_name
        contact.email,                    // $7  contact_email
        contact.phone ?? null,            // $8  contact_phone
        contact.notes ?? null,            // $9  contact_notes
      ]);
      if (result.rowCount === 0) {
        return { inserted: false };
      }
      return { inserted: true };
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
        SELECT id::text AS id, source, status, payload, received_at::text AS received_at
        FROM hwc.leads
        ${whereClause}
        ORDER BY received_at DESC
        LIMIT ${limitParam}
      `;
      const result = await pool.query<LeadRow>(sql, params);
      return result.rows.map(rowToLead);
    },

    async close(): Promise<void> {
      await pool.end();
    },
  };
}
