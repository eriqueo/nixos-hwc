// Source adapter port (intake) — the inbound boundary that turns an external
// backlog into engine Items. A genre's `source` field names which adapter
// feeds it: vault-queued-cards (nightly), firestore-srs (sr_gauntlet),
// cli-input / http-intake (project-ideation), etc.
//
// Adoption note (slice 09): the live nightly-builds card scan and
// sr_gauntlet's fetch-srs.mjs / aggregate-context.mjs become concrete
// SourcePort adapters in a later, human-gated step. This card defines the port
// and the profiles; it does NOT call the live Firestore fetch.

import { Item } from "../contracts.js";

export interface SourcePort {
  readonly id: string; // matches a profile's `source` field
  /** Fetch the next batch of items to refine (already normalized to Item). */
  fetch(): Promise<Item[]>;
}
