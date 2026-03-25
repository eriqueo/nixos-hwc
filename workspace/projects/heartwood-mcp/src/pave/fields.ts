/**
 * Common PAVE field definitions for reuse across JT tools.
 * These define which fields to request from the API for each entity type.
 *
 * PAVE format: nested empty objects for field selection.
 * { id: {}, name: {}, account: { id: {}, name: {} } }
 */

import type { PaveFields } from "./types.js";

// ── Account fields ───────────────────────────────────────────────────────
// Minimal fields for create/update return values
export const ACCOUNT_BASIC_FIELDS: PaveFields = {
  id: {},
  name: {},
  type: {},
};

// Full fields for queries and reads
export const ACCOUNT_FIELDS: PaveFields = {
  id: {},
  name: {},
  type: {},
  createdAt: {},
  updatedAt: {},
  customFieldValues: {
    id: {},
    value: {},
    customField: { id: {}, name: {} },
  },
};

// ── Contact fields ───────────────────────────────────────────────────────
export const CONTACT_FIELDS: PaveFields = {
  id: {},
  name: {},
  email: {},
  phone: {},
  createdAt: {},
  account: { id: {}, name: {} },
  customFieldValues: {
    id: {},
    value: {},
    customField: { id: {}, name: {} },
  },
};

// ── Location fields ──────────────────────────────────────────────────────
export const LOCATION_FIELDS: PaveFields = {
  id: {},
  name: {},
  address: {},
  city: {},
  state: {},
  zip: {},
  account: { id: {}, name: {} },
  contact: { id: {}, name: {} },
};

// ── Job fields ───────────────────────────────────────────────────────────
export const JOB_FIELDS: PaveFields = {
  id: {},
  name: {},
  number: {},
  status: {},
  description: {},
  createdAt: {},
  updatedAt: {},
  location: { id: {}, name: {}, address: {}, city: {}, state: {}, zip: {} },
  account: { id: {}, name: {} },
  customFieldValues: {
    id: {},
    value: {},
    customField: { id: {}, name: {} },
  },
};

export const JOB_DETAIL_FIELDS: PaveFields = {
  ...JOB_FIELDS,
  files: { id: {}, name: {}, url: {}, folder: {} },
  documents: { id: {}, name: {}, type: {}, status: {} },
};

// ── Budget fields ────────────────────────────────────────────────────────
export const BUDGET_ITEM_FIELDS: PaveFields = {
  id: {},
  name: {},
  quantity: {},
  unitCost: {},
  unitPrice: {},
  totalCost: {},
  totalPrice: {},
  margin: {},
  costCode: { id: {}, name: {} },
  costType: { id: {}, name: {} },
  unit: { id: {}, name: {} },
  costGroup: { id: {}, name: {} },
};

// ── Document fields ──────────────────────────────────────────────────────
export const DOCUMENT_FIELDS: PaveFields = {
  id: {},
  name: {},
  type: {},
  status: {},
  date: {},
  total: {},
  description: {},
  createdAt: {},
  job: { id: {}, name: {}, number: {} },
  account: { id: {}, name: {} },
};

export const DOCUMENT_LINE_ITEM_FIELDS: PaveFields = {
  id: {},
  name: {},
  quantity: {},
  unitPrice: {},
  totalPrice: {},
  description: {},
  costGroup: { id: {}, name: {} },
};

// ── Payment fields ───────────────────────────────────────────────────────
export const PAYMENT_FIELDS: PaveFields = {
  id: {},
  amount: {},
  date: {},
  description: {},
  paymentType: {},
  createdAt: {},
  document: { id: {}, name: {}, type: {} },
};

// ── Task fields ──────────────────────────────────────────────────────────
export const TASK_FIELDS: PaveFields = {
  id: {},
  name: {},
  description: {},
  progress: {},
  startDate: {},
  endDate: {},
  isToDo: {},
  isGroup: {},
  assignees: { id: {}, name: {} },
};

export const TASK_DETAIL_FIELDS: PaveFields = {
  ...TASK_FIELDS,
  dependencies: { id: {}, name: {} },
};

// ── Time entry fields ────────────────────────────────────────────────────
export const TIME_ENTRY_FIELDS: PaveFields = {
  id: {},
  startedAt: {},
  endedAt: {},
  notes: {},
  type: {},
  isApproved: {},
  job: { id: {}, name: {}, number: {} },
  user: { id: {}, name: {} },
  costItem: { id: {}, name: {} },
};

// ── Daily log fields ─────────────────────────────────────────────────────
export const DAILY_LOG_FIELDS: PaveFields = {
  id: {},
  date: {},
  notes: {},
  createdAt: {},
  job: { id: {}, name: {}, number: {} },
  user: { id: {}, name: {} },
  customFieldValues: {
    id: {},
    value: {},
    customField: { id: {}, name: {} },
  },
};

// ── File fields ──────────────────────────────────────────────────────────
export const FILE_FIELDS: PaveFields = {
  id: {},
  name: {},
  url: {},
  folder: {},
  description: {},
  createdAt: {},
  fileTags: { id: {}, name: {} },
};

// ── Comment fields ───────────────────────────────────────────────────────
export const COMMENT_FIELDS: PaveFields = {
  id: {},
  message: {},
  name: {},
  isPinned: {},
  createdAt: {},
  files: { id: {}, name: {}, url: {} },
};

export const COMMENT_DETAIL_FIELDS: PaveFields = {
  ...COMMENT_FIELDS,
  children: {
    id: {},
    message: {},
    name: {},
    isPinned: {},
    createdAt: {},
    files: { id: {}, name: {}, url: {} },
  },
};

// ── Dashboard fields ─────────────────────────────────────────────────────
export const DASHBOARD_FIELDS: PaveFields = {
  id: {},
  name: {},
  tiles: {},
  createdAt: {},
  updatedAt: {},
};

// ── Custom field fields ──────────────────────────────────────────────────
export const CUSTOM_FIELD_FIELDS: PaveFields = {
  id: {},
  name: {},
  type: {},
  targetType: {},
  options: {},
};

// ── User fields ──────────────────────────────────────────────────────────
export const USER_FIELDS: PaveFields = {
  id: {},
  name: {},
  email: {},
  role: {},
};

// ── Organization fields ──────────────────────────────────────────────────
export const ORG_FIELDS: PaveFields = {
  id: {},
  name: {},
};

// ── Reference data fields ────────────────────────────────────────────────
export const COST_CODE_FIELDS: PaveFields = { id: {}, name: {} };
export const COST_TYPE_FIELDS: PaveFields = { id: {}, name: {} };
export const UNIT_FIELDS: PaveFields = { id: {}, name: {}, abbreviation: {} };
export const TEMPLATE_FIELDS: PaveFields = { id: {}, name: {} };

// ── Template detail fields (with nested items/tasks) ─────────────────────
export const COST_GROUP_TEMPLATE_DETAIL_FIELDS: PaveFields = {
  ...TEMPLATE_FIELDS,
  items: {
    ...BUDGET_ITEM_FIELDS,
  },
};

export const TASK_TEMPLATE_DETAIL_FIELDS: PaveFields = {
  ...TEMPLATE_FIELDS,
  tasks: {
    ...TASK_FIELDS,
  },
};
