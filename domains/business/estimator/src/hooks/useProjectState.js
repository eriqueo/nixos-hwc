import { useState, useCallback, useEffect } from 'react';
import preparedDraft from '../data/preparedDraft.json';
import { parseCalculatorIntake } from '../api/crm.js';

import { calculatorPatch, applyCalculatorIntake, DEFAULT_STATE } from '../engine/intake.js';
export { calculatorPatch, applyCalculatorIntake, DEFAULT_STATE } from '../engine/intake.js';

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
