/**
 * HMAC-SHA256 verification for POST /leads request signing.
 *
 * The shared signing secret lives in agenix as `hwc-leads-hmac-secret`
 * (loaded once at startup into config.hmacSecret). The calculator app
 * and 11ty form bundles carry the same secret; their submit handler
 * computes HMAC-SHA256 over the raw request body and sends it in the
 * `X-HWC-Signature` header as `sha256=<hex>`.
 *
 * Service-side verification runs on the RAW body bytes — before JSON
 * parsing — so any whitespace / key-ordering difference between what
 * the client signed and what we'd re-serialise doesn't matter.
 *
 * Constant-time comparison via crypto.timingSafeEqual to avoid leaking
 * partial-match information through response timing.
 */

import { createHmac, timingSafeEqual } from "node:crypto";

const HEADER_RE = /^sha256=([0-9a-f]{64})$/i;

export type VerifyResult =
  | { readonly ok: true }
  | { readonly ok: false; readonly reason: "missing" | "malformed" | "mismatch" };

/**
 * Returns ok:true when the signature matches; ok:false with a reason
 * otherwise. Never throws.
 */
export function verifyHmac(
  secret: string,
  rawBody: Buffer,
  signatureHeader: string | undefined,
): VerifyResult {
  if (!signatureHeader || signatureHeader.length === 0) {
    return { ok: false, reason: "missing" };
  }

  const match = HEADER_RE.exec(signatureHeader);
  if (!match || !match[1]) return { ok: false, reason: "malformed" };

  const provided = Buffer.from(match[1].toLowerCase(), "hex");
  const computed = createHmac("sha256", secret).update(rawBody).digest();

  // timingSafeEqual requires identical lengths; an unequal length is
  // itself a mismatch but we check separately so the function never
  // throws on caller bugs.
  if (provided.length !== computed.length) return { ok: false, reason: "mismatch" };
  return timingSafeEqual(provided, computed)
    ? { ok: true }
    : { ok: false, reason: "mismatch" };
}
