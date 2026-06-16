/**
 * Validated data-load boundary.
 *
 * Every engine module that needs catalog / tradeRates / parameters / jtMappings
 * imports from here, never from src/data/*.json directly. The JSON files are
 * parsed through their Zod schemas exactly once at module-load time; a schema
 * failure throws a SchemaValidationError naming the file and the JSON path,
 * so the engine never sees malformed data.
 */
import type { ZodType } from 'zod';
import {
  CatalogSchema,
  TradeRatesSchema,
  ParametersSchema,
  JtMappingsSchema,
  TemplatesSchema,
  type Catalog,
  type TradeRates,
  type Parameters,
  type JtMappings,
  type Templates,
} from './schemas.js';
import { SchemaValidationError, type SchemaIssue } from '../errors/index.js';
import rawCatalog from '../data/catalog.json' with { type: 'json' };
import rawTradeRates from '../data/tradeRates.json' with { type: 'json' };
import rawParameters from '../data/parameters.json' with { type: 'json' };
import rawJtMappings from '../data/jtMappings.json' with { type: 'json' };
import rawTemplates from '../data/templates.json' with { type: 'json' };

export function parseDataFile<T>(schema: ZodType<T>, raw: unknown, file: string): T {
  const result = schema.safeParse(raw);
  if (!result.success) {
    const first = result.error.issues[0];
    const path = first.path.length ? first.path.join('.') : '<root>';
    throw new SchemaValidationError(
      `Schema validation failed for ${file} at ${path}: ${first.message}`,
      { file, path, issues: result.error.issues as unknown as SchemaIssue[] },
    );
  }
  return result.data;
}

export const catalog: Catalog = parseDataFile(CatalogSchema, rawCatalog, 'catalog.json');
export const tradeRates: TradeRates = parseDataFile(TradeRatesSchema, rawTradeRates, 'tradeRates.json');
export const parameters: Parameters = parseDataFile(ParametersSchema, rawParameters, 'parameters.json');
export const jtMappings: JtMappings = parseDataFile(JtMappingsSchema, rawJtMappings, 'jtMappings.json');
export const templates: Templates = parseDataFile(TemplatesSchema, rawTemplates, 'templates.json');
