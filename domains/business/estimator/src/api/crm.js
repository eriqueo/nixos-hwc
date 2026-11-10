import { parseCalculatorIntake, parsePreliminaryStatus } from '../engine/calculator-contract.js';
// Permanent compatibility facade for existing browser/tool consumers.
export { CALCULATOR_INPUT_VERSION, CALCULATOR_FIELDS, deckAnswerEstimates,
  validateCalculatorFields, parseCalculatorIntake, automaticBudgetBlocks } from '../engine/calculator-contract.js';

// Relative same-origin route; Caddy supplies the credential at runtime.
export const ESTIMATOR_WEBHOOK = import.meta.env?.VITE_WEBHOOK_URL || '/webhook/estimate-push';
const WEBHOOK_BASE = ESTIMATOR_WEBHOOK.slice(0, ESTIMATOR_WEBHOOK.lastIndexOf('/'));

// Authenticated list boundary. Bounded to 20 pages; fail visibly instead of truncating.
export async function fetchCalculatorIntake({ jobId, signal, request = fetch }) {
  const response = await request(`/api/jobs/${encodeURIComponent(jobId)}/calculator-intake`, {
    signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]), cache: 'no-store',
  });
  if (response.status === 404) return null;
  if (!response.ok) throw Error(response.status === 409 ? 'More than one CRM record is linked to this job. Resolve the CRM links before loading customer inputs.' : `Customer inputs could not load (${response.status}).`);
  return parseCalculatorIntake(await response.json(), jobId);
}

export async function fetchPreliminaryBudget(jobId, request=fetch) {
  const response=await request(`/api/jobs/${encodeURIComponent(jobId)}/preliminary-budget`, {cache:'no-store',signal:AbortSignal.timeout(15000)});
  if (!response.ok) throw Error('Budget status could not load. Reload before sending.');
  const data=await response.json();
  if (data.schema_version!==1 || !Object.hasOwn(data,'preliminary_budget')) throw Error('Unsupported budget status. Reload before sending.');
  parsePreliminaryStatus(data.preliminary_budget);
  return data.preliminary_budget;
}

export async function fetchCrmList({ resource, params = {}, signal, request = fetch }) {
  const rows = new Map();
  let page;
  const cursors = new Set();
  for (let count = 0; count < 20; count++) {
    const query = new URLSearchParams(params);
    if (page) query.set('page', page);
    const response = await request(`${WEBHOOK_BASE}/jt-${resource}?${query}`, {
      cache: 'no-store', signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]),
    });
    if (!response.ok) throw new Error(`CRM request failed (${response.status})`);
    const data = await response.json();
    if (!Array.isArray(data[resource]) || data[resource].some(row => typeof row.id !== 'string' || typeof row.name !== 'string')) {
      throw new Error('CRM returned an invalid list');
    }
    data[resource].forEach(row => rows.set(row.id, row));
    if (!data.nextPage) return resource === 'customers'
      ? [...rows.values()].sort((a, b) => a.name.localeCompare(b.name))
      : [...rows.values()];
    if (typeof data.nextPage !== 'string' || cursors.has(data.nextPage)) throw new Error('CRM returned an invalid page cursor');
    page = data.nextPage; cursors.add(page);
  }
  throw new Error('CRM list exceeds 20 pages. Narrow the list before continuing.');
}
