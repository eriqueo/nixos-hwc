/**
 * Rate Audit P0 Validation Tests
 *
 * Verifies all 6 P0 fixes from RATE_AUDIT.md.
 * Self-contained — reads JSON directly, reimplements pricing logic
 * to avoid Vite-only import syntax in source modules.
 *
 * Run: node test/rate-audit.test.js
 */

import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');

const tradeRates = JSON.parse(readFileSync(join(root, 'src/data/tradeRates.json'), 'utf8'));
const catalog = JSON.parse(readFileSync(join(root, 'src/data/catalog.json'), 'utf8'));
const templates = JSON.parse(readFileSync(join(root, 'src/data/templates.json'), 'utf8'));

// ─── Reimplemented pricing logic (mirrors src/engine/pricing.js) ───────────

const MAT_MARKUP = 1.4286;

function tradeRate(trade) {
  const r = tradeRates[trade] ?? tradeRates.planning;
  const cost = Math.round(r.wage * r.burden * 100) / 100;
  return {
    cost,
    price: Math.round(cost * r.markup * 100) / 100,
  };
}

function matPrice(cost) {
  return Math.round(cost * MAT_MARKUP * 100) / 100;
}

// ─── Reimplemented TRADE_RATE_KEY (mirrors src/engine/assembler.js) ────────

const TRADE_RATE_KEY = {
  'admin': 'planning',
  'finish_carpentry': 'trimwork',
  'finish carpentry': 'trimwork',
  'tile': 'tiling',
  'waterproofing': 'waterproofing',
  'protection': 'planning',
  'sitework': 'demo',
  'concrete': 'framing',
  'decking': 'framing',
  'stairs': 'framing',
  'railing': 'framing',
};

function tradeRateKey(itemName) {
  const trade = (itemName.split(' | ')[1] || '').toLowerCase();
  return TRADE_RATE_KEY[trade] || trade.replace(/ /g, '_').replace(/&/g, '');
}

// ─── Minimal condition evaluator (for tub demo test) ───────────────────────
// Handles: ident == "str", ident > num, expr OR expr, expr AND expr

function evalCond(expr, state) {
  expr = expr.trim();

  // Handle OR (lowest precedence)
  const orParts = splitLogical(expr, ' OR ');
  if (orParts.length > 1) return orParts.some(p => evalCond(p, state));

  // Handle AND
  const andParts = splitLogical(expr, ' AND ');
  if (andParts.length > 1) return andParts.every(p => evalCond(p, state));

  // Comparison: ident op value
  const cmpMatch = expr.match(/^(\w+)\s*(==|!=|>|<|>=|<=)\s*(.+)$/);
  if (cmpMatch) {
    const [, key, op, rawVal] = cmpMatch;
    const stateVal = state[key];
    const val = rawVal.replace(/^"|"$/g, '');
    const numVal = Number(val);
    const sVal = String(stateVal ?? '');
    const nVal = Number(stateVal ?? 0);

    switch (op) {
      case '==': return sVal === val;
      case '!=': return sVal !== val;
      case '>':  return nVal > numVal;
      case '<':  return nVal < numVal;
      case '>=': return nVal >= numVal;
      case '<=': return nVal <= numVal;
    }
  }

  // Bare ident — truthy check
  return !!state[expr];
}

function splitLogical(expr, delim) {
  // Naive split — works for our simple conditions
  const parts = [];
  let depth = 0, start = 0;
  for (let i = 0; i <= expr.length - delim.length; i++) {
    if (expr[i] === '(') depth++;
    else if (expr[i] === ')') depth--;
    else if (depth === 0 && expr.substring(i, i + delim.length) === delim) {
      parts.push(expr.substring(start, i));
      start = i + delim.length;
      i = start - 1;
    }
  }
  parts.push(expr.substring(start));
  return parts.length > 1 ? parts : [expr];
}

// ─── Test runner ───────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;
const failures = [];

function assert(condition, msg) {
  if (condition) {
    passed++;
    console.log(`  ✓ ${msg}`);
  } else {
    failed++;
    failures.push(msg);
    console.log(`  ✗ ${msg}`);
  }
}

function assertClose(actual, expected, tolerance, msg) {
  const diff = Math.abs(actual - expected);
  if (diff <= tolerance) {
    passed++;
    console.log(`  ✓ ${msg} (${actual} ≈ ${expected})`);
  } else {
    failed++;
    const full = `${msg} — got ${actual}, expected ${expected} ±${tolerance}`;
    failures.push(full);
    console.log(`  ✗ ${full}`);
  }
}

// ─── Calculator reference rates (source of truth) ──────────────────────────

const CALC_RATES = {
  admin:            { cost: 47.25, price: 94.50 },
  demo:             { cost: 35.00, price: 70.00 },
  drywall:          { cost: 47.25, price: 94.50 },
  electrical:       { cost: 60.75, price: 106.31 },
  finish_carpentry: { cost: 51.30, price: 94.91 },
  framing:          { cost: 51.30, price: 94.91 },
  painting:         { cost: 47.25, price: 94.50 },
  plumbing:         { cost: 56.70, price: 120.00 },
  tile:             { cost: 60.75, price: 100.00 },
};

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

console.log('\n══ P0 Fix #1: finish_carpentry → trimwork mapping ══');
{
  // Verify the assembler source has the correct mapping
  const asmSrc = readFileSync(join(root, 'src/engine/assembler.js'), 'utf8');
  assert(
    asmSrc.includes("'finish_carpentry': 'trimwork'"),
    'assembler.js maps finish_carpentry to trimwork'
  );
  assert(
    asmSrc.includes("'finish carpentry': 'trimwork'"),
    'assembler.js maps "finish carpentry" (space) to trimwork'
  );

  // Verify trimwork rate produces calculator-matching price
  const r = tradeRate('trimwork');
  assertClose(r.cost, CALC_RATES.finish_carpentry.cost, 0.01,
    'trimwork cost matches calculator finish_carpentry cost');
  assertClose(r.price, CALC_RATES.finish_carpentry.price, 0.02,
    'trimwork price matches calculator finish_carpentry price');

  // Verify the rate key function resolves correctly
  const key = tradeRateKey('Labor | Finish Carpentry | Install Vanity');
  assert(key === 'trimwork',
    `tradeRateKey resolves "Finish Carpentry" → trimwork (got: ${key})`);
}

console.log('\n══ P0 Fix #2: Niche tile wasteFactor = 1.0 ══');
{
  const nicheItem = catalog.find(i => i.id === 27);
  assert(nicheItem !== undefined, 'Catalog id:27 exists (Niche Installation)');
  assert(nicheItem.wasteFactor === 1.0,
    `wasteFactor is 1.0 (got: ${nicheItem.wasteFactor})`);
  assert(nicheItem.qtyFormula === 'shower_niches * 4',
    `formula is "shower_niches * 4"`);

  // Simulate qty computation: 1 niche → 4 hrs
  const rawQty = 1 * 4;
  const wastedQty = Math.ceil(rawQty * nicheItem.wasteFactor * 100) / 100;
  assert(wastedQty === 4.0,
    `1 niche → ${wastedQty} hrs (should be 4.0, not 0.4)`);

  // 2 niches → 8 hrs
  const rawQty2 = 2 * 4;
  const wastedQty2 = Math.ceil(rawQty2 * nicheItem.wasteFactor * 100) / 100;
  assert(wastedQty2 === 8.0,
    `2 niches → ${wastedQty2} hrs (should be 8.0)`);
}

console.log('\n══ P0 Fix #3: Tub demo fires for tub-to-shower ══');
{
  const tubDemoItem = catalog.find(i => i.id === 1215);
  assert(tubDemoItem !== undefined, 'Catalog id:1215 exists (Bathtub Surround demo)');

  const cond = tubDemoItem.conditionTrigger;

  // Tub-to-shower: removing existing tub, not installing new one
  assert(
    evalCond(cond, { new_tub: 'no', has_existing_tub: 'yes', demo_scope: 'full_gut' }),
    'Fires for tub-to-shower (has_existing_tub=yes, new_tub=no)'
  );

  // New tub install
  assert(
    evalCond(cond, { new_tub: 'yes', demo_scope: 'full_gut' }),
    'Fires for new tub install (new_tub=yes)'
  );

  // Shower-only gut — no tub at all
  assert(
    !evalCond(cond, { new_tub: 'no', demo_scope: 'full_gut' }),
    'Does NOT fire for shower-only gut (no tub involved)'
  );

  // Template 4 has has_existing_tub
  const tpl4 = templates.find(t => t.id === 4);
  assert(tpl4.state.has_existing_tub === 'yes',
    'Template 4 (Tub-to-Shower) state includes has_existing_tub="yes"');

  // Template 2 (has tub + installing new) also has it
  const tpl2 = templates.find(t => t.id === 2);
  assert(tpl2.state.has_existing_tub === 'yes',
    'Template 2 (Medium Gut + Tub) state includes has_existing_tub="yes"');

  // Template 1 (shower-only) does NOT have it
  const tpl1 = templates.find(t => t.id === 1);
  assert(!tpl1.state.has_existing_tub,
    'Template 1 (Standard Medium Gut, shower-only) lacks has_existing_tub');

  // Template 3 (small refresh) does NOT have it
  const tpl3 = templates.find(t => t.id === 3);
  assert(!tpl3.state.has_existing_tub,
    'Template 3 (Small Refresh) lacks has_existing_tub');
}

console.log('\n══ P0 Fix #4: Demo rate = $70/hr ══');
{
  const r = tradeRate('demo');
  assertClose(r.cost, CALC_RATES.demo.cost, 0.01,
    `demo cost = $${r.cost} (target: $${CALC_RATES.demo.cost})`);
  assertClose(r.price, CALC_RATES.demo.price, 0.01,
    `demo price = $${r.price} (target: $${CALC_RATES.demo.price})`);
  assert(tradeRates.demo.burden === 1.0,
    `demo burden = ${tradeRates.demo.burden} (no burden for demo labor)`);
  assert(tradeRates.demo.wage === 35.0,
    `demo wage = $${tradeRates.demo.wage} (unchanged)`);
}

console.log('\n══ P0 Fix #5: Plumbing rate ≈ $120/hr ══');
{
  const r = tradeRate('plumbing');
  assertClose(r.cost, CALC_RATES.plumbing.cost, 0.01,
    `plumbing cost = $${r.cost} (target: $${CALC_RATES.plumbing.cost})`);
  assertClose(r.price, CALC_RATES.plumbing.price, 0.50,
    `plumbing price = $${r.price} (target: $${CALC_RATES.plumbing.price})`);
}

console.log('\n══ P0 Fix #6: Tile rate ≈ $100/hr ══');
{
  const rTiling = tradeRate('tiling');
  assertClose(rTiling.cost, CALC_RATES.tile.cost, 0.01,
    `tiling cost = $${rTiling.cost} (target: $${CALC_RATES.tile.cost})`);
  assertClose(rTiling.price, CALC_RATES.tile.price, 0.50,
    `tiling price = $${rTiling.price} (target: $${CALC_RATES.tile.price})`);

  const rTile = tradeRate('tile');
  assertClose(rTile.price, CALC_RATES.tile.price, 0.50,
    `tile (direct key) price = $${rTile.price} (target: $${CALC_RATES.tile.price})`);
}

console.log('\n══ Regression: Unchanged trades still match calculator ══');
{
  const unchanged = ['admin', 'drywall', 'electrical', 'framing', 'painting'];
  for (const trade of unchanged) {
    const key = TRADE_RATE_KEY[trade] || trade;
    const r = tradeRate(key);
    const expected = CALC_RATES[trade];
    assertClose(r.cost, expected.cost, 0.01, `${trade} cost = $${r.cost}`);
    assertClose(r.price, expected.price, 0.02, `${trade} price = $${r.price}`);
  }
}

console.log('\n══ Regression: Material markup unchanged ══');
{
  assertClose(MAT_MARKUP, 1.4286, 0.001, `MAT_MARKUP = ${MAT_MARKUP}`);
  assertClose(matPrice(100), 142.86, 0.01, 'matPrice($100) = $142.86');
  assertClose(matPrice(350), 500.01, 0.01, 'matPrice($350) = $500.01');
}

// ─── Summary ───────────────────────────────────────────────────────────────

console.log('\n' + '═'.repeat(60));
if (failed === 0) {
  console.log(`ALL ${passed} TESTS PASSED`);
} else {
  console.log(`${passed} passed, ${failed} FAILED`);
  console.log('\nFailures:');
  failures.forEach(f => console.log(`  • ${f}`));
}
console.log('═'.repeat(60) + '\n');

process.exit(failed > 0 ? 1 : 0);
