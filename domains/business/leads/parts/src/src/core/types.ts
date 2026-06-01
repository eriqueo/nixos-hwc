/**
 * Core domain types.
 *
 * The canonical Lead entity. Built from validated LeadInput (see
 * schemas/lead.ts) by core/build.ts. Each source variant carries the
 * fields that source actually has — discriminated union, not "all
 * fields optional + please check at runtime."
 */

export type LeadSource = "contact" | "calculator" | "appointment";

/** 1=critical, 5=low. Same scheme hwc-notify uses. */
export type Priority = 1 | 2 | 3 | 4 | 5;

/** Customer contact fields — present on every Lead regardless of source. */
export interface Contact {
  readonly name: string;
  readonly email: string;
  readonly phone?: string;
  readonly notes?: string;
}

/** Calculator-specific extension. */
export interface CalculatorMeta {
  readonly calculator: string;
  /** Free-form per-calculator selections (bathroom_size, fixtures, ...). */
  readonly projectState: Readonly<Record<string, unknown>>;
  readonly estimate?: { readonly low: number; readonly high: number };
  /** Public-facing report id (used by Phase 4 report viewer). */
  readonly reportId?: string;
  /** Attribution — UTMs / GCLID / referrer / landing page. */
  readonly attribution: ReadonlyAttribution;
}

export interface ReadonlyAttribution {
  readonly utmSource?: string;
  readonly utmMedium?: string;
  readonly utmCampaign?: string;
  readonly gclid?: string;
  readonly referrer?: string;
  readonly landingPage?: string;
  readonly pagesViewed?: number;
}

/** Appointment-specific extension. */
export interface AppointmentMeta {
  readonly preferredDate?: string;
  readonly preferredTime?: string;
}

/** Per-source payload (discriminated union by `source`). */
export type LeadPayload =
  | { readonly source: "contact"; readonly contact: Contact }
  | { readonly source: "calculator"; readonly contact: Contact; readonly calc: CalculatorMeta }
  | { readonly source: "appointment"; readonly contact: Contact; readonly appointment: AppointmentMeta };

/** Status — drives the Phase 2.3+ retry queue. */
export type LeadStatus =
  | "received"
  | "validated"
  | "pending_jt"
  | "complete"
  | "failed";

/** Canonical Lead — what core operates on and what the audit log stores. */
export interface Lead {
  readonly id: string;                  // server UUID
  readonly payload: LeadPayload;
  readonly receivedAt: string;          // ISO-8601
  readonly status: LeadStatus;
  /** JT graph IDs, populated by Phase 2.4. */
  readonly jt: {
    readonly accountId?: string;
    readonly locationId?: string;
    readonly contactId?: string;
    readonly jobId?: string;
  };
}
