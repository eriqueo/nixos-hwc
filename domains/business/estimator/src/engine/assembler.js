/**
 * Heartwood Estimate Assembler -- Data-Driven (Three-Layer Architecture)
 *
 * Reads catalog.json (assembly rules joined to catalog items) to assemble
 * estimates from project state.
 *
 * catalog.json contains one entry per assembly rule, each linking to a
 * catalog item with pricing + JT metadata. The assembler:
 *   1. Filters rules by projectType + conditionTrigger
 *   2. Evaluates qty formulas against project state
 *   3. Applies waste factor to quantity
 *   4. Computes pricing from trade rates or catalog values
 *   5. Returns line items (snapshots, independent of source data)
 *
 * No React dependencies -- can be tested independently.
 */
import { tradeRate, matPrice } from './pricing.js';
import { evaluateFormula, evaluateCondition } from './formulaEngine.js';
import catalog from '../data/catalog.json' with { type: 'json' };
import parameters from '../data/parameters.json' with { type: 'json' };

// Allowance cost keys: allowance name -> state key for unit cost
const ALLOWANCE_COST_KEY = {
  'Allowance | Bathtub': 'tub_allowance',
  'Allowance | Shower Trim': 'shower_trim_allowance',
  'Allowance | Toilet': 'toilet_allowance',
  'Allowance | Vanity': 'vanity_allowance',
  'Allowance | Bathroom Accessories': 'accessory_allowance',
};

// Trade name -> tradeRates key mapping
const TRADE_RATE_KEY = {
  'admin': 'planning',
  'finish_carpentry': 'cabinetry',
  'finish carpentry': 'cabinetry',
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

/**
 * Assemble an estimate from assembly rules.
 *
 * @param {Object} state       -- enriched project state (run through enrichState first)
 * @param {string} projectType -- 'bathroom', 'deck', 'kitchen', etc.
 * @returns {Array} line items
 */
export function assemble(state, projectType = 'bathroom') {
  // 1. Filter to rules for this project type (or 'general' = all types)
  //    Each entry in catalog is an assembly rule with catalog item data
  const applicable = catalog.filter(item =>
    (item.projectType === projectType || item.projectType === 'general')
    && item.conditionTrigger && item.sortOrder
  );

  // 2. Evaluate conditions -- which rules apply to this project state?
  const included = applicable.filter(item => {
    if (!item.conditionTrigger || item.conditionTrigger === 'always') return true;
    return evaluateCondition(item.conditionTrigger, state);
  });

  // 3. Sort by sortOrder
  included.sort((a, b) => (a.sortOrder || 500) - (b.sortOrder || 500));

  // 4. Compute qty and pricing for each item
  let id = 0;
  const result = included.map(item => {
    let qty;
    let usedDefault = false;

    if (item.qtyFormula) {
      qty = evaluateFormula(item.qtyFormula, state);
      if (qty === null || qty === undefined || isNaN(qty)) {
        qty = item.defaultQty || 1;
        usedDefault = true;
      }
    } else {
      qty = item.defaultQty || 1;
    }

    // Apply waste factor to quantity (baked in, stored for traceability)
    const wasteFactor = item.wasteFactor || 1.0;
    qty = Math.ceil(qty * wasteFactor * 100) / 100;

    // Pricing
    let uc, up;
    if (item.type === 'Labor' || item.type === 'Admin') {
      const r = tradeRate(tradeRateKey(item.name));
      uc = r.cost;
      up = r.price;
    } else if (ALLOWANCE_COST_KEY[item.name]) {
      uc = state[ALLOWANCE_COST_KEY[item.name]] || 0;
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
      trade: item.trade || null,
      quantityFormula: item.qtyFormula || null,
      wasteFactor,
      _usedDefault: usedDefault,
      _catalogId: item.id,
      _ruleId: item.ruleId || null,
    };
  });

  // 5. Append custom line items
  (state.custom_items ?? []).forEach(ci => {
    if (ci.name && ci.qty > 0) {
      const uc = ci.cost || 0;
      const up = ci.trade ? tradeRate(ci.trade).price : matPrice(uc);
      result.push({
        id: ++id,
        name: ci.name,
        group: ci.group ?? 'Additional Items',
        code: ci.code ?? '3100',
        type: ci.type ?? 'Materials',
        unit: ci.unit ?? 'Each',
        qty: ci.qty,
        uc, up,
        extC: Math.round(uc * ci.qty * 100) / 100,
        extP: Math.round(up * ci.qty * 100) / 100,
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

// -- Geometry (kept here for backward compat -- also in geometry.js) ----------

export function deriveGeometry(s) {
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
  const paintSqft  = perim * s.wall_height_ft;
  return { fl, perim, wallTile, panTile, curbTile, accentTile, paintSqft, showerW };
}

export function deriveDeckGeometry(s) {
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

export function buildParameters(s) {
  const params = [];
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

export function buildDeckParameters(s) {
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

export function applyEdits(catalog, overrides, removed) {
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

export function computeTotals(estimate) {
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

export function groupEstimate(estimate) {
  const g = {};
  estimate.forEach(i => {
    if (!g[i.group]) g[i.group] = [];
    g[i.group].push(i);
  });
  return g;
}
