/**
 * Zod schemas for every data file the engine reads.
 *
 * These are the trust boundary: anything that crosses from src/data/*.json
 * into the engine is parsed through one of these schemas first. A failure
 * names the file and the JSON path; the engine never sees malformed data.
 */
import { z } from 'zod';

// ── catalog.json — assembly rules joined to catalog items ──────────────────
export const CatalogRuleSchema = z.object({
  id: z.number(),
  ruleId: z.number(),
  name: z.string(),
  group: z.string(),
  code: z.string(),
  type: z.string(),
  unit: z.string(),
  unitAbbr: z.string(),
  defaultQty: z.number(),
  unitCost: z.number().nullable(),
  unitPrice: z.number().nullable(),
  laborWage: z.number().nullable(),
  laborBurden: z.number().nullable(),
  wasteFactor: z.number(),
  productionRate: z.number().nullable(),
  qtyDriverKey: z.string().nullable(),
  qtyFormula: z.string().nullable(),
  conditionTrigger: z.string(),
  sortOrder: z.number(),
  projectType: z.string(),
  notes: z.string(),
});
export const CatalogSchema = z.array(CatalogRuleSchema);

// ── tradeRates.json — trade name → wage/burden/markup ──────────────────────
export const TradeRateSchema = z.object({
  wage: z.number(),
  burden: z.number(),
  markup: z.number(),
});
export const TradeRatesSchema = z.record(z.string(), TradeRateSchema);

// ── templates.json — array of saved project state snapshots ────────────────
export const TemplateSchema = z.object({
  id: z.number(),
  name: z.string(),
  project_type: z.string(),
  description: z.string().nullable().optional(),
  state: z.union([z.record(z.string(), z.unknown()), z.string()]),
  created_at: z.string().nullable().optional(),
  updated_at: z.string().nullable().optional(),
});
export const TemplatesSchema = z.array(TemplateSchema);

// ── jtMappings.json — JT id lookups for codes, types, units ────────────────
export const JtMappingsSchema = z.object({
  codes: z.record(z.string(), z.string()),
  types: z.record(z.string(), z.string()),
  units: z.record(z.string(), z.string()),
});

// ── parameters.json — JT parameter definitions consumed by buildParameters ─
export const NumericParamSchema = z.object({
  name: z.string(),
  default: z.number(),
  label: z.string().optional(),
  section: z.string().optional(),
});
export const FormulaParamSchema = z.object({
  name: z.string(),
  formula: z.string(),
  label: z.string().optional(),
});
export const PicklistParamSchema = z.object({
  name: z.string(),
  options: z.array(z.string()),
  default: z.string(),
  label: z.string().optional(),
});
export const ParametersSchema = z.object({
  numeric: z.array(NumericParamSchema),
  formula: z.array(FormulaParamSchema),
  picklist: z.array(PicklistParamSchema),
  deck_numeric: z.array(NumericParamSchema).optional(),
  deck_picklist: z.array(PicklistParamSchema).optional(),
});

// ── Inferred types — engine consumes these instead of hand-written shapes ──
export type CatalogRule = z.infer<typeof CatalogRuleSchema>;
export type Catalog = z.infer<typeof CatalogSchema>;
export type TradeRate = z.infer<typeof TradeRateSchema>;
export type TradeRates = z.infer<typeof TradeRatesSchema>;
export type Template = z.infer<typeof TemplateSchema>;
export type Templates = z.infer<typeof TemplatesSchema>;
export type JtMappings = z.infer<typeof JtMappingsSchema>;
export type NumericParam = z.infer<typeof NumericParamSchema>;
export type FormulaParam = z.infer<typeof FormulaParamSchema>;
export type PicklistParam = z.infer<typeof PicklistParamSchema>;
export type Parameters = z.infer<typeof ParametersSchema>;
