/**
 * sr_analyzer adapter — outbound HTTP to the DataX SR board service.
 *
 * sr_analyzer (a standalone Podman container at 127.0.0.1:8788) owns the live
 * SR board: it polls DataX Firestore, mirrors the `status` field into canonical
 * phases (New/Open/Closed/Archive), and exposes the board over a thin REST API.
 * The gateway is a *consumer* of that board — it never touches Firestore itself,
 * so no firebase-admin dependency and no service-account creds live here. This
 * is the hexagonal port: swap sr_analyzer for any board service that answers the
 * same two endpoints and the datax tools are unchanged.
 *
 * Boundary validation is hand-written (the gateway has no zod dependency; same
 * manual-guard dialect as sr_analyzer's own server/api.ts). Anything that fails
 * a guard raises so the calling tool degrades to a structured error.
 */

const DEFAULT_TIMEOUT_MS = 5000;

/** One board column. `name` is the human title; `position` orders columns. */
export interface AnalyzerPhase {
  id: string;
  name: string;
  position: number;
}

/** Subset of sr_analyzer's Ticket the SR tile renders. `externalId` is the
 * Firestore webRequests doc id — the join key into the gauntlet ledger. */
export interface AnalyzerTicket {
  id: string;
  phaseId: string;
  title: string;
  status: string;
  priority: string;
  submitterName: string | null;
  externalId: string | null;
  needsReply: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface AnalyzerBoard {
  phases: AnalyzerPhase[];
  tickets: AnalyzerTicket[];
}

/** Last-observed DataX→Firestore import result (sr_analyzer's poller). */
export interface AnalyzerImportStatus {
  inflight: boolean;
  lastRunAt: string | null;
  lastResult: {
    total: number;
    candidates: number;
    imported: number;
    updated: number;
    skipped: number;
  } | null;
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

async function getJson(url: string, timeoutMs: number): Promise<unknown> {
  let resp: Response;
  try {
    resp = await fetch(url, { signal: AbortSignal.timeout(timeoutMs) });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`sr_analyzer unreachable at ${url}: ${reason}`);
  }
  if (!resp.ok) {
    throw new Error(`sr_analyzer ${url} returned HTTP ${resp.status}`);
  }
  return resp.json();
}

function coerceTicket(raw: unknown): AnalyzerTicket | null {
  if (!isObject(raw)) return null;
  if (typeof raw.id !== "string" || typeof raw.phaseId !== "string") return null;
  return {
    id: raw.id,
    phaseId: raw.phaseId,
    title: typeof raw.title === "string" ? raw.title : "(untitled)",
    status: typeof raw.status === "string" ? raw.status : "",
    priority: typeof raw.priority === "string" ? raw.priority : "",
    submitterName: typeof raw.submitterName === "string" ? raw.submitterName : null,
    externalId: typeof raw.externalId === "string" ? raw.externalId : null,
    needsReply: raw.needsReply === true,
    createdAt: typeof raw.createdAt === "string" ? raw.createdAt : "",
    updatedAt: typeof raw.updatedAt === "string" ? raw.updatedAt : "",
  };
}

/** GET <base>/api/board → validated board snapshot. Throws on transport,
 * bad status, or a response that isn't a recognizable board. */
export async function fetchBoard(
  baseUrl: string,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<AnalyzerBoard> {
  const body = await getJson(`${baseUrl.replace(/\/$/, "")}/api/board`, timeoutMs);
  if (!isObject(body) || !Array.isArray(body.phases) || !Array.isArray(body.tickets)) {
    throw new Error("sr_analyzer /api/board did not return {phases, tickets}");
  }
  const phases: AnalyzerPhase[] = body.phases
    .filter(isObject)
    .filter((p) => typeof p.id === "string" && typeof p.name === "string")
    .map((p) => ({
      id: p.id as string,
      name: p.name as string,
      position: typeof p.position === "number" ? p.position : 0,
    }));
  const tickets = body.tickets.map(coerceTicket).filter((t): t is AnalyzerTicket => t !== null);
  return { phases, tickets };
}

/** Shared JSON-body request for the write endpoints. Throws on transport or
 * non-2xx (the caller surfaces it as a tool error — writes fail loud). */
async function sendJson(
  url: string,
  method: "PATCH" | "POST" | "DELETE",
  body: unknown,
  timeoutMs: number,
): Promise<unknown> {
  let resp: Response;
  try {
    resp = await fetch(url, {
      method,
      headers: body === undefined ? {} : { "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (err) {
    const reason = err instanceof Error ? err.message : String(err);
    throw new Error(`sr_analyzer unreachable at ${url}: ${reason}`);
  }
  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(`sr_analyzer ${method} ${url} → HTTP ${resp.status}: ${text.slice(0, 200)}`);
  }
  return resp.status === 204 ? null : resp.json().catch(() => null);
}

/** PATCH <base>/api/tickets/:id/move — move a ticket to another phase
 * (toIndex 0 = top of the column; the board sorts by updatedAt anyway). */
export async function moveTicket(
  baseUrl: string,
  ticketId: string,
  toPhaseId: string,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<unknown> {
  return sendJson(
    `${baseUrl.replace(/\/$/, "")}/api/tickets/${encodeURIComponent(ticketId)}/move`,
    "PATCH",
    { toPhaseId, toIndex: 0 },
    timeoutMs,
  );
}

/** DELETE <base>/api/tickets/:id — remove a ticket from the board. */
export async function deleteTicket(
  baseUrl: string,
  ticketId: string,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<unknown> {
  return sendJson(
    `${baseUrl.replace(/\/$/, "")}/api/tickets/${encodeURIComponent(ticketId)}`,
    "DELETE",
    undefined,
    timeoutMs,
  );
}

/** POST <base>/api/triage/all — re-run the analyzer's own triage pass over
 * all tickets (its rules engine, not an LLM in this process). Can take a few
 * seconds on a big board, so give it a longer leash. */
export async function triageAll(
  baseUrl: string,
  timeoutMs: number = 30_000,
): Promise<unknown> {
  return sendJson(`${baseUrl.replace(/\/$/, "")}/api/triage/all`, "POST", {}, timeoutMs);
}

/** GET <base>/api/import/datax/status → last-observed Firestore sync.
 * This is the reachability signal the API-Health tile reads: a fresh
 * `lastRunAt` means the poller successfully read Firestore recently. */
export async function fetchImportStatus(
  baseUrl: string,
  timeoutMs: number = DEFAULT_TIMEOUT_MS,
): Promise<AnalyzerImportStatus> {
  const body = await getJson(
    `${baseUrl.replace(/\/$/, "")}/api/import/datax/status`,
    timeoutMs,
  );
  if (!isObject(body)) {
    throw new Error("sr_analyzer /api/import/datax/status did not return an object");
  }
  const lr = body.lastResult;
  return {
    inflight: body.inflight === true,
    lastRunAt: typeof body.lastRunAt === "string" ? body.lastRunAt : null,
    lastResult: isObject(lr)
      ? {
          total: Number(lr.total) || 0,
          candidates: Number(lr.candidates) || 0,
          imported: Number(lr.imported) || 0,
          updated: Number(lr.updated) || 0,
          skipped: Number(lr.skipped) || 0,
        }
      : null,
  };
}
