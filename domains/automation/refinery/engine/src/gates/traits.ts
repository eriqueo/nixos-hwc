// Item traits drive gate applicability — the data-driven half of the registry.
// A gate's applies() reads these traits rather than hardcoding genre lists, so
// the pipeline that fires for an item is "the subset of gates whose predicate
// matches its traits" (design note: gate registry). Traits live on the item
// payload under `traits`; they are a trust-boundary input, so we parse them.

import { Item, ItemTraitsSchema, ItemTraits } from "../contracts.js";

// The trait schema is a core contract (profiles reference it via defaultTraits),
// so it lives in contracts.ts. Re-exported here for the gates that read traits.
export { ItemTraitsSchema };
export type { ItemTraits };

/**
 * Read traits off an item payload, tolerating any payload shape. Looks for a
 * `traits` object on the payload; falls back to {} when absent or malformed so
 * applies() predicates get safe defaults rather than throwing.
 */
export function readTraits(item: Item): ItemTraits {
  const payload = item.payload;
  const candidate =
    payload && typeof payload === "object" && "traits" in payload
      ? (payload as { traits: unknown }).traits
      : {};
  const parsed = ItemTraitsSchema.safeParse(candidate);
  return parsed.success ? parsed.data : {};
}
