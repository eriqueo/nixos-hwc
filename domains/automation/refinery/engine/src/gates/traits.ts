// Item traits drive gate applicability — the data-driven half of the registry.
// A gate's applies() reads these traits rather than hardcoding genre lists, so
// the pipeline that fires for an item is "the subset of gates whose predicate
// matches its traits" (design note: gate registry). Traits live on the item
// payload under `traits`; they are a trust-boundary input, so we parse them.

import { z } from "zod";
import { Item } from "../contracts.js";

export const ItemTraitsSchema = z.object({
  // greenfield = builds something new; brownfield = modifies what exists.
  mode: z.enum(["greenfield", "brownfield"]).optional(),
  // touches code the author didn't write (Chesterton's Fence territory).
  touchesExistingCode: z.boolean().optional(),
  // a trivial item (typo, rename) skips the heavier disciplines.
  trivial: z.boolean().optional(),
  // multi-part work that stepwise-refinement should decompose.
  multiPart: z.boolean().optional(),
  // write-mode execution (commits/pushes) vs read-only.
  writeMode: z.boolean().optional(),
});
export type ItemTraits = z.infer<typeof ItemTraitsSchema>;

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
