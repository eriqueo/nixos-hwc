/**
 * N8N response transformer — cleans up bloated n8n-mcp tool responses
 * before they reach the LLM client.
 *
 * Every transform is wrapped in try/catch — a failed transform returns
 * the original data unchanged. Never break a response.
 */

/* ═══════════════════════════════════════════════════════════════════ */
/*  Tool-name sets                                                     */
/* ═══════════════════════════════════════════════════════════════════ */

const WORKFLOW_DETAIL_TOOLS = new Set([
  "n8n_get_workflow",
  "n8n_update_full_workflow",
  "n8n_create_workflow",
]);

/* ═══════════════════════════════════════════════════════════════════ */
/*  Global transforms (apply to every n8n response)                    */
/* ═══════════════════════════════════════════════════════════════════ */

/** Recursively flatten `{__rl: true, value: X, ...}` → X */
function flattenRl(obj: unknown): unknown {
  if (obj === null || obj === undefined) return obj;
  if (Array.isArray(obj)) return obj.map(flattenRl);
  if (typeof obj !== "object") return obj;

  const rec = obj as Record<string, unknown>;

  // __rl sentinel — replace entire object with its value
  if (rec.__rl === true && "value" in rec) {
    return flattenRl(rec.value);
  }

  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(rec)) {
    out[k] = flattenRl(v);
  }
  return out;
}

/** Remove keys whose value is an empty object `{}` */
function dropEmptyObjects(obj: unknown): unknown {
  if (obj === null || obj === undefined) return obj;
  if (Array.isArray(obj)) return obj.map(dropEmptyObjects);
  if (typeof obj !== "object") return obj;

  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    if (v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length === 0) {
      continue; // drop empty object
    }
    out[k] = dropEmptyObjects(v);
  }
  return out;
}

/** Strip `webhookId` from nodes that are NOT n8n-nodes-base.webhook */
function stripSpuriousWebhookIds(obj: unknown): unknown {
  if (obj === null || obj === undefined) return obj;
  if (Array.isArray(obj)) return obj.map(stripSpuriousWebhookIds);
  if (typeof obj !== "object") return obj;

  const rec = obj as Record<string, unknown>;
  const out: Record<string, unknown> = {};

  for (const [k, v] of Object.entries(rec)) {
    // If this looks like a node object with a type and webhookId
    if (k === "webhookId" && typeof rec.type === "string" && rec.type !== "n8n-nodes-base.webhook") {
      continue; // drop spurious webhookId
    }
    out[k] = stripSpuriousWebhookIds(v);
  }
  return out;
}

/**
 * Flatten tag arrays: [{id, name, createdAt, updatedAt}] → ["name1", "name2"]
 * Only applies to arrays named "tags" where elements have a "name" property.
 */
function flattenTags(obj: unknown): unknown {
  if (obj === null || obj === undefined) return obj;
  if (Array.isArray(obj)) return obj.map(flattenTags);
  if (typeof obj !== "object") return obj;

  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
    if (k === "tags" && Array.isArray(v) && v.length > 0 && v[0] && typeof v[0] === "object" && "name" in v[0]) {
      out[k] = v.map((t: Record<string, unknown>) => t.name);
    } else {
      out[k] = flattenTags(v);
    }
  }
  return out;
}

function applyGlobalTransforms(data: unknown): unknown {
  let result = data;
  result = flattenRl(result);
  result = dropEmptyObjects(result);
  result = stripSpuriousWebhookIds(result);
  result = flattenTags(result);
  return result;
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  Tool-specific transforms                                           */
/* ═══════════════════════════════════════════════════════════════════ */

/** n8n_get_workflow, n8n_update_full_workflow, n8n_create_workflow */
function transformWorkflowDetail(data: unknown): unknown {
  if (!data || typeof data !== "object") return data;
  const rec = data as Record<string, unknown>;

  delete rec.activeVersion;
  delete rec.shared;
  delete rec.versionId;
  delete rec.activeVersionId;
  delete rec.versionCounter;
  delete rec.triggerCount;

  if (rec.meta == null || (typeof rec.meta === "object" && Object.keys(rec.meta as object).length === 0)) {
    delete rec.meta;
  }
  if (rec.staticData == null || (typeof rec.staticData === "object" && Object.keys(rec.staticData as object).length === 0)) {
    delete rec.staticData;
  }
  if (rec.pinData == null || (typeof rec.pinData === "object" && Object.keys(rec.pinData as object).length === 0)) {
    delete rec.pinData;
  }
  if (rec.description === null || rec.description === undefined) {
    delete rec.description;
  }

  // Clean settings
  if (rec.settings && typeof rec.settings === "object") {
    const settings = rec.settings as Record<string, unknown>;
    delete settings.availableInMCP;
    delete settings.callerPolicy;
    // If settings is now empty, drop it
    if (Object.keys(settings).length === 0) delete rec.settings;
  }

  return rec;
}

/** n8n_list_workflows */
function transformListWorkflows(data: unknown): unknown {
  if (!data || typeof data !== "object") return data;
  const rec = data as Record<string, unknown>;

  // The response has a workflows array
  const workflows = rec.workflows as Array<Record<string, unknown>> | undefined;
  if (Array.isArray(workflows)) {
    for (const wf of workflows) {
      delete wf.createdAt;
      delete wf.updatedAt;
      if (wf.isArchived === false) delete wf.isArchived;
    }
  }

  return rec;
}

/** n8n_executions (action=list) */
function transformExecutions(data: unknown): unknown {
  if (!data || typeof data !== "object") return data;
  const rec = data as Record<string, unknown>;

  // May have results array or executions array
  const list = (rec.results ?? rec.executions) as Array<Record<string, unknown>> | undefined;
  if (Array.isArray(list)) {
    for (const ex of list) {
      if (ex.retryOf === null || ex.retryOf === undefined) delete ex.retryOf;
      if (ex.retrySuccessId === null || ex.retrySuccessId === undefined) delete ex.retrySuccessId;
    }
  }

  return rec;
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  Envelope helper                                                    */
/* ═══════════════════════════════════════════════════════════════════ */

/**
 * n8n-mcp wraps responses as {success, data: {...}}.
 * Tool-specific transforms operate on the inner `data` payload.
 * Returns the inner data object (mutated in place) or the root if no wrapper.
 */
function unwrapData(root: unknown): unknown {
  if (root && typeof root === "object" && "data" in (root as Record<string, unknown>)) {
    return (root as Record<string, unknown>).data;
  }
  return root;
}

/* ═══════════════════════════════════════════════════════════════════ */
/*  Public entry point                                                 */
/* ═══════════════════════════════════════════════════════════════════ */

export function transformN8nResponse(toolName: string, data: unknown): unknown {
  try {
    let result = applyGlobalTransforms(data);
    const inner = unwrapData(result);

    if (WORKFLOW_DETAIL_TOOLS.has(toolName)) {
      transformWorkflowDetail(inner);
    } else if (toolName === "n8n_list_workflows") {
      transformListWorkflows(inner);
    } else if (toolName === "n8n_executions") {
      transformExecutions(inner);
    }

    return result;
  } catch {
    // Never break a response — return original on any error
    return data;
  }
}
