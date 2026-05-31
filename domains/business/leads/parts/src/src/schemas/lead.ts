/**
 * Lead input schema — the single contract for POST /leads.
 *
 * Discriminated union on `source` — each variant declares the fields
 * that actually exist for that source. Contact gets just contact info;
 * calculator adds calc selections + estimate + attribution; appointment
 * adds preferred date / time.
 *
 * A separate honeypot field (`emailConfirm`) is intersected across all
 * sources — humans don't see the CSS-hidden input, bots fill it. If
 * present and non-empty, the schema rejects.
 *
 * Per engineering-principles/creating-systems.md §4 (Contracts before
 * code): every byte of an inbound /leads payload is parsed by this
 * schema before core touches it. HMAC verification happens FIRST (on
 * raw bytes), then JSON parsing, then this schema.
 */

import { z } from "zod";
import { randomUUID } from "node:crypto";
import type { Lead, LeadPayload, ReadonlyAttribution } from "../core/types.js";

/** Strip nulls — Zod's `.nullable().optional()` emits `T | null | undefined`
 *  but the canonical Lead has no nulls. */
function compactAttribution(raw: {
  utmSource?: string | null;
  utmMedium?: string | null;
  utmCampaign?: string | null;
  gclid?: string | null;
  referrer?: string | null;
  landingPage?: string | null;
  pagesViewed?: number;
}): ReadonlyAttribution {
  const out: { -readonly [K in keyof ReadonlyAttribution]?: ReadonlyAttribution[K] } = {};
  if (raw.utmSource   != null) out.utmSource   = raw.utmSource;
  if (raw.utmMedium   != null) out.utmMedium   = raw.utmMedium;
  if (raw.utmCampaign != null) out.utmCampaign = raw.utmCampaign;
  if (raw.gclid       != null) out.gclid       = raw.gclid;
  if (raw.referrer    != null) out.referrer    = raw.referrer;
  if (raw.landingPage != null) out.landingPage = raw.landingPage;
  if (raw.pagesViewed != null) out.pagesViewed = raw.pagesViewed;
  return out;
}

// ── Reusable pieces ────────────────────────────────────────────────────

const ContactSchema = z.object({
  name: z.string().min(1).max(120),
  email: z.string().email().max(200),
  phone: z.string().min(7).max(40).optional(),
  notes: z.string().max(2000).optional(),
});

const AttributionSchema = z.object({
  utmSource:   z.string().max(120).nullable().optional(),
  utmMedium:   z.string().max(120).nullable().optional(),
  utmCampaign: z.string().max(120).nullable().optional(),
  gclid:       z.string().max(200).nullable().optional(),
  referrer:    z.string().max(2000).nullable().optional(),
  landingPage: z.string().max(2000).nullable().optional(),
  pagesViewed: z.number().int().nonnegative().max(10_000).optional(),
});

const EstimateSchema = z.object({
  low:  z.number().nonnegative().max(10_000_000),
  high: z.number().nonnegative().max(10_000_000),
}).refine((e) => e.high >= e.low, {
  message: "estimate.high must be >= estimate.low",
});

// ── Per-source payloads ────────────────────────────────────────────────

const ContactPayloadSchema = z.object({
  source: z.literal("contact"),
  contact: ContactSchema,
});

const CalculatorPayloadSchema = z.object({
  source: z.literal("calculator"),
  contact: ContactSchema,
  calculator: z.string().min(1).max(40),
  projectState: z.record(z.string(), z.unknown()).default({}),
  estimate: EstimateSchema.optional(),
  reportId: z.string().min(1).max(64).optional(),
  attribution: AttributionSchema.default({}),
});

const AppointmentPayloadSchema = z.object({
  source: z.literal("appointment"),
  contact: ContactSchema,
  preferredDate: z.string().min(1).max(40).optional(),
  preferredTime: z.string().min(1).max(40).optional(),
});

// ── Honeypot (intersected across all sources) ──────────────────────────

const HoneypotSchema = z.object({
  /** Hidden input named `email_confirm` — must be empty / missing. */
  emailConfirm: z
    .string()
    .max(0, "honeypot field must be empty")
    .optional(),
});

// ── Top-level input ────────────────────────────────────────────────────

export const LeadInputSchema = z.intersection(
  z.discriminatedUnion("source", [
    ContactPayloadSchema,
    CalculatorPayloadSchema,
    AppointmentPayloadSchema,
  ]),
  HoneypotSchema,
);

export type LeadInput = z.infer<typeof LeadInputSchema>;

// ── Input → canonical Lead ─────────────────────────────────────────────

/** Build the canonical Lead from validated input. Server-fills id + timestamp. */
export function buildLead(input: LeadInput): Lead {
  const receivedAt = new Date().toISOString();

  let payload: LeadPayload;
  if (input.source === "calculator") {
    payload = {
      source: "calculator",
      contact: input.contact,
      calc: {
        calculator: input.calculator,
        projectState: input.projectState,
        ...(input.estimate ? { estimate: input.estimate } : {}),
        ...(input.reportId ? { reportId: input.reportId } : {}),
        attribution: compactAttribution(input.attribution ?? {}),
      },
    };
  } else if (input.source === "appointment") {
    payload = {
      source: "appointment",
      contact: input.contact,
      appointment: {
        ...(input.preferredDate ? { preferredDate: input.preferredDate } : {}),
        ...(input.preferredTime ? { preferredTime: input.preferredTime } : {}),
      },
    };
  } else {
    payload = { source: "contact", contact: input.contact };
  }

  return {
    id: randomUUID(),
    payload,
    receivedAt,
    status: "validated",
    jt: {},
  };
}

/** Non-throwing parse — mirrors zod.safeParse. */
export type ParseResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly issues: readonly z.ZodIssue[] };

export function safeParseLeadInput(raw: unknown): ParseResult<LeadInput> {
  const result = LeadInputSchema.safeParse(raw);
  if (!result.success) return { ok: false, issues: result.error.issues };
  return { ok: true, value: result.data };
}
