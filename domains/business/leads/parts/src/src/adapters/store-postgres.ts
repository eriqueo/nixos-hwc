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

/**
 * D33 — resolve the CASE this submission belongs to before writing a row.
 *
 * hwc.lead_fingerprint is defined by hwc-crm's migration 009 and is the single
 * definition of lead identity; calling it here rather than re-deriving
 * lower(email) in TypeScript is the whole point, since a second copy of the
 * normalisation rule is what let one person become two cases in the first
 * place.
 *
 * Excludes archived cases (a returning customer opens a fresh one) and merged
 * ones (superseded — resolving to a merged-away row would hand the caller a
 * case that is no longer live).
 */
const RESOLVE_CASE_SQL = `
  SELECT id::text AS id, source, received_at::text AS received_at
    FROM hwc.leads
   WHERE fingerprint = hwc.lead_fingerprint($1, $2)
     AND fingerprint IS NOT NULL
     AND archived_at IS NULL
     AND merged_into IS NULL
   ORDER BY received_at DESC
   LIMIT 1
`;

const VERIFY_SCHEMA_SQL = `
  SELECT to_regprocedure('hwc.lead_fingerprint(text,text)') IS NOT NULL AS has_fn,
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'hwc' AND table_name = 'leads'
                    AND column_name = 'merged_into') AS has_merged_into
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

/**
 * Resolve-then-write, in one transaction (D33).
 *
 * The old fast path (no report → bare INSERT, no transaction) is gone on
 * purpose: identity resolution and the write have to be atomic, or two
 * simultaneous submissions both read "no case yet" and both insert. Lead
 * volume is a handful a day, so a transaction per capture costs nothing.
 *
 * The report always attaches to the RESOLVED case, never to lead.id — on a
 * duplicate, lead.id names a row that was never written, and a report hung off
 * it would violate the FK or orphan the customer's estimate URL.
 */
async function saveOnce(pool: pg.Pool, lead: Lead, report?: Report): Promise<SaveResult> {
  const contact = lead.payload.contact;
  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const hit = (await client.query<{ id: string; source: string; received_at: string }>(
      RESOLVE_CASE_SQL, [contact.email, contact.phone ?? null])).rows[0];

    let result: SaveResult;
    if (hit) {
      result = {
        kind: "matched",
        leadId: hit.id,
        existing: { source: hit.source, receivedAt: hit.received_at },
      };
    } else {
      const leadRes = await client.query<{ id: string }>(INSERT_SQL, [
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
      if (leadRes.rowCount === 0) {
        // ON CONFLICT (id) fired while no live case matched the fingerprint.
        // lead.id is server-minted per request (schemas/lead.ts buildLead), so
        // this means a uuid4 collision. Refuse rather than invent a third
        // outcome: the old code returned inserted=false here, which callers
        // read as "existing case" and used to skip the customer's email.
        throw new Error(
          `lead ${lead.id} already exists but matched no live case — ` +
          `refusing to guess whether this capture was already acknowledged`);
      }
      result = { kind: "inserted", leadId: lead.id };
    }

    if (report) {
      await client.query(INSERT_REPORT_SQL, [
        report.id,                        // $1  report_id
        result.leadId,                    // $2  lead_id — resolved, not lead.id
        JSON.stringify(report.payload),   // $3  payload
        report.templateId,                // $4  template_id
      ]);
    }

    await client.query("COMMIT");
    return result;
  } catch (err) {
    try { await client.query("ROLLBACK"); } catch { /* swallowed — primary error is what matters */ }
    throw err;
  } finally {
    client.release();
  }
}

export function makePostgresLeadStore(opts: PostgresLeadStoreOpts): LeadStore {
  const pool = new pg.Pool({ connectionString: opts.dsn, max: 10 });

  pool.on("error", (err: Error) => {
    opts.log.error("postgres pool error", { err: err.message });
  });

  return {
    async verifySchema(): Promise<void> {
      // Boot-time dependency check. The fingerprint function and merged_into
      // column ship in hwc-crm's migration 009, which this service does not
      // own and cannot apply. Running without them would not fail loudly — it
      // would quietly resume minting a fresh case per submission, which is
      // exactly the bug D33 exists to close. Refuse to start half-alive.
      const r = await pool.query<{ has_fn: boolean; has_merged_into: boolean }>(
        VERIFY_SCHEMA_SQL);
      const row = r.rows[0];
      if (!row?.has_fn || !row?.has_merged_into) {
        throw new Error(
          "hwc.leads is missing D33 case identity (hwc.lead_fingerprint / " +
          "leads.merged_into). Apply hwc-crm migration 009 before starting " +
          "hwc-leads; starting without it silently re-forks duplicate leads.");
      }
    },

    async save(lead: Lead, report?: Report): Promise<SaveResult> {
      // One retry: a 23505 on the fingerprint index means a concurrent
      // submission created this person's case between our SELECT and INSERT.
      // That is the race the unique index exists to catch, and the correct
      // response is to re-resolve and attach to the winner, not to error.
      try {
        return await saveOnce(pool, lead, report);
      } catch (err) {
        if ((err as { code?: string }).code !== "23505") throw err;
        opts.log.info("lead save lost the fingerprint race; re-resolving", {
          leadId: lead.id,
        });
        return await saveOnce(pool, lead, report);
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
