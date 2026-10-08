// Pure intake/state contract shared by the browser and preliminary-budget engine.
import { CALCULATOR_FIELDS, CALCULATOR_INPUT_VERSION } from '../api/crm.js';

import { createFlooring } from './flooring.js';
export const PROJECT_TYPES = { bathroom: 'Bathroom', deck: 'Deck', flooring: 'Flooring' };

// Customer categories stay preferences, never measured dimensions or prices.
export function calculatorPatch(intake) {
  const patch = { projectType: intake.calculator, job_type: intake.calculator === 'deck' ? 'Deck' : 'Bathroom', measurements_checked: 'no', calculator_scope_checked: 'no' };
  for (const key of Object.keys(DEFAULT_STATE)) {
    if (key !== 'state_version' && typeof DEFAULT_STATE[key] === 'number') patch[key] = null;
  }
  const answers = intake.answers;
  const features = new Set(answers.features || []);
  if (intake.calculator === 'bathroom') {
    for (const key of ['has_shower_tile','has_floor_tile','has_accent_tile','has_paint','has_vanity','has_mirror','new_tub','new_electrical','has_toilet','new_fan','has_baseboard','has_drywall_touchup']) patch[key] = 'no';
    patch.demo_scope = answers.project_type === 'full_gut' ? 'full_gut' : 'unknown';
    patch.shower_finish = 'unknown'; patch.floor_finish = 'unknown';
    patch.shower_niches = features.has('niches') ? 'unknown' : '0';
    patch.has_shower_door = features.has('glass_door') ? 'yes' : 'unknown';
    const fields = { new_toilet: 'has_toilet', lighting: 'new_electrical', gfci: 'new_electrical', mirror: 'has_mirror', door: 'has_new_door', ventilation: 'new_fan', double_vanity: 'has_vanity', paint: 'has_paint', baseboard: 'has_baseboard' };
    for (const [feature,key] of Object.entries(fields)) if (features.has(feature)) patch[key] = 'yes';
  } else {
    patch.decking_material = { pt_lumber: 'pt', cedar: 'cedar', composite_mid: 'composite_mid', composite_premium: 'composite_premium' }[answers.material] || 'unknown';
    patch.railing_type = { none: 'no', wood: 'wood', metal_cable: 'metal_cable', glass: 'glass' }[answers.railing] || 'unknown';
    patch.project_scope = { new_build: 'new_build', full_rebuild: 'full_rebuild', partial_rebuild: 'partial_rebuild', repair_refresh: 'repair' }[answers.project_type] || 'unknown';
  }
  if (answers.intake_version === CALCULATOR_INPUT_VERSION) {
    for (const field of CALCULATOR_FIELDS[intake.calculator]) {
      const value = answers[field.id];
      if (value !== undefined && value !== null) patch[field.id] = field.id === 'shower_niches' ? String(value) : value;
    }
    if (answers.shower_finish && answers.shower_finish !== 'unknown') patch.has_shower_tile = answers.shower_finish === 'tile' ? 'yes' : 'no';
    if (answers.floor_finish && answers.floor_finish !== 'unknown') patch.has_floor_tile = answers.floor_finish === 'tile' ? 'yes' : 'no';
  }
  return patch;
}

export function applyCalculatorIntake(current, intake) {
  if (current.jobId !== intake.jt_job_id || current.mode !== 'existing' || current.calculator_intake) return current;
  const touched = new Set(current.touched_fields || Object.keys(current));
  const patch = Object.fromEntries(Object.entries(calculatorPatch(intake)).filter(([key]) => !touched.has(key)));
  return { ...current, ...patch, calculator_intake: intake, calculator_input_status: 'ready' };
}

export const DEFAULT_STATE = {
  state_version: 3,
  flooring: createFlooring(),
  budget_overrides: {},
  budget_removed: {},
  site_notes: '',
  measurements_checked: 'no',
  target_budget: null,
  owner_purchase_cost: null,
  shower_finish: null,
  floor_finish: null,
  panel_install_hours: null,
  panel_drain_hours: null,
  panel_material_allowance: null,
  floor_install_hours: null,
  floor_prep_hours: null,
  floor_material_allowance: null,
  electrical_allowance: 800,
  has_existing_tub: 'no',
  has_shower_door: 'unknown',
  shower_door_allowance: null,
  // Job selection (for JT integration)
  mode: 'existing',           // 'existing' | 'new_job' | 'new_customer'
  customerId: '',
  customerName: '',
  locationId: '',
  jobId: '',
  jobNumber: '',
  jobName: '',
  address: '',
  projectType: 'bathroom',
  job_type: 'Bathroom',

  // New customer fields (for new_customer mode)
  newCustomerName: '',
  newCustomerPhone: '',
  newCustomerEmail: '',
  newCustomerStreet: '',
  newCustomerCity: '',
  newCustomerState: 'MT',
  newCustomerZip: '',

  // ── Room measurements (JT numeric parameters) ──
  bathroom_length_ft: 10,
  bathroom_width_ft: 8,
  wall_height_ft: 8,

  // ── Shower measurements (JT numeric parameters) ──
  shower_wall_height_ft: 8,
  shower_wall_1_width_ft: 4,
  shower_wall_2_width_ft: 4,
  shower_wall_3_width_ft: 4,
  shower_wall_4_width_ft: 0,
  shower_pan_width_ft: 4,
  shower_pan_length_ft: 4,
  shower_curb_length_ft: 4,
  shower_curb_width_in: 6,
  shower_curb_height_in: 4,
  bathroom_wall_repair_sqft: 16,

  // ── Picklist parameters (JT picklists — string values) ──
  demo_scope: 'shower_only',
  has_shower_tile: 'yes',
  has_floor_tile: 'yes',
  has_accent_tile: 'no',
  has_paint: 'yes',
  has_vanity: 'yes',
  has_mirror: 'yes',
  new_tub: 'no',
  new_electrical: 'no',
  has_toilet: 'yes',
  new_fan: 'no',
  shower_niches: '0',
  has_baseboard: 'yes',
  has_drywall_touchup: 'yes',

  // ── Scope dimensions ──
  paint_scope: 'walls_and_ceiling',   // walls_only | ceiling_only | walls_and_ceiling
  drywall_scope: 'walls_and_ceiling', // walls_only | ceiling_only | walls_and_ceiling
  baseboard_lf: 20,

  // ── Allowances ──
  tub_allowance: 1200,
  shower_trim_allowance: 1200,
  toilet_allowance: 1600,
  vanity_allowance: 2000,
  accessory_allowance: 1000,

  // ── Deck measurements ──
  deck_length_ft: 12,
  deck_width_ft: 8,
  deck_height_ft: 3,
  joist_spacing_in: 16,
  railing_lf: 0,
  stair_tread_count: 0,
  stair_stringer_count: 3,
  stair_width_ft: 4,
  decking_material: 'pt',
  railing_type: 'no',
  project_scope: 'new_build',

  // ── Custom ──
  custom_items: [],

  // ── Catalog picks (from price book browser) ──
  catalog_picks: [],
};

