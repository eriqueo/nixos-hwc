import catalog from '../data/catalog.json' with { type: 'json' };
import { tradeRate, matPrice } from './pricing.js';

export const MAX_FLOORING_AREAS = 50;
export const FLOORING_CHOICES = {
  finish: { label: 'Flooring', options: { unknown: 'Choose flooring', lvp: 'Click-lock LVT / LVP', tile: 'Tile' } },
  substrate: { label: 'Substrate', options: { unknown: 'Choose substrate', wood: 'Wood subfloor', concrete: 'Concrete', existing: 'Existing floor' } },
  substrate_checked: { label: 'Substrate reviewed for chosen product', options: { no: 'Not yet checked', yes: 'Checked on site' } },
  supply: { label: 'Floor product supplied by', options: { unknown: 'Choose supplier', hwc: 'HWC', customer: 'Customer' } },
  removal: { label: 'Existing flooring removal', options: { unknown: 'Choose removal scope', none: 'No removal', carpet: 'Carpet', vinyl: 'Vinyl', tile: 'Tile', wood: 'Wood' } },
  trim: { label: 'Baseboard / shoe molding', options: { unknown: 'Choose trim scope', none: 'No trim work', reuse: 'Remove and reinstall', new: 'New trim' } },
};
const number = (key, label, max, positive = false, active = () => true) => ({ key, label, max, positive, active });
export const FLOORING_FIELDS = [
  number('net_sqft', 'Net area (sq ft)', 100000, true),
  number('waste_percent', 'Floor product waste (%)', 100),
  number('box_sqft', 'Coverage per box (sq ft; 0 for loose product)', 1000),
  number('product_cost', 'Floor product cost per sq ft ($)', 1000000, true, a => a.supply === 'hwc'),
  number('install_hours', 'Installation hours', 10000, true),
  number('prep_hours', 'Subfloor preparation hours', 10000),
  number('prep_cost', 'Subfloor preparation materials cost ($ total)', 1000000),
  number('underlay_hours', 'Underlayment / membrane hours', 10000),
  number('underlay_cost', 'Underlayment / membrane cost ($ total)', 1000000),
  number('removal_hours', 'Floor removal hours', 10000, true, a => !['none', 'unknown'].includes(a.removal)),
  number('trim_lf', 'Trim length (linear ft)', 100000, true, a => !['none', 'unknown'].includes(a.trim)),
  number('trim_hours', 'Trim labor hours', 10000, true, a => !['none', 'unknown'].includes(a.trim)),
  number('trim_cost', 'Trim cost per linear ft ($)', 1000000, true, a => a.trim === 'new'),
  number('transitions', 'Transition count', 1000),
  number('transition_hours', 'Transition installation hours', 10000, true, a => a.transitions > 0),
  number('transition_cost', 'Transition cost each ($)', 1000000, true, a => a.transitions > 0),
  number('setting_cost', 'Tile setting materials cost ($ total)', 1000000, true, a => a.finish === 'tile'),
  number('grout_cost', 'Grout cost ($ total)', 1000000, true, a => a.finish === 'tile'),
];
export const FLOORING_JOB_FIELDS = [
  number('setup_hours', 'Moving and protection hours (whole job)', 10000),
  number('cleanup_hours', 'Cleanup hours (whole job)', 10000),
  number('haul_cost', 'Hauling / disposal cost ($ whole job)', 1000000),
];
export function createFlooringArea(id, name) {
  return { id, name, ...Object.fromEntries(Object.entries(FLOORING_CHOICES).map(([key, field]) => [key, Object.keys(field.options)[0]])),
    ...Object.fromEntries(FLOORING_FIELDS.map(f => [f.key, null])) };
}
export function createFlooring() {
  return { schema_version: 1, areas: [], ...Object.fromEntries(FLOORING_JOB_FIELDS.map(f => [f.key, null])) };
}
function validateNumbers(value, fields) {
  for (const f of fields) if (value[f.key] != null && (typeof value[f.key] !== 'number' || !Number.isFinite(value[f.key]) || value[f.key] < 0 || value[f.key] > f.max || (f.key === 'transitions' && !Number.isInteger(value[f.key])))) throw Error(`Invalid flooring field: ${f.label}`);
}
export function parseFlooring(raw) {
  if (!raw || raw.schema_version !== 1 || !Array.isArray(raw.areas) || raw.areas.length > MAX_FLOORING_AREAS) throw Error('Unsupported flooring draft');
  validateNumbers(raw, FLOORING_JOB_FIELDS);
  const ids = new Set();
  const areas = raw.areas.map(a => {
    if (!a || typeof a.id !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(a.id) || ids.has(a.id) || typeof a.name !== 'string' || a.name.length > 120) throw Error('Invalid flooring area identity');
    ids.add(a.id);
    const area = { ...createFlooringArea(a.id, a.name), ...a };
    for (const [key, f] of Object.entries(FLOORING_CHOICES)) if (!Object.hasOwn(f.options, area[key])) throw Error(`Invalid flooring field: ${f.label}`);
    validateNumbers(area, FLOORING_FIELDS);
    return area;
  });
  return { ...createFlooring(), ...raw, areas };
}
export function flooringQuantities(area) {
  if (!(area.net_sqft > 0) || area.waste_percent == null || area.box_sqft == null) return { purchaseSqft: 0, boxes: null };
  const needed = area.net_sqft * (1 + area.waste_percent / 100);
  const boxes = area.box_sqft > 0 ? Math.ceil(needed / area.box_sqft - 1e-9) : null;
  return { purchaseSqft: Math.ceil((boxes === null ? needed : boxes * area.box_sqft) * 100 - 1e-9) / 100, boxes };
}
export function flooringIssues(state) {
  let floor;
  try { floor = parseFlooring(state.flooring); } catch (error) { return [error.message]; }
  const issues = [];
  const missing = (value, fields, prefix) => {
    for (const f of fields) if (f.active(value) && (value[f.key] == null || (f.positive && value[f.key] === 0))) issues.push(`${prefix}: enter ${f.label}.`);
  };
  if (!floor.areas.length) issues.push('Add at least one flooring area in Scope.');
  missing(floor, FLOORING_JOB_FIELDS, 'Whole job');
  floor.areas.forEach((area, index) => {
    const label = area.name.trim() || `Area ${index + 1}`;
    if (!area.name.trim()) issues.push(`${label}: enter an area name.`);
    for (const [key, field] of Object.entries(FLOORING_CHOICES)) if (area[key] === 'unknown' || (key === 'substrate_checked' && area[key] !== 'yes')) issues.push(`${label}: review ${field.label}.`);
    missing(area, FLOORING_FIELDS, label);
  });
  return issues;
}

// DB-owned catalog entries supply cost-code anchors. New area quantities and
// quote costs never mutate the exported catalog or reuse bathroom formulas.
export function assembleFlooring(state) {
  const floor = state.flooring;
  const items = [];
  const add = (key, label, group, anchorId, qty, cost, trade, unit = 'Lump Sum') => {
    const anchor = catalog.find(item => item.ruleId === anchorId);
    if (!anchor) throw Error(`Missing flooring catalog anchor ${anchorId}`);
    const rate = trade ? tradeRate(trade) : { cost: cost ?? 0, price: matPrice(cost ?? 0) };
    items.push({ id: items.length + 1, _editKey: `rule:flooring:${key}`, name: label, group,
      code: anchor.code, type: trade ? 'Labor' : 'Materials', unit: trade ? 'Hours' : unit,
      qty: qty ?? 0, uc: rate.cost, up: rate.price, extC: Math.round(rate.cost * (qty ?? 0) * 100) / 100,
      extP: Math.round(rate.price * (qty ?? 0) * 100) / 100, trade: trade || null,
      quantityFormula: null, wasteFactor: 1, _usedDefault: false, _catalogId: anchor.id, _ruleId: anchorId });
  };
  for (const [index, area] of (floor?.areas || []).entries()) {
    if (!['lvp', 'tile'].includes(area.finish)) continue;
    const tile = area.finish === 'tile';
    const trade = tile ? 'tiling' : 'flooring';
    const group = `Flooring > ${index + 1}. ${area.name}`;
    const line = (key, label, anchor, qty, cost, labor, unit) => add(`${area.id}:${area.finish}:${key}`, `${area.name} | ${label}`, group, anchor, qty, cost, labor, unit);
    if (area.supply === 'hwc') line('product', tile ? 'Floor tile' : 'Click-lock LVT / LVP', tile ? 52 : 163, flooringQuantities(area).purchaseSqft, area.product_cost, null, 'Square Feet');
    line('install', 'Install flooring', tile ? 20 : 164, area.install_hours, null, trade);
    if (area.prep_hours > 0) line('prep', 'Prepare subfloor', 165, area.prep_hours, null, trade);
    if (area.prep_cost > 0) line('prep-material', 'Subfloor preparation materials', 163, 1, area.prep_cost);
    if (area.underlay_hours > 0) line('underlay', 'Install underlayment / membrane', tile ? 20 : 164, area.underlay_hours, null, trade);
    if (area.underlay_cost > 0) line('underlay-material', 'Underlayment / membrane', tile ? 52 : 163, 1, area.underlay_cost);
    if (!['none', 'unknown'].includes(area.removal)) line('removal', `Remove ${area.removal} flooring`, 2, area.removal_hours, null, 'demo');
    if (!['none', 'unknown'].includes(area.trim)) line('trim', area.trim === 'new' ? 'Install new trim' : 'Remove and reinstall trim', 137, area.trim_hours, null, 'trimwork');
    if (area.trim === 'new') line('trim-material', 'Trim', 138, area.trim_lf, area.trim_cost, null, 'Linear Feet');
    if (area.transitions > 0) {
      line('transitions', 'Install transitions', 164, area.transition_hours, null, trade);
      line('transition-material', 'Transitions', tile ? 52 : 163, area.transitions, area.transition_cost, null, 'Each');
    }
    if (tile) {
      line('setting', 'Tile setting materials', 65, 1, area.setting_cost);
      line('grout', 'Grout', 49, 1, area.grout_cost);
    }
  }
  if (floor?.setup_hours > 0) add('job:setup', 'Moving and floor protection', 'Flooring > Whole job', 24, floor.setup_hours, null, 'demo');
  if (floor?.cleanup_hours > 0) add('job:cleanup', 'Final cleanup', 'Flooring > Whole job', 102, floor.cleanup_hours, null, 'cleanup');
  if (floor?.haul_cost > 0) add('job:haul', 'Hauling / disposal', 'Flooring > Whole job', 2, 1, floor.haul_cost);
  return items;
}
