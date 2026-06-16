/**
 * Schema rejection tests — every Zod contract MUST reject at least one
 * malformed fixture. Catches drift between data on disk and the engine's
 * expectations at the load boundary.
 *
 * These run the schemas directly (without touching real JSON), so they are
 * independent of golden-master.
 */
import {
  CatalogSchema,
  TradeRatesSchema,
  TemplatesSchema,
  JtMappingsSchema,
  ParametersSchema,
} from '../src/contracts/schemas.js';

const cases = [
  {
    name: 'CatalogSchema rejects row missing required field',
    schema: CatalogSchema,
    bad: [{ id: 1, name: 'x' }],
  },
  {
    name: 'CatalogSchema rejects wrong type (id as string)',
    schema: CatalogSchema,
    bad: [{
      id: 'one', ruleId: 1, name: 'x', group: 'g', code: 'c', type: 'Labor',
      unit: 'u', unitAbbr: 'u', defaultQty: 1, unitCost: null, unitPrice: null,
      laborWage: null, laborBurden: null, wasteFactor: 1, productionRate: null,
      qtyDriverKey: null, qtyFormula: null, conditionTrigger: 'always',
      sortOrder: 1, projectType: 'deck', notes: '',
    }],
  },
  {
    name: 'TradeRatesSchema rejects rate missing burden',
    schema: TradeRatesSchema,
    bad: { framing: { wage: 35, markup: 1.85 } },
  },
  {
    name: 'TradeRatesSchema rejects non-numeric wage',
    schema: TradeRatesSchema,
    bad: { framing: { wage: 'thirty-five', burden: 1.35, markup: 1.85 } },
  },
  {
    name: 'TemplatesSchema rejects array element missing name',
    schema: TemplatesSchema,
    bad: [{ id: 1, project_type: 'bathroom', state: {} }],
  },
  {
    name: 'JtMappingsSchema rejects missing units',
    schema: JtMappingsSchema,
    bad: { codes: {}, types: {} },
  },
  {
    name: 'JtMappingsSchema rejects non-string mapping value',
    schema: JtMappingsSchema,
    bad: { codes: { '0100': 42 }, types: {}, units: {} },
  },
  {
    name: 'ParametersSchema rejects missing numeric array',
    schema: ParametersSchema,
    bad: { formula: [], picklist: [] },
  },
  {
    name: 'ParametersSchema rejects numeric entry with string default',
    schema: ParametersSchema,
    bad: {
      numeric: [{ name: 'x', default: 'wrong' }],
      formula: [],
      picklist: [],
    },
  },
];

let passed = 0, failed = 0;
for (const c of cases) {
  const r = c.schema.safeParse(c.bad);
  if (r.success) {
    console.log(`FAIL | ${c.name} — schema accepted malformed input`);
    failed++;
  } else {
    console.log(`PASS | ${c.name}`);
    passed++;
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
