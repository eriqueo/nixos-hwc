/**
 * Build a Report from a calculator-sourced Lead.
 *
 * Returns undefined when the Lead is not eligible — either it isn't a
 * calculator submission or it lacks a reportId. Callers should treat
 * undefined as "no report row to write."
 *
 * Sanitisation: only firstName, calculator slug, projectState, and
 * estimate cross from Lead.payload into the Report. Email, phone,
 * notes, full name, and attribution all stay on the Lead row.
 */

import type { Lead } from "./types.js";
import type { Report } from "./report.js";

function firstName(fullName: string): string {
  const trimmed = fullName.trim();
  if (!trimmed) return "there";
  const space = trimmed.indexOf(" ");
  return space === -1 ? trimmed : trimmed.slice(0, space);
}

export function buildReportFromLead(lead: Lead): Report | undefined {
  if (lead.payload.source !== "calculator") return undefined;
  const calc = lead.payload.calc;
  if (!calc.reportId) return undefined;

  return {
    id: calc.reportId,
    leadId: lead.id,
    payload: {
      calculator: calc.calculator,
      firstName: firstName(lead.payload.contact.name),
      projectState: calc.projectState,
      ...(calc.estimate ? { estimate: calc.estimate } : {}),
    },
    templateId: "v1-generic",
    viewedAt: [],
    createdAt: lead.receivedAt,
  };
}
