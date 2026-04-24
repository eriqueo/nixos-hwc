/**
 * Heartwood Estimate Assembler — Parameter-Driven
 *
 * Pure function: project state → priced line items with JT formula strings.
 * No React dependencies — can be tested independently.
 *
 * Each item carries:
 *   qty             — local preview (JS-computed, for display)
 *   quantityFormula — JT formula string (for push, JT evaluates server-side)
 *
 * {production_rate} and {waste} in formulas are COST ITEM custom fields,
 * resolved by JT per-item. All other {param} refs are job parameters.
 */
import { tradeRate, matPrice } from './pricing.js';
import parameters from '../data/parameters.json';

// ─── Picklist helper ────────────────────────────────────────────────────────
const yn = v => v === 'yes';

// ─── Derived geometry (local preview calculations) ──────────────────────────

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

// ─── Build parameters array for JT push ─────────────────────────────────────

export function buildParameters(s) {
  const params = [];

  // Numeric parameters
  for (const p of parameters.numeric) {
    params.push({ name: p.name, value: s[p.name] ?? p.default });
  }

  // Formula parameters (JT evaluates these from numeric params)
  for (const p of parameters.formula) {
    params.push({ name: p.name, formula: p.formula });
  }

  // Picklist parameters
  for (const p of parameters.picklist) {
    params.push({
      name: p.name,
      options: p.options,
      value: s[p.name] ?? p.default,
    });
  }

  return params;
}

// ─── Item builder ─────────────────────────────────────────────────────────────

export function buildCatalog(s) {
  const { fl, perim, wallTile, panTile, curbTile, accentTile, paintSqft } = deriveGeometry(s);
  const niches = parseInt(s.shower_niches) || 0;
  const items = [];
  let id = 0;

  /**
   * @param {string}      name
   * @param {string}      group
   * @param {string}      code
   * @param {string}      type      — Labor | Materials | Other
   * @param {string}      unit
   * @param {number}      qty       — local preview quantity
   * @param {number}      cost      — unit cost (materials) or 0 (labor)
   * @param {string|null} trade     — trade key for labor pricing
   * @param {boolean}     trigger   — false = skip item entirely
   * @param {string|null} formula   — JT quantityFormula string
   */
  const add = (name, group, code, type, unit, qty, cost, trade, trigger, formula) => {
    if (!trigger) return;
    let uc, up;
    if (type === 'Labor') {
      const r = tradeRate(trade);
      uc = r.cost;
      up = r.price;
    } else {
      uc = cost;
      up = matPrice(cost);
    }
    items.push({
      id: ++id,
      name, group, code, type, unit,
      qty:  Math.ceil(qty * 100) / 100,
      uc, up,
      extC: Math.round(uc * qty * 100) / 100,
      extP: Math.round(up * qty * 100) / 100,
      trade,
      quantityFormula: formula || null,
    });
  };

  // ── PRECONSTRUCTION ────────────────────────────────────────────────────────
  add('Admin | Planning | Site Walkthrough', 'Preconstruction', '0100', 'Labor', 'Hours',
    2, 0, 'planning', true, null);

  // ── DEMO ───────────────────────────────────────────────────────────────────
  add('Labor | Demo | Install Floor Protection', 'Demo > Labor', '0200', 'Labor', 'Hours',
    3, 0, 'demo', true, null);

  add('Labor | Demo | Floor Tile', 'Demo > Labor', '0200', 'Labor', 'Hours',
    Math.ceil(0.15 * fl), 0, 'demo',
    s.demo_scope === 'shower_and_floors' || s.demo_scope === 'full_gut',
    'ceil({production_rate}*{bathroom_floor_sqft})');

  add('Labor | Demo | Shower Surround', 'Demo > Labor', '0200', 'Labor', 'Hours',
    4, 0, 'demo', yn(s.has_shower_tile), null);

  add('Labor | Demo | Bathtub Surround', 'Demo > Labor', '0200', 'Labor', 'Hours',
    6, 0, 'demo', yn(s.new_tub) && s.demo_scope === 'full_gut', null);

  add('Material | Protection | Floor Protection Roll', 'Demo > Materials', '0100', 'Materials', 'Each',
    1, 35, null, true, null);
  add('Material | Protection | Sheeting Tape', 'Demo > Materials', '0100', 'Materials', 'Each',
    2, 13, null, true, null);
  add('Material | Protection | Dust Control Sheeting', 'Demo > Materials', '0100', 'Materials', 'Each',
    1, 20, null, true, null);
  add('Material | Protection | Trash Bags', 'Demo > Materials', '0100', 'Materials', 'Each',
    fl > 80 ? 2 : 1, 27, null, true,
    'IF({bathroom_floor_sqft}>80,2,1)');
  add('Material | Demo | Dump Trailer', 'Demo > Materials', '0200', 'Other', 'Each',
    1, 200, null, s.demo_scope === 'shower_and_floors' || s.demo_scope === 'full_gut', null);

  // ── FRAMING ────────────────────────────────────────────────────────────────
  add('Labor | Framing | General', 'Rough Carpentry > Labor', '0600', 'Labor', 'Hours',
    4, 0, 'framing', true, null);
  add('Labor | Framing | Niche Blocking', 'Rough Carpentry > Labor', '0600', 'Labor', 'Hours',
    niches * 2, 0, 'framing', niches > 0,
    '{shower_niches}*2');
  add('Labor | Framing | Install Tub', 'Rough Carpentry > Labor', '0600', 'Labor', 'Hours',
    5, 0, 'framing', yn(s.new_tub), null);
  add('Material | Framing | Screws 3" Exterior 5lb', 'Rough Carpentry > Materials', '3100', 'Materials', 'Each',
    1, 32.98, null, true, null);
  add('Material | Framing | 2x4x8 KD SPF', 'Rough Carpentry > Materials', '0600', 'Materials', 'Each',
    Math.max(2, Math.ceil(perim / 8)), 13, null, true,
    'ceil({bathroom_perimeter_lf}/8)');
  add('Material | Framing | Plywood 3/4" ACX', 'Rough Carpentry > Materials', '0600', 'Materials', 'Each',
    1, 95, null, true, null);

  // ── PLUMBING ───────────────────────────────────────────────────────────────
  if (yn(s.has_shower_tile)) {
    add('Labor | Plumbing | Install Mixer Valve', 'Plumbing > Labor', '1100', 'Labor', 'Hours',
      4, 0, 'plumbing', true, null);
    add('Labor | Plumbing | Install Shower Trim', 'Plumbing > Labor', '1100', 'Labor', 'Hours',
      2, 0, 'plumbing', true, null);
    add('Labor | Plumbing | Run Showerhead Copper', 'Plumbing > Labor', '1100', 'Labor', 'Hours',
      4, 0, 'plumbing', true, null);
    add('Material | Plumbing | Posi-Temp Rough-In Valve', 'Plumbing > Materials', '1100', 'Materials', 'Each',
      1, 135, null, true, null);
    add('Material | Plumbing | 1/2" Copper Pipe', 'Plumbing > Materials', '1100', 'Materials', 'Each',
      2, 8, null, true, null);
    add('Material | Plumbing | Copper Fittings', 'Plumbing > Materials', '1100', 'Materials', 'Lump Sum',
      1, 50, null, true, null);
  }
  if (yn(s.new_tub)) {
    add('Labor | Plumbing | Tub Drain Hookup', 'Plumbing > Labor', '1100', 'Labor', 'Hours',
      4, 0, 'plumbing', true, null);
  }
  add('Labor | Plumbing | Install Toilet', 'Plumbing > Labor', '1100', 'Labor', 'Hours',
    2, 0, 'plumbing', true, null);
  add('Material | Plumbing | PVC Fittings', 'Plumbing > Materials', '1100', 'Materials', 'Each',
    6, 3, null, true, null);

  // ── ELECTRICAL ─────────────────────────────────────────────────────────────
  if (yn(s.new_electrical)) {
    add('Labor | Electrical | General', 'Electrical > Labor', '1000', 'Labor', 'Hours',
      4, 0, 'electrical', true, null);
    add('Material | Electrical | GFCI Outlet', 'Electrical > Materials', '1000', 'Materials', 'Each',
      1, 25, null, true, null);
  }
  if (yn(s.new_fan)) {
    add('Labor | Electrical | Exhaust Fan', 'Electrical > Labor', '1000', 'Labor', 'Hours',
      3, 0, 'electrical', true, null);
  }

  // ── WATERPROOFING ──────────────────────────────────────────────────────────
  if (yn(s.has_shower_tile)) {
    const wpSqft = wallTile + fl * 0.3;
    add('Labor | Waterproofing | Membrane Application', 'Waterproofing > Labor', '1800', 'Labor', 'Hours',
      Math.max(6, Math.ceil(wpSqft * 0.04)), 0, 'waterproofing', true,
      'ceil(({shower_wall_tile_sqft}+{bathroom_floor_sqft}*0.3)*0.04)');
  }

  // ── TILEWORK ───────────────────────────────────────────────────────────────
  // Floor tile
  add('Labor | Tile | Floor Installation', 'Tilework > Floor Tile Labor', '1800', 'Labor', 'Hours',
    Math.max(8, Math.ceil(fl * 0.22)), 0, 'tiling', yn(s.has_floor_tile),
    'ceil({production_rate}*{bathroom_floor_sqft})');

  // Shower tile
  if (yn(s.has_shower_tile)) {
    add('Labor | Tile | Shower Installation', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours',
      Math.max(12, Math.ceil(wallTile * 0.18)), 0, 'tiling', true,
      'ceil({production_rate}*{shower_wall_tile_sqft})');
    add('Labor | Tile | Shower Pan', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours',
      Math.max(4, Math.ceil(panTile * 0.25)), 0, 'tiling', true,
      'ceil({production_rate}*{shower_pan_tile_sqft})');
    add('Labor | Tile | Shower Curb', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours',
      Math.max(2, Math.ceil(curbTile * 0.3)), 0, 'tiling', true,
      'ceil({production_rate}*{shower_curb_tile_sqft})');
    add('Labor | Tile | Niche Installation', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours',
      niches * 4, 0, 'tiling', niches > 0,
      '{shower_niches}*4');
  }

  // Accent tile
  if (yn(s.has_accent_tile) && yn(s.has_shower_tile)) {
    add('Labor | Tile | Accent Band Installation', 'Tilework > Accent Tile Labor', '1800', 'Labor', 'Hours',
      Math.max(4, Math.ceil(accentTile * 0.25)), 0, 'tiling', true,
      'ceil({production_rate}*{shower_accent_tile_sqft})');
  }

  // Tile materials
  add('Material | Tile | Waterproof Backer Board 1/2" 4x8', 'Tilework > Materials', '1800', 'Materials', 'Each',
    Math.max(2, Math.ceil(wallTile / 32)), 98.99, null, yn(s.has_shower_tile),
    'ceil({shower_wall_tile_sqft}/32)');
  add('Material | Tile | Schluter Banding 16\'', 'Tilework > Materials', '1800', 'Materials', 'Each',
    Math.max(1, Math.ceil(perim / 16)), 20.75, null, true,
    'ceil({bathroom_perimeter_lf}/16)');
  add('Material | Tile | Permacolor Grout', 'Tilework > Materials', '1800', 'Materials', 'Each',
    1, 95, null, true, null);
  add('Material | Tile | Schluter 1/4" Aluminum Trim', 'Tilework > Materials', '1800', 'Materials', 'Each',
    Math.max(2, Math.ceil(perim / 8)), 24, null, true,
    'ceil({bathroom_perimeter_lf}/8)');
  add('Material | Tile | Thinset Mortar 50#', 'Tilework > Materials', '1800', 'Materials', 'Each',
    Math.max(2, Math.ceil((fl + wallTile) / 80)), 28.5, null, true,
    'ceil(({bathroom_floor_sqft}+{shower_wall_tile_sqft})/80)');
  add('Material | Tile | Silicone Sealant', 'Tilework > Materials', '1800', 'Materials', 'Each',
    Math.max(2, Math.ceil(perim / 12)), 22, null, true,
    'ceil({bathroom_perimeter_lf}/12)');
  add('Material | Tile | Grout Sealer', 'Tilework > Materials', '1800', 'Materials', 'Each',
    1, 20, null, true, null);

  // ── DRYWALL ────────────────────────────────────────────────────────────────
  const repairSqft = s.bathroom_wall_repair_sqft;
  const sheets = Math.ceil(repairSqft / 32);
  if (repairSqft > 0) {
    add('Labor | Drywall | Remove and Replace', 'Drywall > Labor', '1400', 'Labor', 'Hours',
      Math.ceil(sheets * 1.5), 0, 'drywall', true,
      'ceil({bathroom_wall_repair_sqft}/32*1.5)');
    add('Material | Drywall | Drywall 1/2" 4x8', 'Drywall > Materials', '1400', 'Materials', 'Each',
      Math.max(1, Math.floor(sheets * 0.6)), 20.48, null, true, null);
    add('Material | Drywall | Mold Resistant 1/2" 4x8', 'Drywall > Materials', '1400', 'Materials', 'Each',
      Math.max(1, Math.ceil(sheets * 0.4)), 19.2, null, true, null);
    add('Material | Drywall | Mud 4.5 gal', 'Drywall > Materials', '1400', 'Materials', 'Each',
      1, 15.48, null, true, null);
    add('Material | Drywall | Tape Mesh 500ft', 'Drywall > Materials', '1400', 'Materials', 'Each',
      1, 11.98, null, true, null);
    add('Material | Drywall | Screws 1-5/8" 1lb', 'Drywall > Materials', '1400', 'Materials', 'Each',
      1, 7.98, null, true, null);
  }

  // ── PAINTING ───────────────────────────────────────────────────────────────
  if (yn(s.has_paint)) {
    const paintHrs = paintSqft / 40;
    const paintGal = Math.max(1, Math.ceil(paintSqft / 350));
    add('Labor | Painting | Prep', 'Painting > Labor', '2300', 'Labor', 'Hours',
      Math.max(4, Math.ceil(paintHrs * 0.30)), 0, 'painting', true,
      'ceil({bathroom_wall_paint_sqft}/40*0.30)');
    add('Labor | Painting | Caulking', 'Painting > Labor', '2300', 'Labor', 'Hours',
      Math.max(2, Math.ceil(paintHrs * 0.15)), 0, 'painting', true,
      'ceil({bathroom_wall_paint_sqft}/40*0.15)');
    add('Labor | Painting | Prime Coat', 'Painting > Labor', '2300', 'Labor', 'Hours',
      Math.max(3, Math.ceil(paintHrs * 0.25)), 0, 'painting', true,
      'ceil({bathroom_wall_paint_sqft}/40*0.25)');
    add('Labor | Painting | Finish Coats', 'Painting > Labor', '2300', 'Labor', 'Hours',
      Math.max(4, Math.ceil(paintHrs * 0.50)), 0, 'painting', true,
      'ceil({bathroom_wall_paint_sqft}/40*0.50)');
    add('Material | Painting | BIN Shellac Primer', 'Painting > Materials', '2300', 'Materials', 'Gallons',
      paintGal, 75, null, true,
      'ceil({bathroom_wall_paint_sqft}/350)');
    add('Material | Painting | SW Emerald Urethane Semi Gloss', 'Painting > Materials', '2300', 'Materials', 'Each',
      paintGal, 110, null, true,
      'ceil({bathroom_wall_paint_sqft}/350)');
    add('Material | Painting | Painters Tape Blue', 'Painting > Materials', '2300', 'Materials', 'Each',
      Math.max(2, Math.ceil(perim / 12)), 6.98, null, true,
      'ceil({bathroom_perimeter_lf}/12)');
    add('Material | Painting | Caulking', 'Painting > Materials', '2300', 'Materials', 'Each',
      Math.max(2, Math.ceil(perim / 12)), 11.19, null, true,
      'ceil({bathroom_perimeter_lf}/12)');
  }

  // ── FINISH CARPENTRY ───────────────────────────────────────────────────────
  add('Labor | Finish Carpentry | Install Vanity', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours',
    4, 0, 'cabinetry', yn(s.has_vanity), null);
  add('Labor | Finish Carpentry | General', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours',
    8, 0, 'cabinetry', true, null);
  add('Labor | Finish Carpentry | Mirror Install', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours',
    2, 0, 'cabinetry', yn(s.has_mirror), null);

  // ── ALLOWANCES ─────────────────────────────────────────────────────────────
  add('Allowance | Bathtub', 'Allowances', '2400', 'Materials', 'Lump Sum',
    1, s.tub_allowance, null, yn(s.new_tub), null);
  add('Allowance | Shower Trim', 'Allowances', '1100', 'Materials', 'Lump Sum',
    1, s.shower_trim_allowance, null, yn(s.has_shower_tile), null);
  add('Allowance | Shower Tile', 'Allowances > Tile', '1800', 'Materials', 'Lump Sum',
    1, Math.max(800, Math.round(wallTile * 12)), null, yn(s.has_shower_tile), null);
  add('Allowance | Floor Tile', 'Allowances > Tile', '1800', 'Materials', 'Lump Sum',
    1, Math.max(400, Math.round(fl * 10)), null, yn(s.has_floor_tile), null);
  add('Allowance | Toilet', 'Allowances', '2400', 'Materials', 'Lump Sum',
    1, s.toilet_allowance, null, true, null);
  add('Allowance | Vanity', 'Allowances', '3000', 'Materials', 'Lump Sum',
    1, s.vanity_allowance, null, yn(s.has_vanity), null);
  add('Allowance | Bathroom Accessories', 'Allowances', '3000', 'Materials', 'Lump Sum',
    1, s.accessory_allowance, null, true, null);
  add('Allowance | Electrical', 'Allowances', '1000', 'Materials', 'Lump Sum',
    1, 800, null, yn(s.new_electrical), null);

  // ── CUSTOM LINE ITEMS ──────────────────────────────────────────────────────
  (s.custom_items ?? []).forEach(ci => {
    if (ci.name && ci.qty > 0) {
      add(ci.name, ci.group ?? 'Additional Items', ci.code ?? '3100',
        ci.type ?? 'Materials', ci.unit ?? 'Each', ci.qty, ci.cost ?? 0,
        ci.trade ?? null, true, null);
    }
  });

  return items;
}

/**
 * Apply qty overrides and removals from user edits.
 */
export function applyEdits(catalog, overrides, removed) {
  return catalog
    .filter(i => !removed[i.id])
    .map(i => {
      const qty = overrides[i.id] !== undefined ? overrides[i.id] : i.qty;
      return {
        ...i,
        qty,
        extC: Math.round(i.uc * qty * 100) / 100,
        extP: Math.round(i.up * qty * 100) / 100,
        _edited: overrides[i.id] !== undefined,
      };
    });
}

/**
 * Compute totals from an estimate array.
 */
export function computeTotals(estimate) {
  let cost = 0, price = 0, items = 0, laborHrs = 0;
  estimate.forEach(i => {
    cost     += i.extC;
    price    += i.extP;
    items    += 1;
    if (i.type === 'Labor') laborHrs += i.qty;
  });
  return {
    cost, price, items, laborHrs,
    margin: price > 0 ? ((price - cost) / price * 100) : 0,
  };
}

/**
 * Group estimate items by budget_group_path.
 */
export function groupEstimate(estimate) {
  const g = {};
  estimate.forEach(i => {
    if (!g[i.group]) g[i.group] = [];
    g[i.group].push(i);
  });
  return g;
}
