/**
 * PAVE API client — handles all communication with JobTread's PAVE API.
 *
 * Key responsibilities:
 * - Builds PAVE request envelopes with grantKey auth in body (NOT header)
 * - All requests are POST to apiUrl with { query: { $: { grantKey, ... }, ...ops } }
 * - Sends requests with retry + exponential backoff
 * - Detects PAVE's 200-with-errors pattern
 * - Extracts nested responses to clean structures
 * - Logs every call for audit trail
 */

import type { Config } from "../config.js";
import type {
  PaveResponse,
  PaveFields,
  PaveWhere,
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
   * Low-level: send a PAVE query and return the raw response.
   * Builds the { query: { $: { grantKey, ... }, ...operations } } envelope.
   */
  async execute<T = unknown>(
    operations: Record<string, unknown>,
    options?: { notify?: boolean }
  ): Promise<ToolResult<T>> {
    const envelope = {
      query: {
        $: {
          grantKey: this.grantKey,
          notify: options?.notify ?? false,
          viaUserId: this.userId,
        },
        ...operations,
      },
    };

    const opNames = Object.keys(operations).join(", ");
    const startMs = Date.now();
    let lastError: Error | null = null;

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      if (attempt > 0) {
        const delay = BASE_DELAY_MS * Math.pow(2, attempt - 1);
        log.warn("Retrying PAVE request", {
          attempt,
          delay,
          operations: opNames,
        });
        await sleep(delay);
      }

      try {
        const response = await this.sendRequest(envelope);
        const durationMs = Date.now() - startMs;

        // PAVE returns HTTP 200 even for errors — check the response body
        if (response.errors && (response.errors as Array<{ message: string }>).length > 0) {
          const errors = response.errors as Array<{ message: string }>;
          const errorMsg = errors.map((e) => e.message).join("; ");
          log.error("PAVE API returned errors", {
            operations: opNames,
            errors,
            durationMs,
          });
          return {
            success: false,
            error: errorMsg,
            code: "PAVE_ERROR",
            details: { errors },
          };
        }

        log.info("PAVE request succeeded", {
          operations: opNames,
          durationMs,
        });

        // Return the full response (minus errors key) as data
        const { errors: _errors, ...data } = response;
        return {
          success: true,
          data: data as T,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        log.error("PAVE request failed", {
          operations: opNames,
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
   * Create an entity.
   * operationName examples: "createAccount", "createJob", "addBudgetLineItems"
   * returnKey overrides the default "created" + entityPart extraction.
   */
  async create<T = unknown>(
    operationName: string,
    params: Record<string, unknown>,
    returnFields?: PaveFields,
    options?: { returnKey?: string; skipOrgId?: boolean }
  ): Promise<ToolResult<T>> {
    // Add organizationId unless explicitly skipped
    const paramsWithOrg = options?.skipOrgId
      ? { ...params }
      : { organizationId: this.orgId, ...params };

    // Determine the return key
    // "createAccount" → "createdAccount"
    // "addBudgetLineItems" → "addedBudgetLineItems"
    let returnKey = options?.returnKey;
    if (!returnKey && returnFields) {
      if (operationName.startsWith("create")) {
        returnKey = operationName.replace("create", "created");
      } else if (operationName.startsWith("add")) {
        returnKey = operationName.replace(/^add/, "added");
      } else {
        // Fallback: just use the operationName itself
        returnKey = operationName;
      }
    }

    const operationBody: Record<string, unknown> = { $: paramsWithOrg };
    if (returnFields && returnKey) {
      operationBody[returnKey] = returnFields;
    }

    const operation = { [operationName]: operationBody };
    const result = await this.execute<Record<string, unknown>>(operation, { notify: false });

    if (result.success && result.data && returnKey) {
      const opResult = result.data[operationName] as Record<string, unknown> | undefined;
      return { success: true, data: (opResult?.[returnKey] ?? opResult) as T };
    }
    return result as ToolResult<T>;
  }

  /**
   * Update an entity.
   * operationName examples: "updateAccount", "updateDocument", "setJobParameters"
   */
  async update<T = unknown>(
    operationName: string,
    params: Record<string, unknown>,
    returnFields?: PaveFields,
    options?: { returnKey?: string }
  ): Promise<ToolResult<T>> {
    // Return key for updates: entity name without "update" prefix, lowercased first char
    // e.g., "updateAccount" → "account", "setJobParameters" → use override
    let returnKey = options?.returnKey;
    if (!returnKey && returnFields) {
      if (operationName.startsWith("update")) {
        const entityName = operationName.replace("update", "");
        returnKey = entityName.charAt(0).toLowerCase() + entityName.slice(1);
      } else {
        returnKey = operationName;
      }
    }

    const operationBody: Record<string, unknown> = { $: params };
    if (returnFields && returnKey) {
      operationBody[returnKey] = returnFields;
    }

    const operation = { [operationName]: operationBody };
    const result = await this.execute<Record<string, unknown>>(operation, { notify: false });

    if (result.success && result.data && returnKey) {
      const opResult = result.data[operationName] as Record<string, unknown> | undefined;
      return { success: true, data: (opResult?.[returnKey] ?? opResult) as T };
    }
    return result as ToolResult<T>;
  }

  /**
   * Read a single entity by ID using the node query.
   * entityType is used for the "... on EntityType" syntax (auto-capitalized).
   */
  async read<T = unknown>(
    entityType: string,
    id: string,
    returnFields: PaveFields
  ): Promise<ToolResult<T>> {
    const typeName = entityType.charAt(0).toUpperCase() + entityType.slice(1);
    const operation = {
      node: {
        $: { id },
        [`... on ${typeName}`]: returnFields,
      },
    };

    const result = await this.execute<Record<string, unknown>>(operation);
    if (result.success && result.data) {
      const nodeResult = result.data["node"] as Record<string, unknown> | undefined;
      return { success: true, data: nodeResult as T };
    }
    return result as ToolResult<T>;
  }

  /**
   * Query entities through the organization.
   * entityPlural: "accounts", "jobs", "contacts", etc.
   */
  async query<T = unknown>(opts: {
    entityPlural: string;
    returnFields: PaveFields;
    where?: PaveWhere;
    size?: number;
    after?: string;
    sort?: Record<string, string>;
  }): Promise<ToolResult<T>> {
    const entityParams: Record<string, unknown> = {};
    if (opts.where) entityParams.where = opts.where;
    if (opts.size) entityParams.size = opts.size;
    if (opts.after) entityParams.after = opts.after;
    if (opts.sort) entityParams.sort = opts.sort;

    const operation = {
      organization: {
        $: {},
        [opts.entityPlural]: {
          $: Object.keys(entityParams).length > 0 ? entityParams : {},
          nodes: opts.returnFields,
        },
      },
    };

    const result = await this.execute<Record<string, unknown>>(operation);
    if (result.success && result.data) {
      const org = result.data["organization"] as Record<string, unknown> | undefined;
      const entities = org?.[opts.entityPlural] as { nodes?: unknown[] } | undefined;
      return { success: true, data: (entities?.nodes ?? entities) as T };
    }
    return result as ToolResult<T>;
  }

  /**
   * Delete an entity.
   * operationName: "deleteAccount", "deleteJob", etc.
   */
  async delete(
    operationName: string,
    id: string
  ): Promise<ToolResult> {
    const operation = {
      [operationName]: { $: { id } },
    };
    return this.execute(operation, { notify: false });
  }

  /**
   * Send raw PAVE query for operations that don't fit the patterns above.
   */
  async raw<T = unknown>(operations: Record<string, unknown>): Promise<ToolResult<T>> {
    return this.execute<T>(operations);
  }

  private async sendRequest(envelope: Record<string, unknown>): Promise<PaveResponse> {
    const response = await fetch(this.apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(envelope),
    });

    if (!response.ok) {
      const body = await response.text();
      log.error("PAVE HTTP error response", {
        status: response.status,
        body: body.slice(0, 500),
      });
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
