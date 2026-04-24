import { useState, useCallback, useEffect } from 'react';

const STORAGE_KEY = 'hwc-estimate-state';

export const DEFAULT_STATE = {
  // Job selection (for JT integration)
  mode: 'existing',           // 'existing' | 'new_job'
  customerId: '',
  customerName: '',
  locationId: '',
  jobId: '',
  jobNumber: '',
  jobName: '',
  address: '',
  projectType: 'bathroom',

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
  new_fan: 'no',
  shower_niches: '0',

  // ── Allowances ──
  tub_allowance: 1200,
  shower_trim_allowance: 1200,
  toilet_allowance: 1600,
  vanity_allowance: 2000,
  accessory_allowance: 1000,

  // ── Custom ──
  custom_items: [],
};

function loadSaved() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return { ...DEFAULT_STATE, ...JSON.parse(raw) };
  } catch {
    return null;
  }
}

/**
 * Project state hook with localStorage persistence.
 * Returns [state, setter, resetFn].
 */
export function useProjectState() {
  const [state, setState] = useState(() => loadSaved() ?? DEFAULT_STATE);

  // Persist to localStorage on every change
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch {
      // storage full — silently ignore
    }
  }, [state]);

  const set = useCallback((key, value) => {
    setState(prev => ({ ...prev, [key]: value }));
  }, []);

  const reset = useCallback(() => {
    setState(DEFAULT_STATE);
    localStorage.removeItem(STORAGE_KEY);
  }, []);

  return [state, set, reset];
}
