/** Production pricing regressions. RATE_AUDIT.md records May 5 proposals;
 * demo/tile inputs changed in 363decf65 after that audit. The amounts here
 * preserve the current published inputs, without deciding new pricing policy.
 */
import assert from 'node:assert/strict';
import { assemble, deriveGeometry as legacyRoom, deriveDeckGeometry as legacyDeck } from '../src/engine/assembler.js';
import { enrichState, deriveGeometry, deriveDeckGeometry } from '../src/engine/geometry.js';
import { DEFAULT_STATE } from '../src/engine/intake.js';
import { tradeRate, matPrice } from '../src/engine/pricing.js';

const expectedRates = {
  planning: [47.25, 94.50], demo: [47.25, 94.50], drywall: [47.25, 94.50],
  electrical: [60.75, 106.31], trimwork: [51.30, 94.91], framing: [51.30, 94.91],
  painting: [47.25, 94.50], plumbing: [56.70, 120.20],
  tiling: [60.75, 112.39], tile: [60.75, 112.39],
};
for (const [trade, expected] of Object.entries(expectedRates)) {
  const rate = tradeRate(trade);
  assert.deepEqual([rate.cost, rate.price], expected, trade);
}
assert.equal(matPrice(100), 142.86);
assert.equal(matPrice(350), 500.01);
for (const room of [deriveGeometry, legacyRoom]) {
  assert.equal(room({ ...DEFAULT_STATE, bathroom_length_ft: 9.5, bathroom_width_ft: 6 }).fl, 57);
  assert.ok(Number.isNaN(room({ ...DEFAULT_STATE, bathroom_length_ft: null }).fl));
}
for (const deck of [deriveDeckGeometry, legacyDeck]) {
  assert.equal(deck({ ...DEFAULT_STATE, deck_length_ft: 16, deck_width_ft: 12 }).deckSqft, 192);
  assert.ok(Number.isNaN(deck({ ...DEFAULT_STATE, deck_length_ft: null }).deckSqft));
}

const estimate = patch => assemble(enrichState({ ...DEFAULT_STATE, ...patch }), 'bathroom');
const line = (items, name) => {
  const found = items.find(i => i.name === name);
  assert.ok(found, `Missing assembled line: ${name}`);
  return found;
};
const vanity = line(estimate({}), 'Labor | Finish Carpentry | Install Vanity');
assert.deepEqual([vanity.uc, vanity.up], [51.30, 94.91]);
for (const count of [1, 2]) {
  const niche = line(estimate({ shower_niches: String(count) }), 'Labor | Tile | Niche Installation');
  assert.equal(niche.qty, count === 1 ? 4 : 8);
  assert.deepEqual([niche.uc, niche.up], [60.75, 112.39]);
}
const tubName = 'Labor | Demo | Bathtub Surround';
for (const patch of [
  { new_tub: 'no', has_existing_tub: 'yes', demo_scope: 'full_gut' },
  { new_tub: 'yes', has_existing_tub: 'no', demo_scope: 'full_gut' },
]) assert.equal(line(estimate(patch), tubName).qty, 6);
assert.ok(!estimate({ new_tub: 'no', has_existing_tub: 'no', demo_scope: 'full_gut' }).some(i => i.name === tubName));
console.log('PASS production trade rates, finish-carpentry mapping, niche quantities, tub removal and material markup');
