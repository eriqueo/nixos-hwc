/**
 * JT webhook push helper.
 *
 * Posts an estimate payload to the n8n estimate-push webhook and throws
 * a structured JtPushError on any non-2xx response or network failure.
 */
import { JtPushError } from '../errors/index.js';

export interface PushEstimateArgs {
  url: string;
  apiKey: string;
  payload: unknown;
  fetchImpl?: typeof fetch;
}

export async function pushEstimateToJt({ url, apiKey, payload, fetchImpl = fetch }: PushEstimateArgs): Promise<unknown> {
  if (!url) throw new JtPushError('No webhook URL configured', { status: null });
  if (!apiKey) throw new JtPushError('No API key configured', { status: null });

  let response: Response;
  try {
    response = await fetchImpl(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    throw new JtPushError(`JT push network failure: ${(e as Error).message}`, { status: null, cause: e });
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
