// Authenticated list boundary. Bounded to 20 pages; fail visibly instead of truncating.
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
