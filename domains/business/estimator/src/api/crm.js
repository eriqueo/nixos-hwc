// Shared calculator -> estimator contract. Feet and counts are customer reports,
// never site verification. The public calculator imports this same vocabulary.
export const CALCULATOR_INPUT_VERSION = 2;
export const CALCULATOR_FIELDS = {
  bathroom: [
    { id: 'bathroom_length_ft', label: 'Room length', unit: 'ft', min: 0.25, max: 100 },
    { id: 'bathroom_width_ft', label: 'Room width', unit: 'ft', min: 0.25, max: 100 },
    { id: 'wall_height_ft', label: 'Ceiling height', unit: 'ft', min: 1, max: 30 },
    { id: 'shower_pan_length_ft', label: 'Shower base length', unit: 'ft', min: 0.25, max: 30 },
    { id: 'shower_pan_width_ft', label: 'Shower base width', unit: 'ft', min: 0.25, max: 30 },
    { id: 'shower_niches', label: 'Number of shower niches', unit: 'count', min: 0, max: 3, integer: true },
    { id: 'shower_finish', label: 'Shower finish', options: [{ v: 'unknown', l: 'Choose on site' }, { v: 'none', l: 'No shower work' }, { v: 'tile', l: 'Tile' }, { v: 'panel', l: 'Panel / prefab kit' }] },
    { id: 'floor_finish', label: 'Floor finish', options: [{ v: 'unknown', l: 'Choose on site' }, { v: 'none', l: 'Keep existing' }, { v: 'tile', l: 'Tile' }, { v: 'vinyl', l: 'Vinyl / LVP' }, { v: 'marmoleum', l: 'Marmoleum' }] },
  ],
  deck: [
    { id: 'deck_length_ft', label: 'Deck length', unit: 'ft', min: 0.25, max: 200 },
    { id: 'deck_width_ft', label: 'Deck width', unit: 'ft', min: 0.25, max: 200 },
    { id: 'deck_height_ft', label: 'Height above ground', unit: 'ft', min: 0, max: 30 },
    { id: 'railing_lf', label: 'Total railing length', unit: 'ft', min: 0, max: 800 },
    { id: 'stair_tread_count', label: 'Number of stair treads', unit: 'count', min: 0, max: 100, integer: true },
  ],
};

export function validateCalculatorFields(calculator, answers) {
  if (answers.intake_version === undefined) return; // Permanent legacy reader.
  if (answers.intake_version !== CALCULATOR_INPUT_VERSION) throw Error('Unsupported customer input version.');
  for (const field of CALCULATOR_FIELDS[calculator]) {
    const value = answers[field.id];
    if (value === undefined || value === null) continue;
    if (field.options ? !field.options.some(o => o.v === value) :
      typeof value !== 'number' || !Number.isFinite(value) || value < field.min || value > field.max || (field.integer && !Number.isInteger(value))) {
      throw Error(`Invalid customer input: ${field.label}.`);
    }
  }
}

// Authenticated list boundary. Bounded to 20 pages; fail visibly instead of truncating.
export async function fetchCalculatorIntake({ jobId, signal, request = fetch }) {
  const response = await request(`/api/jobs/${encodeURIComponent(jobId)}/calculator-intake`, {
    signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]), cache: 'no-store',
  });
  if (response.status === 404) return null;
  if (!response.ok) throw Error(response.status === 409 ? 'More than one CRM record is linked to this job. Resolve the CRM links before loading customer inputs.' : `Customer inputs could not load (${response.status}).`);
  return parseCalculatorIntake(await response.json(), jobId);
}

export function parseCalculatorIntake(data, jobId) {
  if (data.schema_version !== 1 || data.jt_job_id !== jobId || !['bathroom','deck'].includes(data.calculator) ||
      typeof data.lead_id !== 'string' || (data.report_id !== null && typeof data.report_id !== 'string') || !data.answers || Array.isArray(data.answers) || typeof data.answers !== 'object' ||
      Object.keys(data.answers).length > 40 ||
      Object.entries(data.answers).some(([key,v]) => key === 'features' ? !Array.isArray(v) || v.some(f => typeof f !== 'string') :
        v !== null && typeof v !== 'boolean' && typeof v !== 'string' && !(typeof v === 'number' && Number.isFinite(v)))) throw Error('Customer inputs have an unsupported format. Enter scope manually.');
  if (data.rough_estimate !== null && (!data.rough_estimate || ![data.rough_estimate.low,data.rough_estimate.high].every(v => typeof v === 'number' && Number.isFinite(v) && v >= 0) || data.rough_estimate.low > data.rough_estimate.high)) throw Error('Customer estimate has an unsupported format.');
  if (data.preliminary_budget !== undefined) parsePreliminaryStatus(data.preliminary_budget);
  validateCalculatorFields(data.calculator, data.answers);
  return data;
}

export function automaticBudgetBlocks(budget) {
  return !!budget && (!['failed','skipped'].includes(budget.state) || budget.error_code === 'existing_budget');
}

export async function fetchPreliminaryBudget(jobId, request=fetch) {
  const response=await request(`/api/jobs/${encodeURIComponent(jobId)}/preliminary-budget`, {cache:'no-store',signal:AbortSignal.timeout(15000)});
  if (!response.ok) throw Error('Budget status could not load. Reload before sending.');
  const data=await response.json();
  if (data.schema_version!==1 || !Object.hasOwn(data,'preliminary_budget')) throw Error('Unsupported budget status. Reload before sending.');
  parsePreliminaryStatus(data.preliminary_budget);
  return data.preliminary_budget;
}

function parsePreliminaryStatus(budget) {
  if (budget !== null && (!budget || budget.schema_version !== 1 || !['pending','reserved','completed','failed','uncertain','skipped'].includes(budget.state) || budget.quote_hold !== true)) throw Error('Automatic budget status has an unsupported format. Reload before sending.');
}

export async function fetchCrmList({ base, key, resource, params = {}, signal, request = fetch }) {
  const rows = new Map();
  let page;
  const cursors = new Set();
  for (let count = 0; count < 20; count++) {
    const query = new URLSearchParams(params);
    if (page) query.set('page', page);
    const response = await request(`${base}/jt-${resource}?${query}`, {
      headers: { 'x-api-key': key }, signal: AbortSignal.any([signal, AbortSignal.timeout(15000)]),
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
