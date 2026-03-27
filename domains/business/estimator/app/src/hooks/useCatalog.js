import { useMemo } from 'react';
import { buildCatalog, applyEdits, computeTotals, groupEstimate } from '../engine/assembler.js';

/**
 * Derives catalog, estimate, totals, and groups from project state + user edits.
 * All values are memoized — only recomputes when inputs change.
 */
export function useCatalog(state, overrides, removed) {
  const catalog  = useMemo(() => buildCatalog(state),               [state]);
  const estimate = useMemo(() => applyEdits(catalog, overrides, removed), [catalog, overrides, removed]);
  const totals   = useMemo(() => computeTotals(estimate),           [estimate]);
  const groups   = useMemo(() => groupEstimate(estimate),           [estimate]);

  return { catalog, estimate, totals, groups };
}
