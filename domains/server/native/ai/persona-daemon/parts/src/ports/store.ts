import type { ChatRole, ConversationMeta, Turn } from "../core/types.ts";

export interface ConversationStore {
  /** Create a new conversation row; returns its uuid. */
  create(personaId: string, title?: string): Promise<string>;

  /** Append a turn (no summarization logic — pure persistence). */
  appendTurn(args: {
    conversationId: string;
    role: ChatRole;
    content: string;
    tokenCount: number | null;
  }): Promise<Turn>;

  /** Return the N most-recent turns in ascending creation order. */
  getRecent(conversationId: string, n: number): Promise<Turn[]>;

  /** Return the conversation summary, if any was set. */
  getSummary(conversationId: string): Promise<string | null>;

  /** Set the summary and mark the given turn ids as superseded. */
  setSummary(
    conversationId: string,
    summary: string,
    droppedTurnIds: string[],
  ): Promise<void>;

  /** Whether the conversation row exists. */
  exists(conversationId: string): Promise<boolean>;

  /** Return conversation metadata; null if not found. */
  getMeta(conversationId: string): Promise<ConversationMeta | null>;

  /** Newest-first list (optionally filtered by persona). */
  list(opts: { personaId?: string; limit: number }): Promise<ConversationMeta[]>;
}
