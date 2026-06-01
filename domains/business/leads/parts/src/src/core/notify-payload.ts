/**
 * Pure builder: Lead → Notification payload for hwc-notify's POST /notify.
 *
 * The shape matches hwc-notify's NotificationInputSchema (zod-validated
 * on the receiving side). Source="lead"; topic="leads" so the existing
 * routing rules send it to #hwc-leads. Priority derived from the
 * lead's timeline / source heuristics:
 *
 *   asap / emergency   → P2 (loud)
 *   1_3_months         → P3 (default)
 *   3_6_months         → P4
 *   flexible / other   → P4
 *   contact / appt     → P3
 */

import type { Lead, Priority } from "./types.js";
import { buildJobName } from "./jt-graph.js";

export interface NotificationInput {
  readonly title: string;
  readonly body: string;
  readonly priority: Priority;
  readonly topic: string;
  readonly source: string;
  readonly tags: readonly string[];
  readonly context: Readonly<Record<string, unknown>>;
}

export function priorityFor(lead: Lead): Priority {
  if (lead.payload.source !== "calculator") return 3;
  const timeline = lead.payload.calc.projectState["timeline"];
  switch (timeline) {
    case "asap":
    case "emergency":
      return 2;
    case "1_3_months":
      return 3;
    case "3_6_months":
      return 4;
    default:
      return 4;
  }
}

/** Build the Discord-ready body summarising the lead. */
function summarise(lead: Lead, jtUrlBase: string | undefined): string {
  const lines: string[] = [];
  const c = lead.payload.contact;
  lines.push(`Contact: ${c.name} <${c.email}>`);
  if (c.phone) lines.push(`Phone:   ${c.phone}`);
  if (c.notes) lines.push(`Notes:   ${c.notes}`);

  if (lead.payload.source === "calculator") {
    const calc = lead.payload.calc;
    lines.push("");
    lines.push(`Calculator: ${calc.calculator}`);
    if (calc.estimate) {
      lines.push(`Estimate:   $${calc.estimate.low.toLocaleString()} – $${calc.estimate.high.toLocaleString()}`);
    }
    const tl = calc.projectState["timeline"];
    if (typeof tl === "string") lines.push(`Timeline:   ${tl.replace(/_/g, " ")}`);
    if (calc.reportId) lines.push(`Report:     ${calc.reportId}`);
  }
  if (lead.payload.source === "appointment") {
    if (lead.payload.appointment.preferredDate) {
      lines.push(`Preferred:  ${lead.payload.appointment.preferredDate} ${lead.payload.appointment.preferredTime ?? ""}`.trim());
    }
  }

  // JT job link if we have it. jtUrlBase is the JT app URL prefix.
  if (lead.jt.jobId && jtUrlBase) {
    lines.push("");
    lines.push(`JT job: ${jtUrlBase}/${lead.jt.jobId}`);
  }
  return lines.join("\n");
}

export function buildNotificationInput(
  lead: Lead,
  jtUrlBase: string | undefined,
): NotificationInput {
  const title = lead.payload.source === "calculator"
    ? `New ${lead.payload.calc.calculator} lead: ${buildJobName(lead)}`
    : `New ${lead.payload.source} lead: ${lead.payload.contact.name}`;

  return {
    title,
    body: summarise(lead, jtUrlBase),
    priority: priorityFor(lead),
    topic: "leads",
    source: "lead",
    tags: [
      lead.payload.source,
      ...(lead.payload.source === "calculator" ? [lead.payload.calc.calculator] : []),
    ],
    context: {
      leadId: lead.id,
      jt: lead.jt,
    },
  };
}
