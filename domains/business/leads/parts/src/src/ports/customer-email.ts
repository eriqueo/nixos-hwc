/**
 * CustomerEmailClient port — outbound interface for sending the
 * "thanks for your inquiry" templated email to the lead's address.
 */

import type { RenderedEmail } from "../core/customer-email.js";

export interface CustomerEmailResult {
  readonly ok: boolean;
  readonly messageId?: string;
  readonly message?: string;
  readonly durationMs: number;
}

export interface CustomerEmailClient {
  send(email: RenderedEmail): Promise<CustomerEmailResult>;
}
