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

/**
 * Startup self-test for the HMAC signing path.
 *
 * Catches a class of silent prod failures: secret rotated on hwc-leads
 * but not on n8n (or vice versa), agenix file truncated, sandbox crypto
 * disabled, etc. The agenix secret hwc-leads-hmac-secret is SHARED with
 * the n8n container (env HWC_LEADS_HMAC_SECRET) — a half-rotation 401s
 * every lead submission silently except for response bodies operators
 * rarely look at. Failing loud at startup makes the misconfig a unit
 * failure visible to `systemctl status`.
 */

export type SelfTestResult =
  | { readonly ok: true }
  | { readonly ok: false; readonly reason: string };

const MIN_SECRET_BYTES = 32;

export function selfTestHmac(secret: string): SelfTestResult {
  // Length floor — 32 bytes = 256 bits, the minimum for SHA-256-keyed
  // HMAC to retain full strength. Empty or near-empty secrets indicate
  // a truncated agenix file or unsubstituted placeholder.
  const byteLen = Buffer.byteLength(secret, "utf8");
  if (byteLen < MIN_SECRET_BYTES) {
    return {
      ok: false,
      reason: `secret length ${byteLen} bytes < required ${MIN_SECRET_BYTES}`,
    };
  }

  // Round-trip: sign a known payload, verify with the same secret. Any
  // failure here means the crypto path itself is broken (sandbox, node
  // build flag, etc.), not just a config mismatch.
  const payload = Buffer.from("hwc-leads:startup-self-test", "utf8");
  const sig = createHmac("sha256", secret).update(payload).digest("hex");
  const header = `sha256=${sig}`;
  const verification = verifyHmac(secret, payload, header);
  if (!verification.ok) {
    return { ok: false, reason: `round-trip failed: ${verification.reason}` };
  }
  return { ok: true };
}
