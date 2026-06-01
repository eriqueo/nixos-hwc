/**
 * Customer-facing email template — pure. Ported verbatim from the
 * live n8n calculator_lead workflow's "Prep Customer Email" node
 * with two changes:
 *   - heartwoodcraft.me → iheartwoodcraft.com (Eric's correction:
 *     .me is dev / never customer-facing).
 *   - Adapted for non-calculator sources: contact + appointment get
 *     simpler "we got it, we'll be in touch" templates.
 *
 * Returns { to, subject, body } ready for the SMTP adapter.
 */

import type { Lead } from "./types.js";

export interface RenderedEmail {
  readonly to: string;
  readonly subject: string;
  readonly body: string;
}

const SIGNATURE = [
  "Talk soon,",
  "",
  "Eric O'Keefe",
  "Heartwood Craft",
  "406-551-5061",
  "eric@iheartwoodcraft.com",
  "https://iheartwoodcraft.com",
].join("\n");

function firstName(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return "there";
  const space = trimmed.indexOf(" ");
  return space === -1 ? trimmed : trimmed.slice(0, space);
}

function capitalise(s: string): string {
  return s.length === 0 ? s : s.charAt(0).toUpperCase() + s.slice(1);
}

function renderCalculatorBody(lead: Lead): string {
  if (lead.payload.source !== "calculator") throw new Error("guard");
  const c = lead.payload;
  const calc = c.calc;
  const fn = firstName(c.contact.name);
  const calcLower = calc.calculator.toLowerCase();
  const estimate = calc.estimate
    ? `$${calc.estimate.low.toLocaleString()} – $${calc.estimate.high.toLocaleString()}`
    : "(estimate not generated)";

  const ps = calc.projectState;
  const stateEntries = Object.entries(ps)
    .filter(([k]) => k !== "features")
    .map(([k, v]) => `  ${k.replace(/_/g, " ")}: ${String(v).replace(/_/g, " ")}`)
    .join("\n");
  const features = Array.isArray(ps["features"])
    ? (ps["features"] as unknown[]).filter((v): v is string => typeof v === "string")
        .join(", ").replace(/_/g, " ")
    : "";

  const reportLine = calc.reportId
    ? [
        "",
        "View your full project summary here:",
        `https://iheartwoodcraft.com/report/${calc.reportId}`,
      ].join("\n")
    : "";

  const parts: string[] = [
    `Hi ${fn},`,
    "",
    `Thanks for using the Heartwood Craft calculator. Here's a quick recap of your ${calcLower} project:`,
    "",
    `Estimated range: ${estimate}`,
    "",
    "Your selections:",
    stateEntries,
  ];
  if (features) parts.push(`  features: ${features}`);
  if (reportLine) parts.push(reportLine);
  parts.push(
    "",
    "What happens next:",
    "  1. I'll give you a call to discuss your project and answer questions.",
    "  2. We schedule a site visit (about 45 minutes at your home).",
    "  3. I send you an itemized estimate, walked through together.",
    "  4. If we're a fit, we set a start date.",
    "",
    "These ranges come from real Heartwood Craft jobs in the Gallatin Valley — not national averages. Your actual cost depends on site conditions, exact dimensions, and final material selections we'd nail down on the site visit.",
    "",
    SIGNATURE,
  );
  return parts.filter((p) => p !== "").length > 0 ? parts.join("\n") : "";
  // Note: empty lines are kept; we only drop entries that are explicitly false (none here).
}

function renderContactBody(lead: Lead): string {
  const fn = firstName(lead.payload.contact.name);
  const notes = lead.payload.contact.notes;
  return [
    `Hi ${fn},`,
    "",
    "Thanks for reaching out to Heartwood Craft. I got your message and I'll be in touch soon to talk through your project.",
    notes ? "" : null,
    notes ? `You wrote:` : null,
    notes ? `> ${notes.split("\n").join("\n> ")}` : null,
    "",
    "What happens next:",
    "  1. I'll reply within a business day to set up a quick conversation.",
    "  2. If it sounds like a fit, we schedule a site visit.",
    "  3. From there it's an itemized estimate and a start date if we move forward.",
    "",
    SIGNATURE,
  ].filter((l): l is string => l !== null).join("\n");
}

function renderAppointmentBody(lead: Lead): string {
  if (lead.payload.source !== "appointment") throw new Error("guard");
  const fn = firstName(lead.payload.contact.name);
  const date = lead.payload.appointment.preferredDate;
  const time = lead.payload.appointment.preferredTime;
  const requested = date
    ? (time ? `${date} ${time}` : date)
    : "(no preferred time given)";
  return [
    `Hi ${fn},`,
    "",
    "Thanks for requesting a site visit with Heartwood Craft. I got your request.",
    "",
    `You asked about: ${requested}`,
    "",
    "I'll confirm by reply within a business day. If that slot doesn't work I'll suggest a couple of alternatives.",
    "",
    SIGNATURE,
  ].join("\n");
}

export function renderCustomerEmail(lead: Lead): RenderedEmail {
  const to = lead.payload.contact.email;

  if (lead.payload.source === "calculator") {
    const calcLabel = capitalise(lead.payload.calc.calculator);
    return {
      to,
      subject: `Your ${calcLabel} project summary from Heartwood Craft`,
      body: renderCalculatorBody(lead),
    };
  }
  if (lead.payload.source === "appointment") {
    return {
      to,
      subject: "Your site-visit request — Heartwood Craft",
      body: renderAppointmentBody(lead),
    };
  }
  return {
    to,
    subject: "Got your message — Heartwood Craft",
    body: renderContactBody(lead),
  };
}
