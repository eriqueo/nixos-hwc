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
  return data;
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
