/**
 * Prometheus HTTP API client — instant and range queries.
 */

import { log } from "../log.js";

const PROMETHEUS_URL = "http://localhost:9090";

interface PrometheusResult {
  status: string;
  data: {
    resultType: string;
    result: Array<{
      metric: Record<string, string>;
      value?: [number, string];
      values?: Array<[number, string]>;
    }>;
  };
}

/**
 * Execute an instant PromQL query.
 */
export async function instantQuery(query: string): Promise<PrometheusResult> {
  const url = `${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`;
  log.debug("prometheus instant query", { query });

  const response = await fetch(url, { signal: AbortSignal.timeout(10000) });
  if (!response.ok) {
    throw new Error(`Prometheus query failed: ${response.status} ${response.statusText}`);
  }

  return response.json() as Promise<PrometheusResult>;
}

/**
 * Execute a range PromQL query.
 */
export async function rangeQuery(
  query: string,
  start: string,
  end: string,
  step: string = "60s"
): Promise<PrometheusResult> {
  const params = new URLSearchParams({
    query,
    start,
    end,
    step,
  });
  const url = `${PROMETHEUS_URL}/api/v1/query_range?${params}`;
  log.debug("prometheus range query", { query, start, end, step });

  const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
  if (!response.ok) {
    throw new Error(`Prometheus range query failed: ${response.status}`);
  }

  return response.json() as Promise<PrometheusResult>;
}
