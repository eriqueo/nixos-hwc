/**
 * Structured-error tests — every coded failure class fires the right code
 * from the right throw site.
 */
import { register } from 'node:module';
const { register: registerTsx } = await import('tsx/esm/api');
registerTsx();
register(new URL('./json-import-hook.mjs', import.meta.url));

const { SchemaValidationError, UnknownFormulaTokenError, MissingTradeRateError, JtPushError } =
  await import('../src/errors/index.js');
const { parseFormulaStrict } = await import('../src/engine/formulaEngine.js');
const { tradeRateStrict, tradeRate } = await import('../src/engine/pricing.js');
const { pushEstimateToJt } = await import('../src/engine/jtPush.js');
const { parseDataFile } = await import('../src/contracts/data.js');
const { CatalogSchema } = await import('../src/contracts/schemas.js');

let passed = 0, failed = 0;
function check(name, expectedCode, fn) {
  try {
    const out = fn();
    if (out && typeof out.then === 'function') {
      return out.then(
        () => { console.log(`FAIL | ${name} — expected throw, got resolve`); failed++; },
        (e) => {
          if (e && e.code === expectedCode) { console.log(`PASS | ${name}`); passed++; }
          else { console.log(`FAIL | ${name} — got code=${e && e.code} (${e && e.name})`); failed++; }
        },
      );
    }
    console.log(`FAIL | ${name} — expected throw, got return`);
    failed++;
  } catch (e) {
    if (e && e.code === expectedCode) { console.log(`PASS | ${name}`); passed++; }
    else { console.log(`FAIL | ${name} — got code=${e && e.code} (${e && e.name})`); failed++; }
  }
}

// SCHEMA_VALIDATION — data-load boundary surfaces validation error with file+path
check('SchemaValidationError on malformed catalog', 'SCHEMA_VALIDATION', () => {
  parseDataFile(CatalogSchema, [{ id: 1, name: 'missing fields' }], 'catalog.json');
});

// And it carries the file + path so a stale export is identifiable
try {
  parseDataFile(CatalogSchema, [{ id: 1, name: 'x' }], 'catalog.json');
} catch (e) {
  if (e instanceof SchemaValidationError && e.file === 'catalog.json' && e.path.startsWith('0.')) {
    console.log('PASS | SchemaValidationError carries file + path'); passed++;
  } else {
    console.log(`FAIL | SchemaValidationError carries file + path — file=${e.file} path=${e.path}`); failed++;
  }
}

// UNKNOWN_FORMULA_TOKEN — formula parser fires on unexpected input
check('UnknownFormulaTokenError on unbalanced paren', 'UNKNOWN_FORMULA_TOKEN', () => {
  parseFormulaStrict('(1 + 2', {});
});
check('UnknownFormulaTokenError on garbage atom', 'UNKNOWN_FORMULA_TOKEN', () => {
  parseFormulaStrict('1 +', {});
});

// MISSING_TRADE_RATE — pricing.tradeRateStrict
check('MissingTradeRateError on unknown trade', 'MISSING_TRADE_RATE', () => {
  tradeRateStrict('not-a-trade');
});

// Sanity: tradeRate() (permissive) still does not throw on a known trade
if (typeof tradeRate('framing').cost === 'number') {
  console.log('PASS | tradeRate() returns numeric cost for known trade'); passed++;
} else {
  console.log('FAIL | tradeRate() returned non-numeric cost'); failed++;
}

// JT_PUSH_FAILED — boundary helper
await check('JtPushError on missing URL', 'JT_PUSH_FAILED', () =>
  pushEstimateToJt({ url: '', apiKey: 'k', payload: {} }),
);
await check('JtPushError on missing API key', 'JT_PUSH_FAILED', () =>
  pushEstimateToJt({ url: 'http://x', apiKey: '', payload: {} }),
);
await check('JtPushError on HTTP 500', 'JT_PUSH_FAILED', () =>
  pushEstimateToJt({
    url: 'http://x', apiKey: 'k', payload: {},
    fetchImpl: async () => ({ ok: false, status: 500, text: async () => 'boom' }),
  }),
);
await check('JtPushError on network failure', 'JT_PUSH_FAILED', () =>
  pushEstimateToJt({
    url: 'http://x', apiKey: 'k', payload: {},
    fetchImpl: async () => { throw new Error('ECONNREFUSED'); },
  }),
);

// Make sure error classes are also instanceof EstimatorError-friendly
try {
  tradeRateStrict('whoops');
} catch (e) {
  if (e instanceof MissingTradeRateError) {
    console.log('PASS | MissingTradeRateError is instanceof its class'); passed++;
  } else {
    console.log('FAIL | MissingTradeRateError instanceof check'); failed++;
  }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
