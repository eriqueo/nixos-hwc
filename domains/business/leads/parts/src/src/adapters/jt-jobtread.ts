/**
 * JobTread Pave adapter.
 *
 * POSTs JSON-encoded GraphQL ("Pave") trees to https://api.jobtread.com/pave
 * for the five-step graph: createAccount → createLocation → createContact
 * → createJob → createComment. Idempotent: skips any step whose target
 * id is already present in `existingIds`.
 *
 * Failures partway through return whatever IDs DID get created so the
 * caller can persist partial progress and resume later.
 *
 * Network errors / 5xx → `retryable: true`. GraphQL errors → terminal
 * (the data is bad; retrying won't help).
 */

import type { JtClient, JtIds, JtGraphResult } from "../ports/jt.js";
import type { Lead } from "../core/types.js";
import type { Logger } from "../ports/log.js";
import type { JtMappings, PaveQuery } from "../core/jt-graph.js";
import {
  buildCreateAccountQuery,
  buildCreateLocationQuery,
  buildCreateContactQuery,
  buildCreateJobQuery,
  buildCreateCommentQuery,
} from "../core/jt-graph.js";

const PAVE_URL = "https://api.jobtread.com/pave";
const DEFAULT_TIMEOUT_MS = 15_000;

export interface JtJobtreadAdapterOpts {
  readonly grantKey: string;
  readonly mappings: JtMappings;
  readonly log: Logger;
  readonly timeoutMs?: number;
}

type PaveStep = "account" | "location" | "contact" | "job" | "comment";

interface PaveError {
  readonly retryable: boolean;
  readonly message: string;
}

/** Wrap fetch with a hard timeout via AbortController. */
async function paveCall(
  query: PaveQuery,
  timeoutMs: number,
  log: Logger,
  step: PaveStep,
): Promise<unknown | PaveError> {
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const res = await fetch(PAVE_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ query }),
      signal: ac.signal,
    });
    if (res.status >= 500) {
      const body = await res.text().catch(() => "");
      return {
        retryable: true,
        message: `Pave ${step} HTTP ${res.status}: ${body.slice(0, 200)}`,
      };
    }
    const json = (await res.json().catch(() => null)) as Record<string, unknown> | null;
    if (json === null) {
      return { retryable: false, message: `Pave ${step}: non-JSON response` };
    }
    if ("error" in json && json["error"]) {
      return {
        retryable: false,
        message: `Pave ${step} error: ${JSON.stringify(json["error"]).slice(0, 200)}`,
      };
    }
    if (res.status >= 400) {
      return {
        retryable: false,
        message: `Pave ${step} HTTP ${res.status}: ${JSON.stringify(json).slice(0, 200)}`,
      };
    }
    log.debug("pave call ok", { step, status: res.status });
    return json;
  } catch (err) {
    const name = err instanceof Error ? err.name : "Error";
    const msg = err instanceof Error ? err.message : String(err);
    // AbortError / network errors are retryable.
    return { retryable: true, message: `Pave ${step}: ${name} ${msg}` };
  } finally {
    clearTimeout(timer);
  }
}

function isErr(v: unknown | PaveError): v is PaveError {
  return typeof v === "object" && v !== null && "retryable" in v && "message" in v;
}

/** Extract a JT id from the Pave response. */
function extractId(response: unknown, op: string, returned: string): string | undefined {
  if (typeof response !== "object" || response === null) return undefined;
  const opNode = (response as Record<string, unknown>)[op];
  if (typeof opNode !== "object" || opNode === null) return undefined;
  const retNode = (opNode as Record<string, unknown>)[returned];
  if (typeof retNode !== "object" || retNode === null) return undefined;
  const id = (retNode as Record<string, unknown>)["id"];
  return typeof id === "string" ? id : undefined;
}

export function makeJtJobtreadAdapter(opts: JtJobtreadAdapterOpts): JtClient {
  const timeout = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;

  return {
    async createGraph(lead: Lead, existingIds: JtIds): Promise<JtGraphResult> {
      // Local mutable copy — JtIds is readonly externally, but the
      // chain mutates as each step completes.
      const ids: { -readonly [K in keyof JtIds]: JtIds[K] } = { ...existingIds };

      // ── 1. Account ──
      if (!ids.accountId) {
        const q = buildCreateAccountQuery(opts.grantKey, lead, opts.mappings);
        const r = await paveCall(q, timeout, opts.log, "account");
        if (isErr(r)) {
          return { ids, complete: false, failedAt: "account", error: r.message, retryable: r.retryable };
        }
        const id = extractId(r, "createAccount", "createdAccount");
        if (!id) {
          return { ids, complete: false, failedAt: "account", error: "no account id in response", retryable: false };
        }
        ids.accountId = id;
        opts.log.info("jt account created", { leadId: lead.id, accountId: id });
      }

      // ── 2. Location ──
      if (!ids.locationId) {
        const q = buildCreateLocationQuery(opts.grantKey, opts.mappings, ids.accountId);
        const r = await paveCall(q, timeout, opts.log, "location");
        if (isErr(r)) {
          return { ids, complete: false, failedAt: "location", error: r.message, retryable: r.retryable };
        }
        const id = extractId(r, "createLocation", "createdLocation");
        if (!id) {
          return { ids, complete: false, failedAt: "location", error: "no location id in response", retryable: false };
        }
        ids.locationId = id;
        opts.log.info("jt location created", { leadId: lead.id, locationId: id });
      }

      // ── 3. Contact ──
      if (!ids.contactId) {
        const q = buildCreateContactQuery(opts.grantKey, lead, opts.mappings, ids.accountId);
        const r = await paveCall(q, timeout, opts.log, "contact");
        if (isErr(r)) {
          return { ids, complete: false, failedAt: "contact", error: r.message, retryable: r.retryable };
        }
        const id = extractId(r, "createContact", "createdContact");
        if (!id) {
          return { ids, complete: false, failedAt: "contact", error: "no contact id in response", retryable: false };
        }
        ids.contactId = id;
        opts.log.info("jt contact created", { leadId: lead.id, contactId: id });
      }

      // ── 4. Job ──
      if (!ids.jobId) {
        const q = buildCreateJobQuery(opts.grantKey, lead, ids.locationId);
        const r = await paveCall(q, timeout, opts.log, "job");
        if (isErr(r)) {
          return { ids, complete: false, failedAt: "job", error: r.message, retryable: r.retryable };
        }
        const id = extractId(r, "createJob", "createdJob");
        if (!id) {
          return { ids, complete: false, failedAt: "job", error: "no job id in response", retryable: false };
        }
        ids.jobId = id;
        opts.log.info("jt job created", { leadId: lead.id, jobId: id });
      }

      // ── 5. Comment ──
      if (!ids.commentId) {
        const q = buildCreateCommentQuery(opts.grantKey, lead, ids.jobId);
        const r = await paveCall(q, timeout, opts.log, "comment");
        if (isErr(r)) {
          return { ids, complete: false, failedAt: "comment", error: r.message, retryable: r.retryable };
        }
        const id = extractId(r, "createComment", "createdComment") ?? "";
        ids.commentId = id;
        opts.log.info("jt comment created", { leadId: lead.id, commentId: id });
      }

      return { ids, complete: true };
    },
  };
}
