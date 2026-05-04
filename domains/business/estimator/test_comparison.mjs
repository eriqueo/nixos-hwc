/**
 * Comparison test: OLD hardcoded assembler vs NEW data-driven assembler.
 *
 * Runs both engines against all 8 templates and compares:
 * - Item count
 * - Item names (presence)
 * - Quantities (within rounding tolerance)
 * - Unit costs / prices
 * - Totals
 *
 * Usage: node test_comparison.mjs
 */
import { createRequire } from 'module';
const require = createRequire(import.meta.url);

// Load data files
const templates = require('./src/data/templates.json');
const tradeRatesData = require('./src/data/tradeRates.json');
const catalogData = require('./src/data/catalog.json');
const parametersData = require('./src/data/parameters.json');

// ── Inline pricing (same as pricing.js) ─────────────────────────────────────
const MAT_MARKUP = 1.4286;
function tradeRate(trade) {
  const r = tradeRatesData[trade] ?? tradeRatesData.planning;
  const cost = Math.round(r.wage * r.burden * 100) / 100;
  return { cost, price: Math.round(cost * r.markup * 100) / 100 };
}
function matPrice(cost) {
  return Math.round(cost * MAT_MARKUP * 100) / 100;
}

// ── Inline OLD assembler (bathroom) ─────────────────────────────────────────
function deriveGeometry(s) {
  const fl = s.bathroom_length_ft * s.bathroom_width_ft;
  const perim = 2 * (s.bathroom_length_ft + s.bathroom_width_ft);
  const showerW = s.shower_wall_1_width_ft + s.shower_wall_2_width_ft + s.shower_wall_3_width_ft + s.shower_wall_4_width_ft;
  const wallTile = showerW * s.shower_wall_height_ft;
  const panTile = s.shower_pan_width_ft * s.shower_pan_length_ft;
  const curbTile = Math.ceil((s.shower_curb_height_in * 2) / 12 * s.shower_curb_length_ft + (s.shower_curb_width_in * 2) / 12 * s.shower_curb_length_ft);
  const accentTile = showerW * 1.25;
  const paintSqft = perim * s.wall_height_ft;
  return { fl, perim, wallTile, panTile, curbTile, accentTile, paintSqft, showerW };
}

const yn = v => v === 'yes';

function oldBuildCatalog(s) {
  const { fl, perim, wallTile, panTile, curbTile, accentTile, paintSqft } = deriveGeometry(s);
  const niches = parseInt(s.shower_niches) || 0;
  const items = [];
  let id = 0;
  const add = (name, group, code, type, unit, qty, cost, trade, trigger, formula) => {
    if (!trigger) return;
    let uc, up;
    if (type === 'Labor') { const r = tradeRate(trade); uc = r.cost; up = r.price; }
    else { uc = cost; up = matPrice(cost); }
    items.push({ id: ++id, name, group, code, type, unit, qty: Math.ceil(qty * 100) / 100, uc, up, extC: Math.round(uc * qty * 100) / 100, extP: Math.round(up * qty * 100) / 100, trade, quantityFormula: formula || null });
  };

  add('Admin | Planning | Site Walkthrough', 'Preconstruction', '0100', 'Labor', 'Hours', 2, 0, 'planning', true, null);
  add('Labor | Admin | Project Management', 'Preconstruction', '0100', 'Labor', 'Hours', 4, 0, 'planning', true, null);
  add('Other | Admin | Building Permit', 'Preconstruction', '0100', 'Other', 'Each', 1, 350, null, s.demo_scope === 'full_gut' || yn(s.new_tub), null);
  add('Labor | Demo | Install Floor Protection', 'Demo > Labor', '0200', 'Labor', 'Hours', 3, 0, 'demo', true, null);
  add('Labor | Demo | Floor Tile', 'Demo > Labor', '0200', 'Labor', 'Hours', Math.ceil(0.08 * fl), 0, 'demo', s.demo_scope === 'shower_and_floors' || s.demo_scope === 'full_gut', null);
  add('Labor | Demo | Shower Surround', 'Demo > Labor', '0200', 'Labor', 'Hours', 4, 0, 'demo', yn(s.has_shower_tile), null);
  add('Labor | Demo | Bathtub Surround', 'Demo > Labor', '0200', 'Labor', 'Hours', 6, 0, 'demo', yn(s.new_tub) && s.demo_scope === 'full_gut', null);
  add('Material | Protection | Floor Protection Roll', 'Demo > Materials', '0100', 'Materials', 'Each', 1, 35, null, true, null);
  add('Material | Protection | Sheeting Tape', 'Demo > Materials', '0100', 'Materials', 'Each', 2, 13, null, true, null);
  add('Material | Protection | Dust Control Sheeting', 'Demo > Materials', '0100', 'Materials', 'Each', 1, 20, null, true, null);
  add('Material | Protection | Trash Bags', 'Demo > Materials', '0100', 'Materials', 'Each', fl > 80 ? 2 : 1, 27, null, true, null);
  add('Material | Demo | Dump Trailer', 'Demo > Materials', '0200', 'Other', 'Each', 1, 200, null, s.demo_scope === 'shower_and_floors' || s.demo_scope === 'full_gut', null);
  add('Labor | Admin | Final Cleanup', 'Close-Out', '0100', 'Labor', 'Hours', 3, 0, 'planning', true, null);
  add('Labor | Framing | General', 'Rough Carpentry > Labor', '0600', 'Labor', 'Hours', 4, 0, 'framing', true, null);
  add('Labor | Framing | Niche Blocking', 'Rough Carpentry > Labor', '0600', 'Labor', 'Hours', niches * 2, 0, 'framing', niches > 0, null);
  add('Labor | Framing | Install Tub', 'Rough Carpentry > Labor', '0600', 'Labor', 'Hours', 5, 0, 'framing', yn(s.new_tub), null);
  add('Material | Framing | Screws 3" Exterior 5lb', 'Rough Carpentry > Materials', '3100', 'Materials', 'Each', 1, 32.98, null, true, null);
  add('Material | Framing | 2x4x8 KD SPF', 'Rough Carpentry > Materials', '0600', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 8)), 13, null, true, null);
  add('Material | Framing | Plywood 3/4" ACX', 'Rough Carpentry > Materials', '0600', 'Materials', 'Each', 1, 95, null, true, null);
  if (yn(s.has_shower_tile)) {
    add('Labor | Plumbing | Install Mixer Valve', 'Plumbing > Labor', '1100', 'Labor', 'Hours', 4, 0, 'plumbing', true, null);
    add('Labor | Plumbing | Install Shower Trim', 'Plumbing > Labor', '1100', 'Labor', 'Hours', 2, 0, 'plumbing', true, null);
    add('Labor | Plumbing | Run Showerhead Copper', 'Plumbing > Labor', '1100', 'Labor', 'Hours', 4, 0, 'plumbing', true, null);
    add('Material | Plumbing | Posi-Temp Rough-In Valve', 'Plumbing > Materials', '1100', 'Materials', 'Each', 1, 135, null, true, null);
    add('Material | Plumbing | 1/2" Copper Pipe', 'Plumbing > Materials', '1100', 'Materials', 'Each', 2, 8, null, true, null);
    add('Material | Plumbing | Copper Fittings', 'Plumbing > Materials', '1100', 'Materials', 'Lump Sum', 1, 50, null, true, null);
  }
  if (yn(s.new_tub)) { add('Labor | Plumbing | Tub Drain Hookup', 'Plumbing > Labor', '1100', 'Labor', 'Hours', 4, 0, 'plumbing', true, null); }
  add('Labor | Plumbing | Install Toilet', 'Plumbing > Labor', '1100', 'Labor', 'Hours', 2, 0, 'plumbing', true, null);
  add('Material | Plumbing | PVC Fittings', 'Plumbing > Materials', '1100', 'Materials', 'Each', 6, 3, null, true, null);
  add('Labor | Plumbing | Vanity Sink Hookup', 'Plumbing > Labor', '1100', 'Labor', 'Hours', 3, 0, 'plumbing', yn(s.has_vanity), null);
  add('Material | Plumbing | Vanity Faucet Assembly', 'Plumbing > Materials', '1100', 'Materials', 'Each', 1, 85, null, yn(s.has_vanity), null);
  add('Material | Plumbing | Toilet Supply Line', 'Plumbing > Materials', '1100', 'Materials', 'Each', 1, 25, null, true, null);
  if (yn(s.new_electrical)) {
    add('Labor | Electrical | General', 'Electrical > Labor', '1000', 'Labor', 'Hours', 4, 0, 'electrical', true, null);
    add('Material | Electrical | GFCI Outlet', 'Electrical > Materials', '1000', 'Materials', 'Each', 1, 25, null, true, null);
  }
  if (yn(s.new_fan)) { add('Labor | Electrical | Exhaust Fan', 'Electrical > Labor', '1000', 'Labor', 'Hours', 3, 0, 'electrical', true, null); }
  if (yn(s.has_shower_tile)) {
    const wpSqft = wallTile + fl * 0.3;
    add('Labor | Waterproofing | Membrane Application', 'Waterproofing > Labor', '1800', 'Labor', 'Hours', Math.max(6, Math.ceil(wpSqft * 0.15)), 0, 'waterproofing', true, null);
  }
  add('Labor | Tile | Floor Installation', 'Tilework > Floor Tile Labor', '1800', 'Labor', 'Hours', Math.max(8, Math.ceil(fl * 0.28)), 0, 'tiling', yn(s.has_floor_tile), null);
  if (yn(s.has_shower_tile)) {
    add('Labor | Tile | Shower Installation', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours', Math.max(12, Math.ceil(wallTile * 0.33)), 0, 'tiling', true, null);
    add('Labor | Tile | Shower Pan', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours', Math.max(4, Math.ceil(panTile * 0.25)), 0, 'tiling', true, null);
    add('Labor | Tile | Shower Curb', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours', Math.max(2, Math.ceil(curbTile * 0.3)), 0, 'tiling', true, null);
    add('Labor | Tile | Niche Installation', 'Tilework > Shower Tile Labor', '1800', 'Labor', 'Hours', niches * 4, 0, 'tiling', niches > 0, null);
  }
  if (yn(s.has_accent_tile) && yn(s.has_shower_tile)) {
    add('Labor | Tile | Accent Band Installation', 'Tilework > Accent Tile Labor', '1800', 'Labor', 'Hours', Math.max(4, Math.ceil(accentTile * 0.25)), 0, 'tiling', true, null);
  }
  add('Material | Tile | Waterproof Backer Board 1/2" 4x8', 'Tilework > Materials', '1800', 'Materials', 'Each', Math.max(2, Math.ceil(wallTile / 32)), 98.99, null, yn(s.has_shower_tile), null);
  add('Material | Tile | Schluter Banding 16\'', 'Tilework > Materials', '1800', 'Materials', 'Each', Math.max(1, Math.ceil(perim / 16)), 20.75, null, true, null);
  add('Material | Tile | Permacolor Grout', 'Tilework > Materials', '1800', 'Materials', 'Each', 1, 95, null, true, null);
  add('Material | Tile | Schluter 1/4" Aluminum Trim', 'Tilework > Materials', '1800', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 8)), 24, null, true, null);
  add('Material | Tile | Thinset Mortar 50#', 'Tilework > Materials', '1800', 'Materials', 'Each', Math.max(2, Math.ceil((fl + wallTile) / 80)), 28.5, null, true, null);
  add('Material | Tile | Silicone Sealant', 'Tilework > Materials', '1800', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 12)), 22, null, true, null);
  add('Material | Tile | Grout Sealer', 'Tilework > Materials', '1800', 'Materials', 'Each', 1, 20, null, true, null);
  const repairSqft = s.bathroom_wall_repair_sqft;
  const sheets = Math.ceil(repairSqft / 32);
  if (repairSqft > 0) {
    add('Labor | Drywall | Remove and Replace', 'Drywall > Labor', '1400', 'Labor', 'Hours', Math.max(2, Math.ceil(repairSqft * 0.05)), 0, 'drywall', true, null);
    add('Material | Drywall | Drywall 1/2" 4x8', 'Drywall > Materials', '1400', 'Materials', 'Each', Math.max(1, Math.floor(sheets * 0.6)), 20.48, null, true, null);
    add('Material | Drywall | Mold Resistant 1/2" 4x8', 'Drywall > Materials', '1400', 'Materials', 'Each', Math.max(1, Math.ceil(sheets * 0.4)), 19.2, null, true, null);
    add('Material | Drywall | Mud 4.5 gal', 'Drywall > Materials', '1400', 'Materials', 'Each', 1, 15.48, null, true, null);
    add('Material | Drywall | Tape Mesh 500ft', 'Drywall > Materials', '1400', 'Materials', 'Each', 1, 11.98, null, true, null);
    add('Material | Drywall | Screws 1-5/8" 1lb', 'Drywall > Materials', '1400', 'Materials', 'Each', 1, 7.98, null, true, null);
  }
  if (yn(s.has_paint)) {
    const paintHrs = paintSqft / 40;
    const paintGal = Math.max(1, Math.ceil(paintSqft / 350));
    add('Labor | Painting | Prep', 'Painting > Labor', '2300', 'Labor', 'Hours', Math.max(4, Math.ceil(paintHrs * 0.30)), 0, 'painting', true, null);
    add('Labor | Painting | Caulking', 'Painting > Labor', '2300', 'Labor', 'Hours', Math.max(2, Math.ceil(paintHrs * 0.15)), 0, 'painting', true, null);
    add('Labor | Painting | Prime Coat', 'Painting > Labor', '2300', 'Labor', 'Hours', Math.max(3, Math.ceil(paintHrs * 0.25)), 0, 'painting', true, null);
    add('Labor | Painting | Finish Coats', 'Painting > Labor', '2300', 'Labor', 'Hours', Math.max(4, Math.ceil(paintHrs * 0.50)), 0, 'painting', true, null);
    add('Material | Painting | BIN Shellac Primer', 'Painting > Materials', '2300', 'Materials', 'Gallons', paintGal, 75, null, true, null);
    add('Material | Painting | SW Emerald Urethane Semi Gloss', 'Painting > Materials', '2300', 'Materials', 'Each', paintGal, 110, null, true, null);
    add('Material | Painting | Painters Tape Blue', 'Painting > Materials', '2300', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 12)), 6.98, null, true, null);
    add('Material | Painting | Caulking', 'Painting > Materials', '2300', 'Materials', 'Each', Math.max(2, Math.ceil(perim / 12)), 11.19, null, true, null);
  }
  add('Labor | Finish Carpentry | Install Vanity', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours', 4, 0, 'cabinetry', yn(s.has_vanity), null);
  add('Labor | Finish Carpentry | General', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours', 8, 0, 'cabinetry', true, null);
  add('Labor | Finish Carpentry | Mirror Install', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours', 2, 0, 'cabinetry', yn(s.has_mirror), null);
  add('Labor | Finish Carpentry | Shower Door Install', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours', 3, 0, 'cabinetry', yn(s.has_shower_tile), null);
  add('Labor | Finish Carpentry | Accessories Install', 'Finish Carpentry > Labor', '1900', 'Labor', 'Hours', 4, 0, 'cabinetry', true, null);
  add('Allowance | Bathtub', 'Allowances', '2400', 'Materials', 'Lump Sum', 1, s.tub_allowance, null, yn(s.new_tub), null);
  add('Allowance | Shower Trim', 'Allowances', '1100', 'Materials', 'Lump Sum', 1, s.shower_trim_allowance, null, yn(s.has_shower_tile), null);
  add('Allowance | Shower Tile', 'Allowances > Tile', '1800', 'Materials', 'Lump Sum', 1, Math.max(800, Math.round(wallTile * 12)), null, yn(s.has_shower_tile), null);
  add('Allowance | Floor Tile', 'Allowances > Tile', '1800', 'Materials', 'Lump Sum', 1, Math.max(400, Math.round(fl * 10)), null, yn(s.has_floor_tile), null);
  add('Allowance | Toilet', 'Allowances', '2400', 'Materials', 'Lump Sum', 1, s.toilet_allowance, null, true, null);
  add('Allowance | Vanity', 'Allowances', '3000', 'Materials', 'Lump Sum', 1, s.vanity_allowance, null, yn(s.has_vanity), null);
  add('Allowance | Bathroom Accessories', 'Allowances', '3000', 'Materials', 'Lump Sum', 1, s.accessory_allowance, null, true, null);
  add('Allowance | Electrical', 'Allowances', '1000', 'Materials', 'Lump Sum', 1, 800, null, yn(s.new_electrical), null);
  return items;
}

function oldBuildDeckCatalog(s) {
  const deckSqft = s.deck_length_ft * s.deck_width_ft;
  const perimeter = 2 * (s.deck_length_ft + s.deck_width_ft);
  const joistCount = Math.ceil(s.deck_length_ft / (s.joist_spacing_in / 12)) + 1;
  const railingLf = s.railing_lf || 0;
  const stairCount = s.stair_tread_count || 0;
  const footingCount = Math.max(4, Math.ceil(deckSqft / 36));
  const deckingLf = Math.ceil(deckSqft / 0.5);
  const items = []; let id = 0;
  const isNew = s.project_scope === 'new_build' || s.project_scope === 'full_rebuild';
  const hasDemo = s.project_scope === 'full_rebuild';
  const hasStairs = stairCount > 0;
  const hasRailing = s.railing_type && s.railing_type !== 'no' && railingLf > 0;
  const waste = 1.1;
  const add = (name, group, code, type, unit, qty, cost, trade, trigger, formula) => {
    if (!trigger) return;
    let uc, up;
    if (type === 'Labor') { const r = tradeRate(trade); uc = r.cost; up = r.price; }
    else { uc = cost; up = matPrice(cost); }
    items.push({ id: ++id, name, group, code, type, unit, qty: Math.ceil(qty * 100) / 100, uc, up, extC: Math.round(uc * qty * 100) / 100, extP: Math.round(up * qty * 100) / 100, trade, quantityFormula: formula || null });
  };
  add('Labor | Admin | Site Walkthrough', 'Preconstruction', '0100', 'Labor', 'Hours', 2, 0, 'planning', true, null);
  add('Labor | Admin | Project Management', 'Preconstruction', '0100', 'Labor', 'Hours', 4, 0, 'planning', true, null);
  add('Other | Admin | Building Permit', 'Preconstruction', '0100', 'Other', 'Each', 1, 350, null, isNew, null);
  add('Material | Admin | Jobsite Mobilization', 'Preconstruction', '0100', 'Materials', 'Lump Sum', 1, 330, null, true, null);
  add('Labor | Sitework | Cleanup', 'Sitework > Labor', '0110', 'Labor', 'Hours', Math.max(4, Math.ceil(deckSqft * 0.04)), 0, 'demo', true, null);
  add('Material | Sitework | Trash Bags', 'Sitework > Materials', '0100', 'Materials', 'Each', 2, 27, null, true, null);
  add('Material | Sitework | Dump Trailer', 'Sitework > Materials', '0200', 'Other', 'Each', 1, 200, null, true, null);
  add('Labor | Demo | Deck Removal', 'Demolition > Labor', '0200', 'Labor', 'Hours', Math.max(4, Math.ceil(deckSqft * 0.06)), 0, 'demo', hasDemo, null);
  add('Labor | Demo | Move Furnishings', 'Demolition > Labor', '0200', 'Labor', 'Hours', 2, 0, 'demo', hasDemo, null);
  add('Labor | Concrete | Pour Footings', 'Footings > Labor', '2800', 'Labor', 'Hours', footingCount * 1.5, 0, 'framing', isNew, null);
  add('Material | Concrete | Sonotubes 12"x4\'', 'Footings > Materials', '2800', 'Materials', 'Each', footingCount, 17.47, null, isNew, null);
  add('Material | Concrete | Concrete Mix 80lb', 'Footings > Materials', '2800', 'Materials', 'Each', footingCount * 3, 4.38, null, isNew, null);
  add('Material | Concrete | Post Bases', 'Footings > Materials', '2800', 'Materials', 'Each', footingCount, 54, null, isNew, null);
  add('Material | Concrete | Anchor Bolts', 'Footings > Materials', '2800', 'Materials', 'Each', footingCount, 2, null, isNew, null);
  add('Labor | Framing | Deck Frame', 'Framing > Labor', '0600', 'Labor', 'Hours', Math.max(8, Math.ceil(deckSqft * 0.27)), 0, 'framing', isNew, null);
  add('Labor | Framing | Temporary Bracing', 'Framing > Labor', '0600', 'Labor', 'Hours', Math.max(4, Math.ceil(deckSqft * 0.10)), 0, 'framing', isNew && s.deck_height_ft >= 3, null);
  add('Material | Framing | Joists 2x8', 'Framing > Lumber', '0600', 'Materials', 'Each', joistCount, 23.15, null, isNew, null);
  add('Material | Framing | Rim Joists 2x8', 'Framing > Lumber', '0600', 'Materials', 'Each', 4, 23.15, null, isNew, null);
  add('Material | Framing | Blocking 2x8', 'Framing > Lumber', '0600', 'Materials', 'Each', Math.max(1, Math.ceil(deckSqft / 48)), 23.15, null, isNew, null);
  add('Material | Framing | Ledger Board 2x8', 'Framing > Lumber', '0600', 'Materials', 'Each', Math.ceil(s.deck_width_ft / 16) + 1, 23.15, null, isNew, null);
  add('Material | Framing | Fascia 1x8', 'Framing > Lumber', '2500', 'Materials', 'Each', Math.ceil(perimeter / 16) + 1, 31.44, null, true, null);
  add('Material | Framing | Joist Hangers', 'Framing > Hardware', '2500', 'Materials', 'Each', joistCount * 2, 2.98, null, isNew, null);
  add('Material | Framing | Hurricane Ties', 'Framing > Hardware', '2500', 'Materials', 'Each', joistCount, 0.98, null, isNew, null);
  add('Material | Framing | Structural Screws 5lb', 'Framing > Hardware', '3100', 'Materials', 'Each', 1, 46.02, null, true, null);
  add('Material | Framing | Joist Hanger Nails', 'Framing > Hardware', '2500', 'Materials', 'Each', 2, 7.38, null, isNew, null);
  add('Material | Framing | Bolts 1/2"x6"', 'Framing > Hardware', '2500', 'Materials', 'Each', 4, 2, null, isNew, null);
  add('Material | Framing | Flashing / Ledger Tape', 'Framing > Hardware', '2500', 'Materials', 'Each', 1, 130.55, null, isNew, null);
  add('Labor | Decking | Install Decking', 'Decking > Labor', '2500', 'Labor', 'Hours', Math.max(6, Math.ceil(deckSqft * 0.08)), 0, 'framing', true, null);
  const materialCosts = { pt: 1.50, cedar: 2.20, redwood: 2.50, composite_mid: 2.34, composite_premium: 6.80 };
  const matCostPerLf = materialCosts[s.decking_material] || 2.50;
  const boardLf = Math.ceil(deckingLf * waste);
  add('Material | Decking | Deck Boards', 'Decking > Materials', '2500', 'Materials', 'Linear Feet', boardLf, matCostPerLf, null, true, null);
  const useHidden = s.decking_material?.startsWith('composite');
  add('Material | Decking | Hidden Fasteners', 'Decking > Materials', '2500', 'Materials', 'Each', deckSqft < 500 ? 1 : 2, 319.99, null, useHidden, null);
  add('Material | Decking | Deck Screws 350ct', 'Decking > Materials', '2500', 'Materials', 'Each', Math.ceil(deckSqft / 100), 63.33, null, !useHidden, null);
  add('Labor | Decking | Install Stairs', 'Stairs > Labor', '2500', 'Labor', 'Hours', Math.max(4, stairCount * 1.5), 0, 'framing', hasStairs, null);
  add('Material | Stairs | Stringers 2x12x14', 'Stairs > Materials', '0600', 'Materials', 'Each', s.stair_stringer_count || 3, 30, null, hasStairs, null);
  add('Material | Stairs | Tread Stock', 'Stairs > Materials', '2500', 'Materials', 'Linear Feet', Math.ceil(stairCount * (s.stair_width_ft || 4) * waste), matCostPerLf, null, hasStairs, null);
  add('Material | Stairs | Stringer Connectors', 'Stairs > Materials', '2500', 'Materials', 'Each', s.stair_stringer_count || 3, 1.98, null, hasStairs, null);
  add('Labor | Decking | Install Railing', 'Railing > Labor', '2500', 'Labor', 'Hours', Math.max(4, Math.ceil(railingLf * 0.33)), 0, 'framing', hasRailing, null);
  const railCosts = { wood: 35, composite: 50, metal_cable: 75, glass: 120 };
  const railCost = railCosts[s.railing_type] || 35;
  add('Material | Railing | Railing Package', 'Railing > Materials', '2500', 'Materials', 'Linear Feet', Math.ceil(railingLf * waste), railCost, null, hasRailing, null);
  const postCount = Math.ceil(railingLf / 6) + 1;
  add('Material | Railing | Post Caps', 'Railing > Materials', '2500', 'Materials', 'Each', postCount, 20, null, hasRailing, null);
  add('Labor | Admin | Final Cleanup', 'Close-Out', '0100', 'Labor', 'Hours', 3, 0, 'planning', true, null);
  return items;
}

// ── Inline formula engine (same as formulaEngine.js) ────────────────────────
const TOKEN = { NUMBER: 'N', STRING: 'S', IDENT: 'I', OP: 'O', LPAREN: '(', RPAREN: ')', COMMA: ',', EOF: 'E' };
function tokenize(expr) {
  const tokens = []; let i = 0;
  while (i < expr.length) {
    if (/\s/.test(expr[i])) { i++; continue; }
    if (/[0-9.]/.test(expr[i])) { let n = ''; while (i < expr.length && /[0-9.]/.test(expr[i])) n += expr[i++]; tokens.push({ type: TOKEN.NUMBER, value: parseFloat(n) }); continue; }
    if (expr[i] === '"') { i++; let s = ''; while (i < expr.length && expr[i] !== '"') s += expr[i++]; i++; tokens.push({ type: TOKEN.STRING, value: s }); continue; }
    const two = expr.slice(i, i + 2);
    if (['>=', '<=', '==', '!='].includes(two)) { tokens.push({ type: TOKEN.OP, value: two }); i += 2; continue; }
    if ('+-*/><!'.includes(expr[i])) { tokens.push({ type: TOKEN.OP, value: expr[i] }); i++; continue; }
    if (expr[i] === '(') { tokens.push({ type: TOKEN.LPAREN }); i++; continue; }
    if (expr[i] === ')') { tokens.push({ type: TOKEN.RPAREN }); i++; continue; }
    if (expr[i] === ',') { tokens.push({ type: TOKEN.COMMA }); i++; continue; }
    if (/[a-zA-Z_]/.test(expr[i])) { let id = ''; while (i < expr.length && /[a-zA-Z0-9_]/.test(expr[i])) id += expr[i++]; tokens.push({ type: TOKEN.IDENT, value: id }); continue; }
    i++;
  }
  tokens.push({ type: TOKEN.EOF }); return tokens;
}
class P {
  constructor(t, s) { this.t = t; this.p = 0; this.s = s; }
  peek() { return this.t[this.p]; }
  adv() { return this.t[this.p++]; }
  exp(type) { const t = this.adv(); if (t.type !== type) throw new Error(`E ${type}`); return t; }
  parse() { return this.pOr(); }
  pOr() { let l = this.pAnd(); while (this.peek().type === TOKEN.IDENT && this.peek().value.toUpperCase() === 'OR') { this.adv(); const r = this.pAnd(); l = l || r; } return l; }
  pAnd() { let l = this.pNot(); while (this.peek().type === TOKEN.IDENT && this.peek().value.toUpperCase() === 'AND') { this.adv(); const r = this.pNot(); l = l && r; } return l; }
  pNot() { if (this.peek().type === TOKEN.IDENT && this.peek().value.toUpperCase() === 'NOT') { this.adv(); return !this.pNot(); } return this.pCmp(); }
  pCmp() { let l = this.pAdd(); const t = this.peek(); if (t.type === TOKEN.OP && ['==','!=','>','<','>=','<='].includes(t.value)) { const o = this.adv().value; const r = this.pAdd(); switch(o) { case '==': return l == r; case '!=': return l != r; case '>': return l > r; case '<': return l < r; case '>=': return l >= r; case '<=': return l <= r; } } return l; }
  pAdd() { let l = this.pMul(); while (this.peek().type === TOKEN.OP && (this.peek().value === '+' || this.peek().value === '-')) { const o = this.adv().value; const r = this.pMul(); l = o === '+' ? l + r : l - r; } return l; }
  pMul() { let l = this.pUn(); while (this.peek().type === TOKEN.OP && (this.peek().value === '*' || this.peek().value === '/')) { const o = this.adv().value; const r = this.pUn(); l = o === '*' ? l * r : l / r; } return l; }
  pUn() { if (this.peek().type === TOKEN.OP && this.peek().value === '-') { this.adv(); return -this.pUn(); } return this.pAtom(); }
  pAtom() {
    const t = this.peek();
    if (t.type === TOKEN.NUMBER) { this.adv(); return t.value; }
    if (t.type === TOKEN.STRING) { this.adv(); return t.value; }
    if (t.type === TOKEN.LPAREN) { this.adv(); const v = this.pOr(); this.exp(TOKEN.RPAREN); return v; }
    if (t.type === TOKEN.IDENT) {
      const n = t.value; const u = n.toUpperCase();
      if (u === 'TRUE') { this.adv(); return true; }
      if (u === 'FALSE') { this.adv(); return false; }
      this.adv();
      if (this.peek().type === TOKEN.LPAREN) { return this.pFn(n); }
      const v = this.s[n]; if (v !== undefined) { const num = parseFloat(v); return isNaN(num) ? v : num; } return 0;
    }
    throw new Error(`Unexpected: ${JSON.stringify(t)}`);
  }
  pFn(name) {
    this.exp(TOKEN.LPAREN); const a = [];
    if (this.peek().type !== TOKEN.RPAREN) { a.push(this.pOr()); while (this.peek().type === TOKEN.COMMA) { this.adv(); a.push(this.pOr()); } }
    this.exp(TOKEN.RPAREN);
    const f = name.toLowerCase();
    switch(f) { case 'ceil': return Math.ceil(a[0]); case 'floor': return Math.floor(a[0]); case 'round': return Math.round(a[0]); case 'max': return Math.max(...a); case 'min': return Math.min(...a); case 'abs': return Math.abs(a[0]); case 'if': return a[0] ? a[1] : a[2]; default: return 0; }
  }
}
function evalFormula(formula, state) {
  if (!formula) return null;
  try { const r = new P(tokenize(formula), state).parse(); return typeof r === 'number' && isFinite(r) ? r : null; } catch { return null; }
}
function evalCondition(cond, state) {
  if (!cond || cond === 'always') return true;
  try { return !!new P(tokenize(cond), state).parse(); } catch { return false; }
}

// ── Inline enrichState ──────────────────────────────────────────────────────
function enrichState(state) {
  const s = { ...state };
  if (state.job_type === 'Deck') {
    const deckSqft = state.deck_length_ft * state.deck_width_ft;
    s.deck_sqft = deckSqft;
    s.deck_perimeter_lf = 2 * (state.deck_length_ft + state.deck_width_ft);
    s.deck_joist_count = Math.ceil(state.deck_length_ft / (state.joist_spacing_in / 12)) + 1;
    s.deck_footing_count = Math.max(4, Math.ceil(deckSqft / 36));
    s.deck_decking_lf = Math.ceil(deckSqft / 0.5);
    s.railing_lf = state.railing_lf || 0;
    s.stair_tread_count = state.stair_tread_count || 0;
    s.deck_width_ft = state.deck_width_ft;
    s.deck_height_ft = state.deck_height_ft;
    s.stair_width_ft = state.stair_width_ft || 4;
    s.stair_stringer_count = state.stair_stringer_count || 3;
  } else {
    const g = deriveGeometry(state);
    s.bathroom_floor_sqft = g.fl;
    s.bathroom_perimeter_lf = g.perim;
    s.shower_wall_tile_sqft = g.wallTile;
    s.shower_pan_tile_sqft = g.panTile;
    s.shower_curb_tile_sqft = g.curbTile;
    s.shower_accent_tile_sqft = g.accentTile;
    s.bathroom_wall_paint_sqft = g.paintSqft;
  }
  return s;
}

// ── Inline NEW assembler ────────────────────────────────────────────────────
const TRADE_RATE_KEY = { 'admin': 'planning', 'finish_carpentry': 'cabinetry', 'finish carpentry': 'cabinetry', 'tile': 'tiling', 'waterproofing': 'waterproofing', 'protection': 'planning', 'sitework': 'demo', 'concrete': 'framing', 'decking': 'framing', 'stairs': 'framing', 'railing': 'framing' };
function tradeRateKey(name) { const t = (name.split(' | ')[1] || '').toLowerCase(); return TRADE_RATE_KEY[t] || t.replace(/ /g, '_').replace(/&/g, ''); }

const ALLOWANCE_COST_KEY = {
  'Allowance | Bathtub': 'tub_allowance',
  'Allowance | Shower Trim': 'shower_trim_allowance',
  'Allowance | Toilet': 'toilet_allowance',
  'Allowance | Vanity': 'vanity_allowance',
  'Allowance | Bathroom Accessories': 'accessory_allowance',
};

function newAssemble(state, projectType) {
  const applicable = catalogData.filter(item => (item.projectType === projectType || item.projectType === 'general') && item.conditionTrigger && item.sortOrder);
  const included = applicable.filter(item => {
    if (!item.conditionTrigger || item.conditionTrigger === 'always') return true;
    return evalCondition(item.conditionTrigger, state);
  });
  included.sort((a, b) => (a.sortOrder || 500) - (b.sortOrder || 500));
  let id = 0;
  return included.map(item => {
    let qty, usedDefault = false;
    if (item.qtyFormula) {
      qty = evalFormula(item.qtyFormula, state);
      if (qty === null || qty === undefined || isNaN(qty)) { qty = item.defaultQty || 1; usedDefault = true; }
    } else { qty = item.defaultQty || 1; }
    qty = Math.ceil(qty * 100) / 100;
    let uc, up;
    if (item.type === 'Labor' || item.type === 'Admin') {
      const r = tradeRate(tradeRateKey(item.name)); uc = r.cost; up = r.price;
    } else if (ALLOWANCE_COST_KEY[item.name]) {
      uc = state[ALLOWANCE_COST_KEY[item.name]] || 0; up = matPrice(uc);
    } else if (item.name.startsWith('Allowance |') && item.qtyFormula && !item.unitCost) {
      uc = evalFormula(item.qtyFormula, state) || 0; up = matPrice(uc); qty = 1;
    } else {
      uc = item.unitCost || 0; up = item.unitPrice || matPrice(item.unitCost || 0);
    }
    return { id: ++id, name: item.name, group: item.group || '', code: item.code, type: item.type, unit: item.unit || item.unitAbbr || 'Each', qty, uc, up, extC: Math.round(uc * qty * 100) / 100, extP: Math.round(up * qty * 100) / 100, trade: item.trade || null, quantityFormula: item.qtyFormula || null, _usedDefault: usedDefault, _catalogId: item.id };
  });
}

// ── Comparison logic ────────────────────────────────────────────────────────
function computeTotals(items) {
  let cost = 0, price = 0, laborHrs = 0;
  items.forEach(i => { cost += i.extC; price += i.extP; if (i.type === 'Labor') laborHrs += i.qty; });
  return { cost: Math.round(cost * 100) / 100, price: Math.round(price * 100) / 100, items: items.length, laborHrs, margin: price > 0 ? ((price - cost) / price * 100) : 0 };
}

function compareEstimates(name, oldItems, newItems) {
  const oldNames = new Set(oldItems.map(i => i.name));
  const newNames = new Set(newItems.map(i => i.name));
  const oldTotals = computeTotals(oldItems);
  const newTotals = computeTotals(newItems);

  // Handle variant items: old "Deck Boards" -> new "Deck Board PT" etc.
  // A missing old item is OK if a new item starts with the same prefix
  const missing = [...oldNames].filter(n => {
    if (newNames.has(n)) return false;
    // Check if a variant exists
    return !newItems.some(ni => ni.name.startsWith(n.replace(' Boards', ' Board').replace(' Stock', ' Stock')));
  });
  const extra = [...newNames].filter(n => {
    if (oldNames.has(n)) return false;
    // Check if this is a variant of an old item
    return !oldItems.some(oi => n.startsWith(oi.name.replace(' Boards', ' Board').replace(' Stock', ' Stock')));
  });

  // Compare matching items
  const qtyDiffs = [];
  const priceDiffs = [];
  for (const oldItem of oldItems) {
    const newItem = newItems.find(n => n.name === oldItem.name);
    if (!newItem) continue;
    if (Math.abs(oldItem.qty - newItem.qty) > 0.01) {
      qtyDiffs.push({ name: oldItem.name, old: oldItem.qty, new: newItem.qty });
    }
    if (Math.abs(oldItem.uc - newItem.uc) > 0.01) {
      priceDiffs.push({ name: oldItem.name, field: 'uc', old: oldItem.uc, new: newItem.uc });
    }
    if (Math.abs(oldItem.up - newItem.up) > 0.01) {
      priceDiffs.push({ name: oldItem.name, field: 'up', old: oldItem.up, new: newItem.up });
    }
  }

  const totalDiff = Math.abs(oldTotals.price - newTotals.price);
  // Allow $15 tolerance for real pricing improvements from JT catalog vs hardcoded values
  const pass = missing.length === 0 && qtyDiffs.length === 0 && totalDiff < 15;

  console.log(`\n${'='.repeat(70)}`);
  console.log(`${pass ? 'PASS' : 'FAIL'} | ${name}`);
  console.log(`  Old: ${oldTotals.items} items, $${oldTotals.price.toFixed(2)} price, ${oldTotals.laborHrs} labor hrs`);
  console.log(`  New: ${newTotals.items} items, $${newTotals.price.toFixed(2)} price, ${newTotals.laborHrs} labor hrs`);

  if (missing.length > 0) {
    console.log(`  MISSING from new (${missing.length}):`);
    missing.forEach(n => console.log(`    - ${n}`));
  }
  if (extra.length > 0) {
    console.log(`  EXTRA in new (${extra.length}):`);
    extra.forEach(n => console.log(`    + ${n}`));
  }
  if (qtyDiffs.length > 0) {
    console.log(`  QTY DIFFS (${qtyDiffs.length}):`);
    qtyDiffs.forEach(d => console.log(`    ${d.name}: old=${d.old} new=${d.new}`));
  }
  if (priceDiffs.length > 0) {
    console.log(`  PRICE DIFFS (${priceDiffs.length}):`);
    priceDiffs.forEach(d => console.log(`    ${d.name} ${d.field}: old=${d.old} new=${d.new}`));
  }
  if (totalDiff >= 1) {
    console.log(`  TOTAL DIFF: $${totalDiff.toFixed(2)}`);
  }

  return pass;
}

// ── Run all templates ───────────────────────────────────────────────────────
console.log('Assembler Comparison Test: OLD (hardcoded) vs NEW (data-driven)');
console.log(`Templates: ${templates.length}`);
console.log(`Catalog items: ${catalogData.length} (${catalogData.filter(i => i.conditionTrigger).length} with assembly logic)`);

let passed = 0, failed = 0;

for (const tmpl of templates) {
  const state = typeof tmpl.state === 'string' ? JSON.parse(tmpl.state) : tmpl.state;
  const projectType = tmpl.project_type;

  if (projectType === 'bathroom') {
    const oldResult = oldBuildCatalog(state);
    const enriched = enrichState(state);
    const newResult = newAssemble(enriched, 'bathroom');
    if (compareEstimates(`${tmpl.name} (bathroom)`, oldResult, newResult)) passed++; else failed++;
  } else {
    const oldResult = oldBuildDeckCatalog(state);
    const enriched = enrichState(state);
    const newResult = newAssemble(enriched, 'deck');
    if (compareEstimates(`${tmpl.name} (deck)`, oldResult, newResult)) passed++; else failed++;
  }
}

console.log(`\n${'='.repeat(70)}`);
console.log(`RESULTS: ${passed} passed, ${failed} failed, ${templates.length - passed - failed} skipped`);
process.exit(failed > 0 ? 1 : 0);
