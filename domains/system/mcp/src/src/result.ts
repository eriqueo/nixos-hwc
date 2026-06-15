/**
 * Universal Result Contract helpers.
 *
 * `contract(kind, title, data, meta)` builds a ResultEnvelope — the
 * render-ready, self-describing view a tool attaches to its ToolResult.view.
 * backend-manager emits it as MCP `structuredContent` (dual-emit alongside the
 * legacy text block). Keep `data` to the kind's canonical fields; push
 * producer noise (status/message/counts/timing) into `meta`.
 *
 * Spec + per-kind field shapes: brain note universal_result_contract_schema.
 */
import type { ResultEnvelope, ViewKind } from "./types.js";

export const CONTRACT_VERSION = "1";

export function contract<T>(
  kind: ViewKind,
  title: string,
  data: T,
  meta: Record<string, unknown> = {},
): ResultEnvelope<T> {
  return { kind, title, data, meta: { contract: CONTRACT_VERSION, ...meta } };
}

/**
 * Strip a value to a string id; returns "" when absent so callers can decide
 * whether a row is selectable (the entity rule: truthy id ⇒ selectable).
 */
export function asId(value: unknown): string {
  return value == null ? "" : String(value);
}
