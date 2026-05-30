// Commit 2: summarization is a stub. When a conversation exceeds maxRecentTurns,
// we log a warning and truncate. Commit 3 (or later) wires this to invoke the
// persona's own backend with a "summarize-for-self" prompt + persists via
// ConversationStore.setSummary.

import type { Turn } from "./types.ts";

export interface SummarizeArgs {
  oldestTurns: Turn[];
  newSummary?: string;
}

export interface SummarizeResult {
  summary: string;
  droppedTurnIds: string[];
}

/** Placeholder: returns a truncation marker, not a real summary. */
export function placeholderSummary(args: SummarizeArgs): SummarizeResult {
  const { oldestTurns } = args;
  return {
    summary:
      `[truncation marker — ${oldestTurns.length} earlier turns omitted. ` +
      `Real summarization arrives in a later commit.]`,
    droppedTurnIds: oldestTurns.map((t) => t.id),
  };
}
