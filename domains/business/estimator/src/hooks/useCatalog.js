import { useMemo } from 'react';
import { assemble, applyEdits, computeTotals, groupEstimate } from '../engine/assembler.js';
import { enrichState } from '../engine/geometry.js';

/**
 * Derives catalog, estimate, totals, and groups from project state + user edits.
 * Uses the data-driven assembler that reads from catalog.json.
 * Merges catalog_picks (from price book browser) into the estimate.
 * All values are memoized -- only recomputes when inputs change.
 */
export function useCatalog(state, overrides, removed) {
  const enrichedState = useMemo(() => enrichState(state), [state]);
  const projectType = state.job_type === 'Deck' ? 'deck' : 'bathroom';
  const assembled = useMemo(() => assemble(enrichedState, projectType), [enrichedState, projectType]);

  // Merge catalog picks into the assembled line items
  const catalogPicks = state.catalog_picks || [];
  const catalog = useMemo(() => {
    if (catalogPicks.length === 0) return assembled;
    // Start IDs after assembled items to avoid collisions
    const maxId = assembled.reduce((mx, i) => Math.max(mx, i.id), 0);
    const pickItems = catalogPicks.map((p, idx) => ({
      id: maxId + idx + 1,
      name: p.name,
      group: p.group || 'Catalog Picks',
      code: p.code || '',
      type: p.type || 'Materials',
      unit: p.unit || p.unitAbbr || 'Each',
      qty: p.qty || 1,
      uc: p.uc || 0,
      up: p.up || 0,
      extC: Math.round((p.uc || 0) * (p.qty || 1) * 100) / 100,
      extP: Math.round((p.up || 0) * (p.qty || 1) * 100) / 100,
      trade: p.trade || null,
      quantityFormula: null,
      wasteFactor: 1.0,
      _usedDefault: false,
      _catalogId: p.catalogItemId || null,
      _ruleId: null,
      _source: 'catalog_pick',
      _pickIndex: idx,
    }));
    return [...assembled, ...pickItems];
  }, [assembled, catalogPicks]);

  const estimate = useMemo(() => applyEdits(catalog, overrides, removed), [catalog, overrides, removed]);
  const totals   = useMemo(() => computeTotals(estimate), [estimate]);
  const groups   = useMemo(() => groupEstimate(estimate), [estimate]);

  return { catalog, estimate, totals, groups };
}
