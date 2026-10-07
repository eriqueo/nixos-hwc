import { useState, useCallback, useEffect } from 'react';

const STORAGE_KEY = 'hwc-estimate-state';

export const DEFAULT_STATE = {
  state_version: 2,
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

function loadSaved() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return parseDraft(JSON.parse(raw));
  } catch {
    return null;
  }
}

export function parseDraft(saved) {
  if (!saved || typeof saved !== 'object' || Array.isArray(saved) ||
      !['bathroom', 'deck'].includes(saved.projectType) ||
      (saved.state_version && saved.state_version !== 2)) throw new Error('Unsupported estimator draft');
  for (const [key, value] of Object.entries(saved)) {
    if (typeof DEFAULT_STATE[key] === 'number' && (typeof value !== 'number' || !Number.isFinite(value))) throw new Error(`Invalid draft field: ${key}`);
  }
  for (const field of ['custom_items', 'catalog_picks']) {
    if (saved[field] !== undefined && (!Array.isArray(saved[field]) || saved[field].some(item =>
      !item || typeof item.name !== 'string' || typeof item.qty !== 'number' || !Number.isFinite(item.qty) || item.qty < 0))) throw new Error(`Invalid draft field: ${field}`);
  }
  for (const field of ['budget_overrides', 'budget_removed']) {
    const values = saved[field];
    if (values !== undefined && (!values || typeof values !== 'object' || Array.isArray(values) ||
      Object.entries(values).some(([key,value]) => !/^(rule|pick|custom):/.test(key) ||
        (field === 'budget_overrides' ? typeof value !== 'number' || !Number.isFinite(value) || value < 0 : typeof value !== 'boolean')))) throw new Error(`Invalid draft field: ${field}`);
  }
  return { ...DEFAULT_STATE, ...saved, state_version: 2,
    custom_items: (saved.custom_items || []).map((item, index) => ({ ...item, draftId: item.draftId ?? `legacy-custom-${index}` })),
    catalog_picks: (saved.catalog_picks || []).map((item, index) => ({ ...item, draftId: item.draftId ?? `legacy-pick-${index}` })),
  };
}

/**
 * Project state hook with localStorage persistence.
 * Returns [state, setter, resetFn].
 */
export function useProjectState() {
  const [state, setState] = useState(() => loadSaved() ?? DEFAULT_STATE);
  const [storageError, setStorageError] = useState('');

  // Persist to localStorage on every change
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
      setStorageError('');
    } catch {
      setStorageError('This browser could not save your draft. Download a backup before leaving this page.');
    }
  }, [state]);

  const set = useCallback((key, value) => {
    setState(prev => ({ ...prev, [key]: typeof value === 'function' ? value(prev[key]) : value }));
  }, []);

  const reset = useCallback(() => {
    setState(DEFAULT_STATE);
    localStorage.removeItem(STORAGE_KEY);
  }, []);

  const restore = useCallback(saved => {
    setState(parseDraft(saved));
  }, []);
  return [state, set, reset, storageError, restore];
}
