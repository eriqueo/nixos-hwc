/**
 * JT webhook push helper.
 *
 * Posts an estimate payload to the n8n estimate-push webhook and throws
 * a structured JtPushError on any non-2xx response or network failure.
 * Callers (currently EstimateTab; soon a hexagonal output port) get a
 * single, typed failure mode to handle instead of mixing fetch quirks
 * into the UI layer.
 */
import { JtPushError } from '../errors/index.js';

export async function pushEstimateToJt({ url, apiKey, payload, fetchImpl = fetch }) {
  if (!url) throw new JtPushError('No webhook URL configured', { status: null });
  if (!apiKey) throw new JtPushError('No API key configured', { status: null });

  let response;
  try {
    response = await fetchImpl(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    throw new JtPushError(`JT push network failure: ${e.message}`, { status: null, cause: e });
  }

  const body = await response.text();
  if (!response.ok) {
    throw new JtPushError(
      `JT push failed: HTTP ${response.status}`,
      { status: response.status, body },
    );
  }
  try { return JSON.parse(body); } catch { return body; }
}
