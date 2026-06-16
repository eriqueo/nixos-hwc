/**
 * Validated data-load boundary.
 *
 * Every engine module that needs catalog / tradeRates / parameters / jtMappings
 * imports from here, never from src/data/*.json directly. The JSON files are
 * parsed through their Zod schemas exactly once at module-load time; a schema
 * failure throws a SchemaValidationError naming the file and the JSON path,
 * so the engine never sees malformed data.
 */
import {
  CatalogSchema,
  TradeRatesSchema,
  ParametersSchema,
  JtMappingsSchema,
  TemplatesSchema,
} from './schemas.js';
import { SchemaValidationError } from '../errors/index.js';
import rawCatalog from '../data/catalog.json' with { type: 'json' };
import rawTradeRates from '../data/tradeRates.json' with { type: 'json' };
import rawParameters from '../data/parameters.json' with { type: 'json' };
import rawJtMappings from '../data/jtMappings.json' with { type: 'json' };
import rawTemplates from '../data/templates.json' with { type: 'json' };

/**
 * Parse raw JSON through a Zod schema; on failure throw a
 * SchemaValidationError whose message names the file and the first failing
 * path so a human reviewing the log can jump straight to the bad row.
 */
export function parseDataFile(schema, raw, file) {
  const result = schema.safeParse(raw);
  if (!result.success) {
    const first = result.error.issues[0];
    const path = first.path.length ? first.path.join('.') : '<root>';
    throw new SchemaValidationError(
      `Schema validation failed for ${file} at ${path}: ${first.message}`,
      { file, path, issues: result.error.issues },
    );
  }
  return result.data;
}

export const catalog = parseDataFile(CatalogSchema, rawCatalog, 'catalog.json');
export const tradeRates = parseDataFile(TradeRatesSchema, rawTradeRates, 'tradeRates.json');
export const parameters = parseDataFile(ParametersSchema, rawParameters, 'parameters.json');
export const jtMappings = parseDataFile(JtMappingsSchema, rawJtMappings, 'jtMappings.json');
export const templates = parseDataFile(TemplatesSchema, rawTemplates, 'templates.json');
