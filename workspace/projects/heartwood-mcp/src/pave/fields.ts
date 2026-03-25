/**
 * Common PAVE field definitions for reuse across JT tools.
 * These define which fields to request from the API for each entity type.
 */

import type { PaveField } from "./types.js";

/** Shorthand: create a flat field */
function f(field: string): PaveField {
  return { field };
}

/** Shorthand: create a nested field */
function nested(field: string, ...subfields: string[]): PaveField {
  return { field, fields: subfields.map(f) };
}

// ── Account fields ───────────────────────────────────────────────────────
export const ACCOUNT_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("type"),
  f("createdAt"),
  f("updatedAt"),
  nested("customFieldValues", "id", "value", "customFieldId", "customFieldName"),
];

// ── Contact fields ───────────────────────────────────────────────────────
export const CONTACT_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("email"),
  f("phone"),
  f("createdAt"),
  nested("account", "id", "name"),
  nested("customFieldValues", "id", "value", "customFieldId", "customFieldName"),
];

// ── Location fields ──────────────────────────────────────────────────────
export const LOCATION_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("address"),
  f("city"),
  f("state"),
  f("zip"),
  nested("account", "id", "name"),
  nested("contact", "id", "name"),
];

// ── Job fields ───────────────────────────────────────────────────────────
export const JOB_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("number"),
  f("status"),
  f("description"),
  f("createdAt"),
  f("updatedAt"),
  nested("location", "id", "name", "address", "city", "state", "zip"),
  nested("account", "id", "name"),
  nested("customFieldValues", "id", "value", "customFieldId", "customFieldName"),
];

export const JOB_DETAIL_FIELDS: PaveField[] = [
  ...JOB_FIELDS,
  nested("files", "id", "name", "url", "folder"),
  nested("documents", "id", "name", "type", "status"),
];

// ── Budget fields ────────────────────────────────────────────────────────
export const BUDGET_ITEM_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("quantity"),
  f("unitCost"),
  f("unitPrice"),
  f("totalCost"),
  f("totalPrice"),
  f("margin"),
  nested("costCode", "id", "name"),
  nested("costType", "id", "name"),
  nested("unit", "id", "name"),
  nested("costGroup", "id", "name"),
];

// ── Document fields ──────────────────────────────────────────────────────
export const DOCUMENT_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("type"),
  f("status"),
  f("date"),
  f("total"),
  f("description"),
  f("createdAt"),
  nested("job", "id", "name", "number"),
  nested("account", "id", "name"),
];

export const DOCUMENT_LINE_ITEM_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("quantity"),
  f("unitPrice"),
  f("totalPrice"),
  f("description"),
  nested("costGroup", "id", "name"),
];

// ── Payment fields ───────────────────────────────────────────────────────
export const PAYMENT_FIELDS: PaveField[] = [
  f("id"),
  f("amount"),
  f("date"),
  f("description"),
  f("paymentType"),
  f("createdAt"),
  nested("document", "id", "name", "type"),
];

// ── Task fields ──────────────────────────────────────────────────────────
export const TASK_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("description"),
  f("progress"),
  f("startDate"),
  f("endDate"),
  f("isToDo"),
  f("isGroup"),
  nested("assignees", "id", "name"),
];

// ── Time entry fields ────────────────────────────────────────────────────
export const TIME_ENTRY_FIELDS: PaveField[] = [
  f("id"),
  f("startedAt"),
  f("endedAt"),
  f("notes"),
  f("type"),
  f("isApproved"),
  nested("job", "id", "name", "number"),
  nested("user", "id", "name"),
  nested("costItem", "id", "name"),
];

// ── Daily log fields ─────────────────────────────────────────────────────
export const DAILY_LOG_FIELDS: PaveField[] = [
  f("id"),
  f("date"),
  f("notes"),
  f("createdAt"),
  nested("job", "id", "name", "number"),
  nested("user", "id", "name"),
  nested("customFieldValues", "id", "value", "customFieldId", "customFieldName"),
];

// ── File fields ──────────────────────────────────────────────────────────
export const FILE_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("url"),
  f("folder"),
  f("description"),
  f("createdAt"),
  nested("fileTags", "id", "name"),
];

// ── Comment fields ───────────────────────────────────────────────────────
export const COMMENT_FIELDS: PaveField[] = [
  f("id"),
  f("message"),
  f("name"),
  f("isPinned"),
  f("createdAt"),
  nested("files", "id", "name", "url"),
];

// ── Dashboard fields ─────────────────────────────────────────────────────
export const DASHBOARD_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("tiles"),
  f("createdAt"),
  f("updatedAt"),
];

// ── Custom field fields ──────────────────────────────────────────────────
export const CUSTOM_FIELD_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("type"),
  f("targetType"),
  f("options"),
];

// ── User fields ──────────────────────────────────────────────────────────
export const USER_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
  f("email"),
  f("role"),
];

// ── Organization fields ──────────────────────────────────────────────────
export const ORG_FIELDS: PaveField[] = [
  f("id"),
  f("name"),
];

// ── Reference data fields ────────────────────────────────────────────────
export const COST_CODE_FIELDS: PaveField[] = [f("id"), f("name")];
export const COST_TYPE_FIELDS: PaveField[] = [f("id"), f("name")];
export const UNIT_FIELDS: PaveField[] = [f("id"), f("name"), f("abbreviation")];
export const TEMPLATE_FIELDS: PaveField[] = [f("id"), f("name")];
