/**
 * Pure helpers for building JobTread Pave GraphQL trees from a Lead.
 *
 * The Pave dialect is JSON-encoded GraphQL: every object's `$` key
 * holds field arguments, every other key is a selected field. The
 * top-level `$` carries auth (`grantKey`) and side-effect flags
 * (`notify`). See live work_calculator_lead n8n workflow for the
 * proven shapes; these mirror them.
 *
 * Each function takes only the data it needs — kept testable
 * without an actual JT account.
 */

import type { Lead } from "./types.js";

export interface JtMappings {
  readonly organizationId: string;
  readonly defaultLocation: { readonly name: string; readonly address: string };
  readonly contactCustomFields: { readonly phone: string; readonly email: string };
  readonly accountType: string;
}

const PAVE_GRANT = Symbol("$");

/** Normalise a phone string to E.164 (US default). Returns null on garbage. */
export function toE164(raw: string | undefined): string | null {
  if (!raw) return null;
  const digits = raw.replace(/\D/g, "");
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  return digits.length > 0 ? `+${digits}` : null;
}

/** Get the customer-facing name from a Lead. */
function contactName(lead: Lead): string {
  return lead.payload.contact.name;
}

/** Get the contact email + e164 phone. */
function contactChannels(lead: Lead): { email: string; phoneE164: string | null } {
  return {
    email: lead.payload.contact.email,
    phoneE164: toE164(lead.payload.contact.phone),
  };
}

/** JT's hard limit on job.name. Names longer than this are 400'd by Pave. */
const JT_NAME_MAX = 30;

function truncate(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max);
}

/**
 * Build a label for the new JT job — capped at the JT name limit.
 * Strategy: keep the contact name verbatim; truncate the trailing
 * "'s <calc> Project" / "— ..." suffix as the budget shrinks. If the
 * name alone busts the budget, just hard-cut it.
 */
export function buildJobName(lead: Lead): string {
  const name = contactName(lead);
  if (lead.payload.source === "calculator") {
    const calc = lead.payload.calc.calculator;
    const calcLabel = calc.charAt(0).toUpperCase() + calc.slice(1);
    return truncate(`${name}'s ${calcLabel} Project`, JT_NAME_MAX);
  }
  if (lead.payload.source === "appointment") {
    return truncate(`${name} — appt`, JT_NAME_MAX);
  }
  return truncate(`${name} — contact`, JT_NAME_MAX);
}

/** Long-form description shown on the job + as the source comment body. */
export function buildJobDescription(lead: Lead): string {
  const p = lead.payload;
  const lines: string[] = [];
  lines.push(`Source: ${p.source}`);
  if (p.contact.notes) lines.push(`Notes: ${p.contact.notes}`);

  if (p.source === "calculator") {
    const c = p.calc;
    lines.push(`Calculator: ${c.calculator}`);
    if (c.estimate) {
      lines.push(`Estimate: $${c.estimate.low.toLocaleString()} – $${c.estimate.high.toLocaleString()}`);
    }
    if (c.reportId) lines.push(`Report id: ${c.reportId}`);
    const stateEntries = Object.entries(c.projectState)
      .filter(([k]) => k !== "features")
      .map(([k, v]) => `  ${k.replace(/_/g, " ")}: ${String(v).replace(/_/g, " ")}`);
    if (stateEntries.length > 0) {
      lines.push("Selections:");
      lines.push(...stateEntries);
    }
    const features = c.projectState["features"];
    if (Array.isArray(features) && features.length > 0) {
      lines.push(`  features: ${(features as unknown[]).join(", ").replace(/_/g, " ")}`);
    }
  }

  if (p.source === "appointment") {
    if (p.appointment.preferredDate) {
      lines.push(`Preferred call: ${p.appointment.preferredDate} ${p.appointment.preferredTime ?? ""}`.trim());
    }
  }

  return lines.join("\n");
}

/** Build the comment subject line. */
export function buildCommentSubject(lead: Lead): string {
  if (lead.payload.source === "calculator") {
    const c = lead.payload.calc;
    const tag = c.reportId ? ` (${c.reportId})` : "";
    const calcLabel = c.calculator.charAt(0).toUpperCase() + c.calculator.slice(1);
    return `Calculator lead — ${calcLabel}${tag}`;
  }
  return `${lead.payload.source.charAt(0).toUpperCase() + lead.payload.source.slice(1)} lead`;
}

// ── Pave query builders ────────────────────────────────────────────────

export interface PaveQuery {
  readonly [key: string]: unknown;
}

export function buildCreateAccountQuery(grantKey: string, lead: Lead, m: JtMappings): PaveQuery {
  return {
    "$": { grantKey, notify: false },
    createAccount: {
      "$": {
        organizationId: m.organizationId,
        name: contactName(lead),
        type: m.accountType,
      },
      createdAccount: { id: {}, name: {} },
    },
  };
}

export function buildCreateLocationQuery(
  grantKey: string,
  m: JtMappings,
  accountId: string,
): PaveQuery {
  return {
    "$": { grantKey, notify: false },
    createLocation: {
      "$": {
        accountId,
        name: m.defaultLocation.name,
        address: m.defaultLocation.address,
      },
      createdLocation: { id: {}, name: {} },
    },
  };
}

export function buildCreateContactQuery(
  grantKey: string,
  lead: Lead,
  m: JtMappings,
  accountId: string,
): PaveQuery {
  const { email, phoneE164 } = contactChannels(lead);
  const customFieldValues: Record<string, string> = {};
  if (phoneE164) customFieldValues[m.contactCustomFields.phone] = phoneE164;
  if (email)     customFieldValues[m.contactCustomFields.email] = email;

  const args: Record<string, unknown> = {
    accountId,
    name: contactName(lead),
  };
  if (Object.keys(customFieldValues).length > 0) {
    args["customFieldValues"] = customFieldValues;
  }

  return {
    "$": { grantKey, notify: false },
    createContact: {
      "$": args,
      createdContact: { id: {}, name: {} },
    },
  };
}

export function buildCreateJobQuery(
  grantKey: string,
  lead: Lead,
  locationId: string,
): PaveQuery {
  return {
    "$": { grantKey, notify: false },
    createJob: {
      "$": {
        locationId,
        name: buildJobName(lead),
        description: buildJobDescription(lead),
      },
      createdJob: { id: {}, number: {}, name: {} },
    },
  };
}

export function buildCreateCommentQuery(
  grantKey: string,
  lead: Lead,
  jobId: string,
): PaveQuery {
  return {
    "$": { grantKey, notify: false },
    createComment: {
      "$": {
        targetType: "job",
        targetId: jobId,
        name: buildCommentSubject(lead),
        message: buildJobDescription(lead),
        isVisibleToInternalRoles: true,
        isVisibleToCustomerRoles: false,
        isVisibleToVendorRoles: false,
        isVisibleToAll: false,
      },
      createdComment: { id: {} },
    },
  };
}

// Suppress unused-symbol warning for the Pave grant marker we keep for docs.
void PAVE_GRANT;
