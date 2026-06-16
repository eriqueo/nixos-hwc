/**
 * Golden-master parity oracle for the estimator engine.
 *
 * Runs the LIVE engine (src/engine/assembler.js + pricing.js + geometry.js,
 * loaded unmodified via a JSON import-attribute hook) against all 8 templates
 * in src/data/templates.json and diffs the output against the golden
 * snapshots in test/golden/<template>.json.
 *
 * Unlike test_comparison.mjs (which reimplements the engine inline and always
 * exits 0 on engine drift), this runner exits NON-ZERO on any diff. It is the
 * gate for every estimator refactor step.
 *
 * Usage:
 *   node test/golden-master.test.js            # verify against snapshots
 *   node test/golden-master.test.js --update   # (re)capture snapshots
 *   node test/golden-master.test.js --perturb  # self-test: perturb one number
 *                                              # in-memory; MUST go red
 */
import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { register } from 'node:module';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const goldenDir = join(__dirname, 'golden');

// Register tsx so `node` (not just `tsx`) can resolve the engine's `.ts`
// modules written `.js`-style. Engine data files load via contracts/data with
// native `with { type: 'json' }`, so the JSON hook is no longer required —
// kept registered for backward compat with any external test runner.
const { register: registerTsx } = await import('tsx/esm/api');
registerTsx();
register(new URL('./json-import-hook.mjs', import.meta.url));

const { assemble, computeTotals } = await import('../src/engine/assembler.js');
const { enrichState } = await import('../src/engine/geometry.js');

const templates = JSON.parse(readFileSync(join(root, 'src/data/templates.json'), 'utf8'));

const UPDATE = process.argv.includes('--update');
const PERTURB = process.argv.includes('--perturb');

// Numeric rounding tolerance (matches test_comparison.mjs item tolerance).
const TOL = 0.01;

// Fields compared per line item. _usedDefault/_catalogId/_ruleId are
// engine-internal provenance, not estimate output — excluded so refactors
// may change internals freely.
const ITEM_FIELDS = ['name', 'group', 'code', 'type', 'unit', 'qty', 'uc', 'up', 'extC', 'extP', 'trade', 'wasteFactor'];

function slugify(name) {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function snapshotItem(item) {
  const out = {};
  for (const f of ITEM_FIELDS) out[f] = item[f] ?? null;
  return out;
}

function runTemplate(tmpl) {
  const state = typeof tmpl.state === 'string' ? JSON.parse(tmpl.state) : tmpl.state;
  const enriched = enrichState(state);
  const items = assemble(enriched, tmpl.project_type);
  const t = computeTotals(items);
  return {
    template: tmpl.name,
    projectType: tmpl.project_type,
    items: items.map(snapshotItem),
    totals: {
      items: t.items,
      laborHrs: Math.round(t.laborHrs * 100) / 100,
      cost: Math.round(t.cost * 100) / 100,
      price: Math.round(t.price * 100) / 100,
    },
  };
}

function diffSnapshots(golden, actual) {
  const diffs = [];
  if (golden.items.length !== actual.items.length) {
    diffs.push(`item count: golden=${golden.items.length} actual=${actual.items.length}`);
  }
  const n = Math.min(golden.items.length, actual.items.length);
  for (let i = 0; i < n; i++) {
    const g = golden.items[i];
    const a = actual.items[i];
    for (const f of ITEM_FIELDS) {
      const gv = g[f], av = a[f];
      if (typeof gv === 'number' && typeof av === 'number') {
        if (Math.abs(gv - av) > TOL) diffs.push(`[${i}] ${g.name} .${f}: golden=${gv} actual=${av}`);
      } else if (gv !== av) {
        diffs.push(`[${i}] ${g.name} .${f}: golden=${JSON.stringify(gv)} actual=${JSON.stringify(av)}`);
      }
    }
  }
  for (const f of ['items', 'laborHrs', 'cost', 'price']) {
    if (Math.abs(golden.totals[f] - actual.totals[f]) > TOL) {
      diffs.push(`totals.${f}: golden=${golden.totals[f]} actual=${actual.totals[f]}`);
    }
  }
  return diffs;
}

// ── Main ────────────────────────────────────────────────────────────────────

if (templates.length !== 8) {
  console.error(`Expected 8 templates, found ${templates.length} — refusing to run.`);
  process.exit(1);
}

if (UPDATE) {
  mkdirSync(goldenDir, { recursive: true });
  for (const tmpl of templates) {
    const snap = runTemplate(tmpl);
    const file = join(goldenDir, `${slugify(tmpl.name)}.json`);
    writeFileSync(file, JSON.stringify(snap, null, 2) + '\n');
    console.log(`captured ${file} (${snap.items.length} items, $${snap.totals.price.toFixed(2)})`);
  }
  console.log(`\n${templates.length} golden snapshots written to ${goldenDir}`);
  process.exit(0);
}

let passed = 0, failed = 0;
for (const tmpl of templates) {
  const file = join(goldenDir, `${slugify(tmpl.name)}.json`);
  let golden;
  try {
    golden = JSON.parse(readFileSync(file, 'utf8'));
  } catch (e) {
    console.log(`FAIL | ${tmpl.name} — missing/unreadable snapshot ${file}: ${e.message}`);
    failed++;
    continue;
  }
  const actual = runTemplate(tmpl);

  if (PERTURB && tmpl === templates[0]) {
    // Self-test: nudge one number in-memory; the oracle MUST catch it.
    actual.items[0].qty += 1;
    actual.totals.price += 99.99;
  }

  const diffs = diffSnapshots(golden, actual);
  if (diffs.length === 0) {
    console.log(`PASS | ${tmpl.name} (${tmpl.project_type}) — ${actual.items.length} items, $${actual.totals.price.toFixed(2)}`);
    passed++;
  } else {
    console.log(`FAIL | ${tmpl.name} (${tmpl.project_type}) — ${diffs.length} diff(s):`);
    diffs.slice(0, 20).forEach(d => console.log(`    ${d}`));
    if (diffs.length > 20) console.log(`    ... and ${diffs.length - 20} more`);
    failed++;
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
