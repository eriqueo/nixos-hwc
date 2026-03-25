/**
 * PAVE API client — handles all communication with JobTread's PAVE API.
 *
 * Key responsibilities:
 * - Builds PAVE request envelopes with auth injection
 * - Sends requests with retry + exponential backoff
 * - Detects PAVE's 200-with-errors pattern
 * - Flattens nested responses to clean structures
 * - Logs every call for audit trail
 */

import type { Config } from "../config.js";
import type {
  PaveRequest,
  PaveResponse,
  PaveAction,
  PaveField,
  PaveFilter,
  PaveSort,
  ToolResult,
} from "./types.js";
import { log } from "../logging/logger.js";

const MAX_RETRIES = 3;
const BASE_DELAY_MS = 1000;

export class PaveClient {
  private apiUrl: string;
  private grantKey: string;
  private orgId: string;
  private userId: string;

  constructor(config: Config["jt"]) {
    this.apiUrl = config.apiUrl;
    this.grantKey = config.grantKey;
    this.orgId = config.orgId;
    this.userId = config.userId;
  }

  /**
   * Execute a PAVE API call with automatic auth, retries, and error detection.
   */
  async execute<T = unknown>(
    request: Omit<PaveRequest, "organizationId" | "userId" | "notify">
  ): Promise<ToolResult<T>> {
    const envelope: PaveRequest = {
      ...request,
      organizationId: this.orgId,
      userId: this.userId,
      notify: false,
    };

    const startMs = Date.now();
    let lastError: Error | null = null;

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      if (attempt > 0) {
        const delay = BASE_DELAY_MS * Math.pow(2, attempt - 1);
        log.warn("Retrying PAVE request", {
          attempt,
          delay,
          action: envelope.action,
          entity: envelope.entity,
        });
        await sleep(delay);
      }

      try {
        const response = await this.sendRequest(envelope);
        const durationMs = Date.now() - startMs;

        // PAVE returns HTTP 200 even for errors — check the response body
        if (response.errors && response.errors.length > 0) {
          const errorMsg = response.errors
            .map((e) => e.message)
            .join("; ");
          log.error("PAVE API returned errors", {
            action: envelope.action,
            entity: envelope.entity,
            errors: response.errors,
            durationMs,
          });
          return {
            success: false,
            error: errorMsg,
            code: "PAVE_ERROR",
            details: { errors: response.errors },
          };
        }

        log.info("PAVE request succeeded", {
          action: envelope.action,
          entity: envelope.entity,
          durationMs,
        });

        return {
          success: true,
          data: response.data as T,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        log.error("PAVE request failed", {
          action: envelope.action,
          entity: envelope.entity,
          attempt,
          error: lastError.message,
        });

        // Only retry on network/transient errors
        if (!isTransientError(lastError)) {
          break;
        }
      }
    }

    return {
      success: false,
      error: lastError?.message ?? "Unknown error",
      code: "NETWORK_ERROR",
    };
  }

  /**
   * Convenience: query entities with field selection and filtering.
   */
  async query<T = unknown>(opts: {
    entity: string;
    fields?: PaveField[];
    filter?: PaveFilter;
    sort?: PaveSort[];
    limit?: number;
    offset?: number;
  }): Promise<ToolResult<T>> {
    return this.execute<T>({
      action: "query",
      entity: opts.entity,
      fields: opts.fields,
      filter: opts.filter,
      sort: opts.sort,
      limit: opts.limit,
      offset: opts.offset,
    });
  }

  /**
   * Convenience: create an entity.
   */
  async create<T = unknown>(
    entity: string,
    data: Record<string, unknown>,
    fields?: PaveField[]
  ): Promise<ToolResult<T>> {
    return this.execute<T>({
      action: "create",
      entity,
      data,
      fields,
    });
  }

  /**
   * Convenience: read a single entity by ID.
   */
  async read<T = unknown>(
    entity: string,
    id: string,
    fields?: PaveField[]
  ): Promise<ToolResult<T>> {
    return this.execute<T>({
      action: "read",
      entity,
      data: { id },
      fields,
    });
  }

  /**
   * Convenience: update an entity.
   */
  async update<T = unknown>(
    entity: string,
    id: string,
    data: Record<string, unknown>,
    fields?: PaveField[]
  ): Promise<ToolResult<T>> {
    return this.execute<T>({
      action: "update",
      entity,
      data: { id, ...data },
      fields,
    });
  }

  private async sendRequest(envelope: PaveRequest): Promise<PaveResponse> {
    const response = await fetch(this.apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.grantKey}`,
      },
      body: JSON.stringify(envelope),
    });

    if (!response.ok) {
      throw new Error(
        `PAVE HTTP ${response.status}: ${response.statusText}`
      );
    }

    return (await response.json()) as PaveResponse;
  }
}

function isTransientError(error: Error): boolean {
  const msg = error.message.toLowerCase();
  return (
    msg.includes("econnreset") ||
    msg.includes("econnrefused") ||
    msg.includes("etimedout") ||
    msg.includes("socket hang up") ||
    msg.includes("fetch failed") ||
    msg.includes("network") ||
    msg.includes("503") ||
    msg.includes("502") ||
    msg.includes("429")
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
