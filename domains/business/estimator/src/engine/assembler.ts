/**
 * Heartwood Estimate Assembler -- Data-Driven (Three-Layer Architecture)
 *
 * Reads catalog.json (assembly rules joined to catalog items) to assemble
 * estimates from project state.
 */
import { tradeRate, matPrice } from './pricing.js';
import { evaluateFormula, evaluateCondition } from './formulaEngine.js';
import { catalog, parameters } from '../contracts/data.js';
import type { CatalogRule } from '../contracts/schemas.js';
import type { RawState } from './geometry.js';

// Allowance cost keys: allowance name -> state key for unit cost
const ALLOWANCE_COST_KEY: Record<string, string> = {
  'Allowance | Bathtub': 'tub_allowance',
  'Allowance | Shower Trim': 'shower_trim_allowance',
  'Allowance | Toilet': 'toilet_allowance',
  'Allowance | Vanity': 'vanity_allowance',
  'Allowance | Bathroom Accessories': 'accessory_allowance',
};

// Trade name -> tradeRates key mapping
const TRADE_RATE_KEY: Record<string, string> = {
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

function tradeRateKey(itemName: string): string {
  const trade = (itemName.split(' | ')[1] || '').toLowerCase();
  return TRADE_RATE_KEY[trade] || trade.replace(/ /g, '_').replace(/&/g, '');
}

export interface LineItem {
  id: number;
  name: string;
  group: string;
  code: string;
  type: string;
  unit: string;
  qty: number;
  uc: number;
  up: number;
  extC: number;
  extP: number;
  trade: string | null;
  quantityFormula: string | null;
  wasteFactor: number;
  _usedDefault: boolean;
  _catalogId: number | null;
  _ruleId: number | null;
  _source?: string;
  _pickIndex?: number;
  _edited?: boolean;
}

export interface CustomItem {
  name?: string;
  qty?: number;
  cost?: number;
  trade?: string | null;
  group?: string;
  code?: string;
  type?: string;
  unit?: string;
}

export function assemble(state: RawState, projectType: string = 'bathroom'): LineItem[] {
  const applicable = (catalog as CatalogRule[]).filter(item =>
    (item.projectType === projectType || item.projectType === 'general')
    && item.conditionTrigger && item.sortOrder
  );

  const included = applicable.filter(item => {
    if (!item.conditionTrigger || item.conditionTrigger === 'always') return true;
    return evaluateCondition(item.conditionTrigger, state);
  });

  included.sort((a, b) => (a.sortOrder || 500) - (b.sortOrder || 500));

  let id = 0;
  const result: LineItem[] = included.map(item => {
    let qty: number;
    let usedDefault = false;

    if (item.qtyFormula) {
      const v = evaluateFormula(item.qtyFormula, state);
      if (v === null || v === undefined || isNaN(v)) {
        qty = item.defaultQty || 1;
        usedDefault = true;
      } else {
        qty = v;
      }
    } else {
      qty = item.defaultQty || 1;
    }

    const wasteFactor = item.wasteFactor || 1.0;
    qty = Math.ceil(qty * wasteFactor * 100) / 100;

    let uc: number;
    let up: number;
    if (item.type === 'Labor' || item.type === 'Admin') {
      const r = tradeRate(tradeRateKey(item.name));
      uc = r.cost;
      up = r.price;
    } else if (ALLOWANCE_COST_KEY[item.name]) {
      uc = Number(state[ALLOWANCE_COST_KEY[item.name]]) || 0;
      up = matPrice(uc);
    } else if (item.name.startsWith('Allowance |') && item.qtyFormula && !item.unitCost) {
      uc = evaluateFormula(item.qtyFormula, state) || 0;
      up = matPrice(uc);
      qty = 1;
    } else {
      uc = item.unitCost || 0;
      up = item.unitPrice || matPrice(item.unitCost || 0);
    }

    return {
      id: ++id,
      name: item.name,
      group: item.group || '',
      code: item.code,
      type: item.type,
      unit: item.unit || item.unitAbbr || 'Each',
      qty,
      uc, up,
      extC: Math.round(uc * qty * 100) / 100,
      extP: Math.round(up * qty * 100) / 100,
      trade: (item as unknown as { trade?: string | null }).trade ?? null,
      quantityFormula: item.qtyFormula || null,
      wasteFactor,
      _usedDefault: usedDefault,
      _catalogId: item.id,
      _ruleId: item.ruleId || null,
    };
  });

  ((state.custom_items as CustomItem[] | undefined) ?? []).forEach(ci => {
    if (ci.name && (ci.qty ?? 0) > 0) {
      const uc = ci.cost || 0;
      const up = ci.trade ? tradeRate(ci.trade).price : matPrice(uc);
      const qty = ci.qty ?? 0;
      result.push({
        id: ++id,
        name: ci.name,
        group: ci.group ?? 'Additional Items',
        code: ci.code ?? '3100',
        type: ci.type ?? 'Materials',
        unit: ci.unit ?? 'Each',
        qty,
        uc, up,
        extC: Math.round(uc * qty * 100) / 100,
        extP: Math.round(up * qty * 100) / 100,
        trade: ci.trade ?? null,
        quantityFormula: null,
        wasteFactor: 1.0,
        _usedDefault: false,
        _catalogId: null,
        _ruleId: null,
      });
    }
  });

  return result;
}

// -- Geometry (kept here for backward compat -- also in geometry.ts) ----------

export function deriveGeometry(s: RawState) {
  const fl        = s.bathroom_length_ft * s.bathroom_width_ft;
  const perim     = 2 * (s.bathroom_length_ft + s.bathroom_width_ft);
  const showerW   = s.shower_wall_1_width_ft + s.shower_wall_2_width_ft
                  + s.shower_wall_3_width_ft + s.shower_wall_4_width_ft;
  const wallTile  = showerW * s.shower_wall_height_ft;
  const panTile   = s.shower_pan_width_ft * s.shower_pan_length_ft;
  const curbTile  = Math.ceil(
    (s.shower_curb_height_in * 2) / 12 * s.shower_curb_length_ft
    + (s.shower_curb_width_in * 2) / 12 * s.shower_curb_length_ft
  );
  const accentTile = showerW * 1.25;
  const wallArea   = perim * s.wall_height_ft;
  const ceilArea   = fl;
  const paintableWalls = Math.max(0, wallArea - wallTile);
  const paintSqft  = wallArea;
  return { fl, perim, wallTile, panTile, curbTile, accentTile, paintSqft, wallArea, ceilArea, paintableWalls, showerW };
}

export function deriveDeckGeometry(s: RawState) {
  const deckSqft   = s.deck_length_ft * s.deck_width_ft;
  const perimeter  = 2 * (s.deck_length_ft + s.deck_width_ft);
  const joistCount = Math.ceil(s.deck_length_ft / (s.joist_spacing_in / 12)) + 1;
  const railingLf  = s.railing_lf || 0;
  const stairCount = s.stair_tread_count || 0;
  const footingCount = Math.max(4, Math.ceil(deckSqft / 36));
  const deckingLf  = Math.ceil(deckSqft / 0.5);
  return { deckSqft, perimeter, joistCount, railingLf, stairCount, footingCount, deckingLf };
}

// -- JT parameter builders (for webhook push) ---------------------------------

export function buildParameters(s: RawState) {
  const params: Array<Record<string, unknown>> = [];
  for (const p of parameters.numeric) {
    params.push({ name: p.name, value: s[p.name] ?? p.default });
  }
  for (const p of parameters.formula) {
    params.push({ name: p.name, formula: p.formula });
  }
  for (const p of parameters.picklist) {
    params.push({ name: p.name, options: p.options, value: s[p.name] ?? p.default });
  }
  return params;
}

export function buildDeckParameters(s: RawState) {
  return [
    { name: 'd_length', value: s.deck_length_ft ?? 12 },
    { name: 'd_width', value: s.deck_width_ft ?? 8 },
    { name: 'd_height_ft', value: s.deck_height_ft ?? 3 },
    { name: 'joist_spacing', value: s.joist_spacing_in ?? 16 },
    { name: 'railing_lf', value: s.railing_lf ?? 0 },
    { name: 'stair_tread_count', value: s.stair_tread_count ?? 0 },
    { name: 'waste_factor', value: 1.1 },
    { name: 'decking', options: ['pt','cedar','redwood','composite_mid','composite_premium'], value: s.decking_material ?? 'pt' },
    { name: 'railings', options: ['no','wood','composite','metal_cable','glass'], value: s.railing_type ?? 'no' },
    { name: 'project_scope', options: ['new_build','full_rebuild','partial_rebuild','repair'], value: s.project_scope ?? 'new_build' },
  ];
}

// -- Utilities ----------------------------------------------------------------

export function applyEdits(
  catalog: LineItem[],
  overrides: Record<number, number>,
  removed: Record<number, boolean>,
): LineItem[] {
  return catalog
    .filter(i => !removed[i.id])
    .map(i => {
      const qty = overrides[i.id] !== undefined ? overrides[i.id] : i.qty;
      return {
        ...i, qty,
        extC: Math.round(i.uc * qty * 100) / 100,
        extP: Math.round(i.up * qty * 100) / 100,
        _edited: overrides[i.id] !== undefined,
      };
    });
}

export interface Totals {
  cost: number;
  price: number;
  items: number;
  laborHrs: number;
  margin: number;
}

export function computeTotals(estimate: LineItem[]): Totals {
  let cost = 0, price = 0, items = 0, laborHrs = 0;
  estimate.forEach(i => {
    cost  += i.extC;
    price += i.extP;
    items += 1;
    if (i.type === 'Labor') laborHrs += i.qty;
  });
  return {
    cost, price, items, laborHrs,
    margin: price > 0 ? ((price - cost) / price * 100) : 0,
  };
}

export function groupEstimate(estimate: LineItem[]): Record<string, LineItem[]> {
  const g: Record<string, LineItem[]> = {};
  estimate.forEach(i => {
    if (!g[i.group]) g[i.group] = [];
    g[i.group].push(i);
  });
  return g;
}
