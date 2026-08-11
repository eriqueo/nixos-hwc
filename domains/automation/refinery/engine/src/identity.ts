// Content-derived identity — the ONE producer of the normalize+hash fingerprint
// (case-ledger law 1: identity is content-derived, never time-derived; see
// _library/ai-ml/case_ledger_pattern.md). Extracted from sources/brain-ideas.ts
// so /intake and the brain sync share the exact same discipline instead of the
// intake path minting `slug-<Date.now()>` ids that fork the same sentence into
// two Items forever. Pure logic: no IO, no clock.

/** Normalize a list line OR a raw sentence to its comparison key: drop a
 *  leading "- ", strip html comments, trim, lowercase. Case-insensitive so
 *  trivial capitalization/whitespace drift converges to the same identity. */
export function normalizeText(s: string): string {
  return s
    .replace(/^\s*-\s+/, "")
    .replace(/<!--[\s\S]*?-->/g, "")
    .trim()
    .toLowerCase();
}

/** Stable djb2 hash → base36. Deterministic across runs (no Date.now): the
 *  same text always yields the same token. */
export function djb2(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = (((h << 5) + h) ^ s.charCodeAt(i)) >>> 0;
  return h.toString(36);
}

/** A content-derived id: `<prefix><djb2(normalizeText(text))>`. The prefix
 *  namespaces the intake path (brain- for vault ideas, in- for /intake). */
export function contentId(prefix: string, text: string): string {
  return `${prefix}${djb2(normalizeText(text))}`;
}

export const INTAKE_PREFIX = "in-";

/** The id an /intake sentence maps to. The same sentence resubmitted converges
 *  onto the same Item (an amendment event), never a duplicate. Legacy
 *  `slug-<epoch>` ids remain valid — they are just ids on disk. */
export function intakeId(text: string): string {
  return contentId(INTAKE_PREFIX, text);
}
