import { useState, useCallback, useEffect } from 'react';
import preparedDraft from '../data/preparedDraft.json';
import { parseCalculatorIntake } from '../api/crm.js';

const STORAGE_KEY = 'hwc-estimate-state';
const JOB_DRAFTS_KEY = 'hwc-estimate-job-drafts';
const draftKey = draft => draft.jobId ? `job:${draft.jobId}` : `unassigned:${draft.mode}:${draft.customerId || ''}`;

// CRITICAL device drafts: bounded to 50 jobs, never evicted. Download/import
// remains the backup path; at capacity switching to another job is blocked.
export function switchJobDraft(current, identity, storage) {
  const raw = storage.getItem(JOB_DRAFTS_KEY);
  const saved = raw ? JSON.parse(raw) : { schema_version: 1, jobs: {} };
  if (saved.schema_version !== 1 || !saved.jobs || typeof saved.jobs !== 'object' || Array.isArray(saved.jobs)) throw Error('Invalid saved job drafts');
  const currentKey = draftKey(current);
  const nextKey = draftKey(identity);
  if (!Object.hasOwn(saved.jobs, currentKey) && Object.keys(saved.jobs).length >= 50) throw Error('50 drafts saved. Download backups and remove a finished draft before switching jobs.');
  saved.jobs[currentKey] = current;
  storage.setItem(JOB_DRAFTS_KEY, JSON.stringify(saved));
  const next = Object.hasOwn(saved.jobs, nextKey) ? parseDraft(saved.jobs[nextKey]) : { ...DEFAULT_STATE, touched_fields: [], calculator_input_status: identity.jobId && identity.mode === 'existing' ? 'pending' : 'none' };
  const selected = { ...next, ...identity };
  // A newly selected prepared job gets its newer worksheet, not generic
  // presets. Existing saved job drafts continue through the preserve merge.
  if (!Object.hasOwn(saved.jobs, nextKey) && identity.jobId === preparedDraft.state.jobId) {
    return { ...applyPreparedDraft(null), ...identity, calculator_input_status: 'pending' };
  }
  return selected;
}

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
  return patch;
}

export function applyCalculatorIntake(current, intake) {
  if (current.jobId !== intake.jt_job_id || current.mode !== 'existing' || current.calculator_intake) return current;
  const touched = new Set(current.touched_fields || Object.keys(current));
  const patch = Object.fromEntries(Object.entries(calculatorPatch(intake)).filter(([key]) => !touched.has(key)));
  return { ...current, ...patch, calculator_intake: intake, calculator_input_status: 'ready' };
}

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

// App-owned site worksheet: REPLACEABLE from Git. The device draft remains
// CRITICAL and downloadable. This keyed merge applies once per revision;
// existing measurements, prices, scope choices, edits and send locks win.
export function applyPreparedDraft(saved, prepared = preparedDraft) {
  if (prepared.version !== 1) throw new Error('Unsupported prepared draft');
  if (!saved) {
    const state = parseDraft(prepared.state);
    // The prepared worksheet explicitly labels its zero measurements/quotes
    // as placeholders. Fresh copies show unknown; saved field work is retained.
    for (const [key,value] of Object.entries(state)) if (value === 0 && /(_ft|_in|_sqft|_lf|_allowance)$/.test(key)) state[key] = null;
    return { ...state, prepared_draft_revision: prepared.revision };
  }
  if (saved.jobId !== prepared.state.jobId || saved.prepared_draft_revision === prepared.revision) return saved;
  const questions = prepared.state.site_notes;
  return { ...saved,
    touched_fields: [...new Set([...(saved.touched_fields || Object.keys(saved)), 'target_budget', 'bathroom_floor_sqft', 'site_notes'])],
    target_budget: saved.target_budget ?? prepared.state.target_budget,
    bathroom_floor_sqft: saved.bathroom_floor_sqft ?? prepared.state.bathroom_floor_sqft,
    site_notes: saved.site_notes?.includes(questions) ? saved.site_notes : [saved.site_notes, questions].filter(Boolean).join('\n\n'),
    prepared_draft_revision: prepared.revision,
  };
}

export function parseDraft(saved) {
  if (!saved || typeof saved !== 'object' || Array.isArray(saved) ||
      !['bathroom', 'deck'].includes(saved.projectType) ||
      (saved.state_version && saved.state_version !== 2)) throw new Error('Unsupported estimator draft');
  if (saved.touched_fields !== undefined && (!Array.isArray(saved.touched_fields) || saved.touched_fields.some(key => typeof key !== 'string'))) throw Error('Invalid draft field: touched_fields');
  if (saved.calculator_intake) parseCalculatorIntake(saved.calculator_intake, saved.jobId);
  for (const [key, value] of Object.entries(saved)) {
    if (typeof DEFAULT_STATE[key] === 'number' && value !== null && (typeof value !== 'number' || !Number.isFinite(value))) throw new Error(`Invalid draft field: ${key}`);
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
  const [state, setState] = useState(() => applyPreparedDraft(loadSaved()));
  const [storageError, setStorageError] = useState('');

  // Also apply when an existing session selects the prepared job.
  useEffect(() => {
    setState(current => applyPreparedDraft(current));
  }, [state.jobId]);

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
    setState(prev => ({ ...prev, touched_fields: [...new Set([...(prev.touched_fields || Object.keys(prev)), key])], [key]: typeof value === 'function' ? value(prev[key]) : value }));
  }, []);

  const selectJob = useCallback(identity => {
    setState(prev => {
      if (prev.jobId === identity.jobId && prev.mode === identity.mode && prev.customerId === identity.customerId) return { ...prev, ...identity };
      try { const next = switchJobDraft(prev, identity, localStorage); setStorageError(''); return next; }
      catch (error) { setStorageError(`Job was not changed: ${error.message}. Download your draft backup.`); return prev; }
    });
  }, []);
  const prefill = useCallback(intake => setState(prev => applyCalculatorIntake(prev, intake)), []);

  const reset = useCallback(() => {
    try {
      const raw = localStorage.getItem(JOB_DRAFTS_KEY);
      if (raw) { const saved = JSON.parse(raw); delete saved.jobs[draftKey(state)]; localStorage.setItem(JOB_DRAFTS_KEY, JSON.stringify(saved)); }
    } catch { setStorageError('Saved draft could not be removed. Download a backup.'); return; }
    setState(DEFAULT_STATE);
    localStorage.removeItem(STORAGE_KEY);
  }, [state]);

  const restore = useCallback(saved => {
    setState(parseDraft(saved));
  }, []);
  return [state, set, reset, storageError, restore, selectJob, prefill];
}
