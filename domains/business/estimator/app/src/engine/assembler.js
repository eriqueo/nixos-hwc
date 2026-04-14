/**
 * Heartwood Estimate Assembler
 *
 * Pure function: project state → priced line items.
 * No React dependencies — can be tested independently.
 *
 * The catalog data (catalog.json) drives item names, codes, types, and units.
 * Trigger evaluation and quantity derivation live here, driven by state.
 */
import { tradeRate, matPrice } from './pricing.js';

// ─── Derived geometry ────────────────────────────────────────────────────────

export function deriveGeometry(s) {
  const fl     = s.room_length * s.room_width;
  const perim  = 2 * (s.room_length + s.room_width);
  const wallTile = s.tile_height > 0 ? perim * s.tile_height : 0;
  return { fl, perim, wallTile };
}

// ─── Item builder ─────────────────────────────────────────────────────────────

/**
 * Build the full catalog of line items for a given project state.
 * Returns an array of priced items.
 */
export function buildCatalog(s) {
  const { fl, perim, wallTile } = deriveGeometry(s);
  const items = [];
  let id = 0;

  const add = (name, group, code, type, unit, qty, cost, trade, trigger) => {
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
    });
  };

  // ── PRECONSTRUCTION ────────────────────────────────────────────────────────
  add('Admin | Planning | Site Walkthrough',  'Preconstruction', '0100', 'Labor',  'Hours', 2, 0, 'planning', true);
  add('Admin | Planning | Remodeling Permit', 'Preconstruction', '0100', 'Other',  'Each',  1, 350, null, s.permit_required);

  // ── DEMO ───────────────────────────────────────────────────────────────────
  if (s.demo_scope !== 'none') {
    add('Labor | Demo | Install Floor Protection', 'Demo > Labor',     '0200', 'Labor',     'Hours', 3, 0, 'demo', true);
    add('Labor | Demo | Floor Tile',              'Demo > Labor',     '0200', 'Labor',     'Hours', Math.max(4, fl * 0.12), 0, 'demo', s.demo_scope === 'full_gut' || s.demo_scope === 'tile_only');
    add('Labor | Demo | Shower Surround',         'Demo > Labor',     '0200', 'Labor',     'Hours', Math.max(4, wallTile * 0.04), 0, 'demo', s.has_shower);
    add('Labor | Demo | Bathtub Surround',        'Demo > Labor',     '0200', 'Labor',     'Hours', 6, 0, 'demo', s.has_tub && s.demo_scope === 'full_gut');
    add('Material | Protection | Floor Protection Roll', 'Demo > Materials', '0100', 'Materials', 'Each', 1,  35,  null, true);
    add('Material | Protection | Sheeting Tape',         'Demo > Materials', '0100', 'Materials', 'Each', 2,  13,  null, true);
    add('Material | Protection | Dust Control Sheeting', 'Demo > Materials', '0100', 'Materials', 'Each', 1,  20,  null, true);
    add('Material | Protection | Trash Bags',            'Demo > Materials', '0100', 'Materials', 'Each', fl > 80 ? 2 : 1, 27, null, true);
    add('Material | Demo | Dump Trailer',                'Demo > Materials', '0200', 'Other',     'Each', 1, 200, null, true);
  }

  // ── FRAMING ────────────────────────────────────────────────────────────────
  add('Labor | Framing | General',          'Rough Carpentry > Labor',     '0600', 'Labor',     'Hours', s.framing_hours, 0, 'framing', s.framing_hours > 0);
  add('Labor | Framing | Niche Blocking',   'Rough Carpentry > Labor',     '0600', 'Labor',     'Hours', s.niche_count * 2, 0, 'framing', s.has_niche && s.niche_count > 0);
  add('Labor | Framing | Install Tub',      'Rough Carpentry > Labor',     '0600', 'Labor',     'Hours', 5, 0, 'framing', s.has_tub);
  add('Labor | Framing | Pocket Door',      'Rough Carpentry > Labor',     '0600', 'Labor',     'Hours', 6, 0, 'framing', s.has_pocket_door);
  add('Material | Framing | Screws 3" Exterior 5lb',  'Rough Carpentry > Materials', '3100', 'Materials', 'Each', 1, 32.98, null, true);
  add('Material | Framing | 2x4x8 KD SPF',            'Rough Carpentry > Materials', '0600', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 8)), 13, null, true);
  add('Material | Framing | Plywood 3/4" ACX',         'Rough Carpentry > Materials', '0600', 'Materials', 'Each', 1, 95, null, true);
  add('Material | Framing | Pocket Door Frame Kit',    'Rough Carpentry > Materials', '0600', 'Materials', 'Each', 1, 362.85, null, s.has_pocket_door);

  // ── PLUMBING ───────────────────────────────────────────────────────────────
  if (s.has_shower) {
    add('Labor | Plumbing | Install Mixer Valve',  'Plumbing > Shower Labor', '1100', 'Labor', 'Hours', 4, 0, 'plumbing', true);
    add('Labor | Plumbing | Install Shower Trim',  'Plumbing > Shower Labor', '1100', 'Labor', 'Hours', 2, 0, 'plumbing', true);
    add('Labor | Plumbing | Run Showerhead Copper','Plumbing > Shower Labor', '1100', 'Labor', 'Hours', s.shower_head_config === 'rain_handheld' ? 6 : 4, 0, 'plumbing', true);
    add('Material | Plumbing | Posi-Temp Rough-In Valve', 'Plumbing > Materials', '1100', 'Materials', 'Each',     1, 135, null, true);
    add('Material | Plumbing | 1/2" Copper Pipe',         'Plumbing > Materials', '1100', 'Materials', 'Each',     s.shower_head_config === 'rain_handheld' ? 3 : 2, 8, null, true);
    add('Material | Plumbing | Copper Fittings',          'Plumbing > Materials', '1100', 'Materials', 'Lump Sum', 1, 50, null, true);
  }
  if (s.has_tub) {
    add('Labor | Plumbing | Tub Drain Hookup', 'Plumbing > Tub Labor', '1100', 'Labor', 'Hours', 4, 0, 'plumbing', true);
  }
  add('Labor | Plumbing | Install Toilet', 'Plumbing > Toilet Labor', '1100', 'Labor', 'Hours', s.toilet_type === 'wall_mount' ? 8 : 2, 0, 'plumbing', true);
  if (s.plumbing_moved) {
    add('Material | Plumbing | 2" PVC Drain Pipe 10\'', 'Plumbing > Materials', '1100', 'Materials', 'Each', 1, 17, null, true);
  }
  add('Material | Plumbing | PVC Fittings', 'Plumbing > Materials', '1100', 'Materials', 'Each', 6, 3, null, true);

  // ── ELECTRICAL ─────────────────────────────────────────────────────────────
  if (s.electrical_needed) {
    const elecHrs = s.electrical_scope === 'moderate' ? 8 : s.electrical_scope === 'rewire' ? 16 : 4;
    add('Labor | Electrical | General',        'Electrical > Labor',     '1000', 'Labor',     'Hours', elecHrs, 0, 'electrical', true);
    add('Labor | Electrical | GFCI Install',   'Electrical > Labor',     '1000', 'Labor',     'Hours', s.gfci_count * 1.5, 0, 'electrical', s.gfci_count > 0);
    add('Material | Electrical | GFCI Outlet', 'Electrical > Materials', '1000', 'Materials', 'Each',  s.gfci_count, 25, null, s.gfci_count > 0);
    add('Labor | Electrical | Light Fixture Install', 'Electrical > Labor', '1000', 'Labor', 'Hours', s.light_fixture_count, 0, 'electrical', s.light_fixture_count > 0);
    add('Labor | Electrical | Exhaust Fan',           'Electrical > Labor', '1000', 'Labor', 'Hours', 3, 0, 'electrical', s.has_fan);
  }

  // ── WATERPROOFING ──────────────────────────────────────────────────────────
  if (s.has_shower) {
    const wpSqft = wallTile + fl * 0.3;
    add('Labor | Waterproofing | Membrane Application', 'Waterproofing > Labor', '1800', 'Labor', 'Hours', Math.max(6, wpSqft * 0.04), 0, 'waterproofing', true);
  }

  // ── TILEWORK ───────────────────────────────────────────────────────────────
  const tileMultiplier = s.tile_complexity === 'mosaic' ? 0.4 : s.tile_complexity === 'pattern' ? 0.3 : 0.22;
  add('Labor | Tile | Floor Installation', 'Tilework > Floor Tile Labor', '1800', 'Labor', 'Hours', Math.max(8, fl * tileMultiplier), 0, 'tiling', true);
  if (s.has_shower) {
    const showerMultiplier = s.tile_complexity === 'mosaic' ? 0.25 : 0.18;
    add('Labor | Tile | Shower Installation', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours', Math.max(12, wallTile * showerMultiplier), 0, 'tiling', true);
    add('Labor | Tile | Niche Installation',  'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours', s.niche_count * 4, 0, 'tiling', s.has_niche && s.niche_count > 0);
  }
  if (s.shower_pan_type === 'schluter_tray') {
    add('Material | Tile | Schluter Shower Pan', 'Tilework > Materials', '1800', 'Materials', 'Each', 1,  178, null, true);
    add('Material | Tile | Schluter Drain',      'Tilework > Materials', '1800', 'Materials', 'Each', 1,   99, null, true);
  }
  add('Material | Tile | Waterproof Backer Board 1/2" 4x8', 'Tilework > Materials', '1800', 'Materials', 'Each',     Math.max(2, Math.ceil(wallTile / 32)), 98.99, null, s.has_shower);
  add('Material | Tile | Schluter Banding 16\'',             'Tilework > Materials', '1800', 'Materials', 'Each',     Math.max(1, Math.ceil(perim / 16)), 20.75, null, true);
  add('Material | Tile | Permacolor Grout',                  'Tilework > Materials', '1800', 'Materials', 'Each',     1, 95,   null, true);
  add('Material | Tile | Schluter 1/4" Aluminum Trim',       'Tilework > Materials', '1800', 'Materials', 'Each',     Math.max(2, Math.ceil(perim / 8)), 24, null, true);
  add('Material | Tile | Thinset Mortar 50#',                'Tilework > Materials', '1800', 'Materials', 'Each',     Math.max(2, Math.ceil((fl + wallTile) / 80)), 28.5, null, true);
  add('Material | Tile | Silicone Sealant',                  'Tilework > Materials', '1800', 'Materials', 'Each',     Math.max(2, Math.ceil(perim / 12)), 22, null, true);
  add('Material | Tile | Grout Sealer',                      'Tilework > Materials', '1800', 'Materials', 'Each',     1, 20, null, true);

  // ── DRYWALL ────────────────────────────────────────────────────────────────
  if (s.drywall_repair_needed) {
    add('Labor | Drywall | Remove and Replace',       'Drywall > Labor',     '1400', 'Labor',     'Hours', s.drywall_sheets * 1.5, 0, 'drywall', true);
    add('Material | Drywall | Drywall 1/2" 4x8',     'Drywall > Materials', '1400', 'Materials', 'Each', Math.max(1, Math.floor(s.drywall_sheets * 0.6)), 20.48, null, true);
    add('Material | Drywall | Mold Resistant 1/2" 4x8','Drywall > Materials','1400', 'Materials', 'Each', Math.max(1, Math.ceil(s.drywall_sheets * 0.4)),  19.2,  null, true);
    add('Material | Drywall | Mud 4.5 gal',           'Drywall > Materials', '1400', 'Materials', 'Each', 1, 15.48, null, true);
    add('Material | Drywall | Tape Mesh 500ft',       'Drywall > Materials', '1400', 'Materials', 'Each', 1, 11.98, null, true);
    add('Material | Drywall | Screws 1-5/8" 1lb',     'Drywall > Materials', '1400', 'Materials', 'Each', 1,  7.98, null, s.drywall_sheets <= 3);
    add('Material | Drywall | Screws 1-5/8" 5lb',     'Drywall > Materials', '1400', 'Materials', 'Each', 1, 25.98, null, s.drywall_sheets > 3);
  }

  // ── PAINTING ───────────────────────────────────────────────────────────────
  const paintHrs = (perim * s.wall_height) / 40;
  const paintGal = Math.max(1, Math.ceil((perim * s.wall_height) / 350));
  add('Labor | Painting | Prep',         'Painting > Labor',     '2300', 'Labor',     'Hours',   Math.max(4, Math.ceil(paintHrs * 0.30)), 0, 'painting', true);
  add('Labor | Painting | Caulking',     'Painting > Labor',     '2300', 'Labor',     'Hours',   Math.max(2, Math.ceil(paintHrs * 0.15)), 0, 'painting', true);
  add('Labor | Painting | Prime Coat',   'Painting > Labor',     '2300', 'Labor',     'Hours',   Math.max(3, Math.ceil(paintHrs * 0.25)), 0, 'painting', true);
  add('Labor | Painting | Finish Coats', 'Painting > Labor',     '2300', 'Labor',     'Hours',   Math.max(4, Math.ceil(paintHrs * 0.50)), 0, 'painting', true);
  add('Material | Painting | BIN Shellac Primer',        'Painting > Materials', '2300', 'Materials', 'Gallons', paintGal, 75,    null, true);
  add('Material | Painting | SW Emerald Urethane Semi Gloss', 'Painting > Materials', '2300', 'Materials', 'Each', paintGal, 110, null, true);
  add('Material | Painting | Painters Tape Blue',        'Painting > Materials', '2300', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 12)), 6.98,  null, true);
  add('Material | Painting | Caulking',                  'Painting > Materials', '2300', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 12)), 11.19, null, true);

  // ── FINISH CARPENTRY ───────────────────────────────────────────────────────
  add('Labor | Finish Carpentry | Install Vanity',       'Finish Carpentry > Labor', '1900', 'Labor', 'Hours', s.vanity_size === 'double' ? 6 : 4, 0, 'cabinetry', true);
  add('Labor | Finish Carpentry | Accessories & Hardware','Finish Carpentry > Labor', '1900', 'Labor', 'Hours', Math.max(4, s.accessory_count * 0.75), 0, 'cabinetry', true);
  add('Labor | Finish Carpentry | Mirror Install',       'Finish Carpentry > Labor', '1900', 'Labor', 'Hours', 2, 0, 'cabinetry', s.has_mirror);
  add('Labor | Finish Carpentry | Trim & Base',          'Finish Carpentry > Labor', '2100', 'Labor', 'Hours', Math.max(2, Math.ceil(perim / 6)), 0, 'cabinetry', s.has_trim_work);

  // ── ALLOWANCES ─────────────────────────────────────────────────────────────
  add('Allowance | Bathtub',              'Allowances',       '2400', 'Materials', 'Lump Sum', 1, s.tub_allowance,          null, s.has_tub);
  add('Allowance | Shower Trim',          'Allowances',       '1100', 'Materials', 'Lump Sum', 1, s.shower_trim_allowance,  null, s.has_shower);
  add('Allowance | Shower Tile',          'Allowances > Tile','1800', 'Materials', 'Lump Sum', 1, Math.max(800, Math.round(wallTile * 12)), null, s.has_shower);
  add('Allowance | Floor Tile',           'Allowances > Tile','1800', 'Materials', 'Lump Sum', 1, Math.max(400, Math.round(fl * 10)),       null, true);
  add('Allowance | Toilet',               'Allowances',       '2400', 'Materials', 'Lump Sum', 1, s.toilet_allowance,       null, true);
  add('Allowance | Vanity',               'Allowances',       '3000', 'Materials', 'Lump Sum', 1, s.vanity_allowance,       null, true);
  add('Allowance | Bathroom Accessories', 'Allowances',       '3000', 'Materials', 'Lump Sum', 1, s.accessory_allowance,    null, true);
  add('Allowance | Electrical',           'Allowances',       '1000', 'Materials', 'Lump Sum', 1, 800,                      null, s.electrical_needed);

  // ── CUSTOM LINE ITEMS ──────────────────────────────────────────────────────
  (s.custom_items ?? []).forEach(ci => {
    if (ci.name && ci.qty > 0) {
      add(ci.name, ci.group ?? 'Additional Items', ci.code ?? '3100', ci.type ?? 'Materials', ci.unit ?? 'Each', ci.qty, ci.cost ?? 0, ci.trade ?? null, true);
    }
  });

  return items;
}

/**
 * Apply qty overrides and removals from user edits.
 * Returns final estimate ready for display/export.
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
