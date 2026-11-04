import { test } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import type { Logger } from '../ports/log.js';
import { makePostgresLeadStore } from '../adapters/store-postgres.js';
import { makePostgresReportStore } from '../adapters/store-reports-postgres.js';

// Run against an isolated Postgres cluster (created by the package checkPhase).
// Poisoned view fields make an unnecessary projection fail in the real engine.
test('scalar lead reads and report views avoid unused large fields', { skip: !process.env.PGHOST }, async () => {
  const pool = new pg.Pool();
  const dsn = 'postgresql:///postgres';
  const log: Logger = { info() {}, warn() {}, error() {}, debug() {}, child: () => log };
  const leads = makePostgresLeadStore({ dsn, log });
  const reports = makePostgresReportStore({ dsn, log });
  try {
    await pool.query(`
      CREATE SCHEMA hwc;
      CREATE FUNCTION hwc.forbidden_payload() RETURNS jsonb LANGUAGE plpgsql STABLE AS
        $$ BEGIN RAISE EXCEPTION 'unused JSONB payload was read'; END $$;
      CREATE FUNCTION hwc.forbidden_views() RETURNS timestamptz[] LANGUAGE plpgsql STABLE AS
        $$ BEGIN RAISE EXCEPTION 'unused view history was read'; END $$;
      CREATE VIEW hwc.leads AS SELECT
        '00000000-0000-4000-8000-000000000001'::uuid AS id,
        'account'::text AS jt_account_id, NULL::text AS jt_location_id,
        'contact'::text AS jt_contact_id, 'job'::text AS jt_job_id,
        hwc.forbidden_payload() AS payload;
      CREATE VIEW hwc.reports AS SELECT report_id, template_id, created_at, revoked_at,
        CASE WHEN revoked_at IS NOT NULL THEN hwc.forbidden_payload()
          ELSE '{"calculator":"bathroom","firstName":"Test","projectState":{}}'::jsonb END AS payload,
        hwc.forbidden_views() AS viewed_at
      FROM (VALUES
        ('active', 'v1', now(), NULL::timestamptz),
        ('revoked', 'v1', now(), now())
      ) AS r(report_id, template_id, created_at, revoked_at);
    `);
    assert.deepEqual(await leads.jtIds('00000000-0000-4000-8000-000000000001'), {
      accountId: 'account', contactId: 'contact', jobId: 'job',
    });
    assert.equal(await leads.jtIds('00000000-0000-4000-8000-000000000002'), undefined);
    const report = await reports.byId('active');
    assert.deepEqual(report?.payload, { calculator: 'bathroom', firstName: 'Test', projectState: {} });
    assert.equal(Object.hasOwn(report!, 'viewedAt'), false);
    assert.equal(Object.hasOwn(report!, 'leadId'), false);
    const revoked = await reports.byId('revoked');
    assert.ok(revoked?.revokedAt);
    assert.equal(Object.hasOwn(revoked!, 'payload'), false);
    assert.equal(await reports.byId('missing'), undefined);
  } finally {
    await Promise.all([leads.close(), reports.close(), pool.end()]);
  }
});
