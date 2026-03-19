import { useState, useCallback, useEffect } from 'react';

const STORAGE_KEY = 'hwc-estimate-state';

export const DEFAULT_STATE = {
  // Context
  customer: '', address: '', job_name: '',
  // Measurements
  room_length: 8, room_width: 7, wall_height: 8, tile_height: 6,
  // Core toggles
  demo_scope: 'full_gut', permit_required: true,
  has_tub: true, has_shower: true, has_niche: true,
  // Feature params
  niche_count: 2, shower_pan_type: 'tub_combo', shower_head_config: 'single',
  toilet_type: 'standard', vanity_size: 'single',
  tile_complexity: 'simple',
  // Framing
  framing_hours: 4, has_pocket_door: false,
  // Plumbing
  plumbing_moved: false,
  // Electrical
  electrical_needed: false, electrical_scope: 'minor',
  gfci_count: 1, light_fixture_count: 2, has_fan: true,
  // Drywall
  drywall_repair_needed: true, drywall_sheets: 3,
  // Finish
  has_mirror: true, has_trim_work: true, accessory_count: 5,
  // Allowances
  tub_allowance: 1200, shower_trim_allowance: 1200,
  toilet_allowance: 1600, vanity_allowance: 2000, accessory_allowance: 1000,
  // Custom
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
