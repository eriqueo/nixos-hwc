/**
 * PAVE API client — handles all communication with JobTread's PAVE API.
 *
 * Key responsibilities:
 * - Builds PAVE graph query/mutation payloads with grantKey auth
 * - Sends requests with retry + exponential backoff
 * - Detects PAVE's errors field in response
 * - Extracts data from nested response structure
 * - Logs every call for audit trail
 *
 * PAVE graph query format:
 *   { query: { $: { grantKey }, organization: { $: {}, accounts: { $: { size, where }, nodes: { id: {}, name: {} } } } } }
 *
 * PAVE where format:
 *   { and: [[ ["fieldName", "operator", value], ... ]] }
 */

import type { Config } from "../config.js";
import type {
  PaveOperation,
  PaveResponse,
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

  constructor(config: Config["jt"]) {
    this.apiUrl = config.apiUrl;
    this.grantKey = config.grantKey;
  }

  /**
   * Execute a PAVE API call with automatic auth, retries, and error detection.
   */
  async execute<T = unknown>(
    operation: Omit<PaveOperation, "organizationId" | "userId" | "notify">
  ): Promise<ToolResult<T>> {
    const payload = this.buildPayload(operation);
    const startMs = Date.now();
    let lastError: Error | null = null;

    for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
      if (attempt > 0) {
        const delay = BASE_DELAY_MS * Math.pow(2, attempt - 1);
        log.warn("Retrying PAVE request", {
          attempt,
          delay,
          action: operation.action,
          entity: operation.entity,
        });
        await sleep(delay);
      }

      try {
        const response = await this.sendRequest(payload);
        const durationMs = Date.now() - startMs;

        if (response.errors && response.errors.length > 0) {
          const errorMsg = response.errors
            .map((e) => e.message)
            .join("; ");
          log.error("PAVE API returned errors", {
            action: operation.action,
            entity: operation.entity,
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
          action: operation.action,
          entity: operation.entity,
          durationMs,
        });

        const extracted = this.extractData(response.data, operation);
        return {
          success: true,
          data: extracted as T,
        };
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        log.error("PAVE request failed", {
          action: operation.action,
          entity: operation.entity,
          attempt,
          error: lastError.message,
        });

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

  /**
   * Build the PAVE graph JSON payload from an internal operation.
   *
   * Query:
   *   { query: { $: { grantKey }, organization: { $: {}, accounts: { $: { size, where }, nodes: {...} } } } }
   *
   * Read (single):
   *   { query: { $: { grantKey }, organization: { $: {}, account: { $: { id }, ...fields } } } }
   *
   * Mutation:
   *   { mutation: { $: { grantKey }, createAccount: { $: { ...data }, ...fields } } }
   */
  private buildPayload(op: Omit<PaveOperation, "organizationId" | "userId" | "notify">): unknown {
    const { action, entity, data, fields, filter, sort, limit, offset } = op;
    const nodes = fields ? fieldsToNodes(fields) : {};

    if (action === "query") {
      const entityKey = pluralize(entity);
      const params: Record<string, unknown> = {
        size: limit ?? 25,
      };
      if (offset !== undefined) params.offset = offset;
      if (filter) params.where = filterToWhere(filter);
      if (sort && sort.length > 0) params.sort = sortToPave(sort);

      return {
        query: {
          $: { grantKey: this.grantKey },
          organization: {
            $: {},
            [entityKey]: {
              $: params,
              nodes,
            },
          },
        },
      };
    }

    if (action === "read") {
      return {
        query: {
          $: { grantKey: this.grantKey },
          organization: {
            $: {},
            [entity]: {
              $: { id: data?.id },
              ...nodes,
            },
          },
        },
      };
    }

    const entityPascal = entity[0].toUpperCase() + entity.slice(1);

    if (action === "create") {
      return {
        mutation: {
          $: { grantKey: this.grantKey },
          [`create${entityPascal}`]: {
            $: { ...data },
            ...nodes,
          },
        },
      };
    }

    if (action === "update") {
      return {
        mutation: {
          $: { grantKey: this.grantKey },
          [`update${entityPascal}`]: {
            $: { ...data },
            ...nodes,
          },
        },
      };
    }

    if (action === "delete") {
      return {
        mutation: {
          $: { grantKey: this.grantKey },
          [`delete${entityPascal}`]: {
            $: { id: data?.id },
          },
        },
      };
    }

    throw new Error(`Unknown action: ${action}`);
  }

  /**
   * Extract the relevant data node from a PAVE graph response.
   *
   * Query response: { data: { query: { organization: { accounts: { nodes: [...] } } } } }
   * Read response:  { data: { query: { organization: { account: { id, name, ... } } } } }
   * Mutation response: { data: { mutation: { createAccount: { id, name, ... } } } }
   */
  private extractData(responseData: unknown, op: Omit<PaveOperation, "organizationId" | "userId" | "notify">): unknown {
    const { action, entity } = op;
    const d = responseData as Record<string, unknown> | null | undefined;
    if (!d) return null;

    if (action === "query") {
      const org = ((d.query as Record<string, unknown>)?.organization as Record<string, unknown>);
      const entityData = org?.[pluralize(entity)] as Record<string, unknown> | undefined;
      // Return nodes array if present, otherwise the entity data itself
      return entityData?.nodes ?? entityData ?? null;
    }

    if (action === "read") {
      const org = ((d.query as Record<string, unknown>)?.organization as Record<string, unknown>);
      return org?.[entity] ?? null;
    }

    const entityPascal = entity[0].toUpperCase() + entity.slice(1);

    if (action === "create") {
      return (d.mutation as Record<string, unknown>)?.[`create${entityPascal}`] ?? null;
    }

    if (action === "update") {
      return (d.mutation as Record<string, unknown>)?.[`update${entityPascal}`] ?? null;
    }

    return null;
  }

  private async sendRequest(payload: unknown): Promise<PaveResponse> {
    const response = await fetch(this.apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(
        `PAVE HTTP ${response.status}: ${response.statusText}`
      );
    }

    return (await response.json()) as PaveResponse;
  }
}

/**
 * Convert internal PaveFilter to PAVE where clause format.
 * PAVE format: { "and": [[ ["field", "op", value], ... ]] }
 */
function filterToWhere(filter: PaveFilter): unknown {
  const conditions = (filter.conditions ?? []).map((c) => [
    c.field,
    operatorToSymbol(c.operator),
    c.value,
  ]);
  if (conditions.length === 0) return undefined;
  const op = filter.operator ?? "and";
  return { [op]: [conditions] };
}

function operatorToSymbol(op: string): string {
  const map: Record<string, string> = {
    eq: "=",
    neq: "!=",
    gt: ">",
    gte: ">=",
    lt: "<",
    lte: "<=",
    like: "like",
    in: "in",
    nin: "nin",
    null: "null",
    notNull: "notNull",
  };
  return map[op] ?? op;
}

/**
 * Convert internal PaveSort[] to PAVE sort format.
 */
function sortToPave(sort: PaveSort[]): unknown {
  return sort.map((s) => ({ field: s.field, direction: s.direction }));
}

/**
 * Convert PaveField[] to PAVE nodes object: { fieldName: {} } or { fieldName: { nodes: {...} } }
 */
function fieldsToNodes(fields: PaveField[]): Record<string, unknown> {
  const nodes: Record<string, unknown> = {};
  for (const field of fields) {
    if (field.fields && field.fields.length > 0) {
      // Nested fields — use { nodes: {...} } for collections
      nodes[field.field] = { nodes: fieldsToNodes(field.fields) };
    } else {
      nodes[field.field] = {};
    }
  }
  return nodes;
}

/**
 * Pluralize an entity name for PAVE collection queries.
 */
function pluralize(entity: string): string {
  const map: Record<string, string> = {
    timeEntry: "timeEntries",
    dailyLog: "dailyLogs",
    costItem: "costItems",
    costCode: "costCodes",
    costType: "costTypes",
    costGroup: "costGroups",
    costGroupTemplate: "costGroupTemplates",
    customField: "customFields",
    fileTag: "fileTags",
    scheduleTemplate: "scheduleTemplates",
    todoTemplate: "todoTemplates",
    taskTemplate: "taskTemplates",
    documentTemplate: "documentTemplates",
  };
  return map[entity] ?? `${entity}s`;
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
