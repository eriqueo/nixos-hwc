import type { ChatPort, EmbedPort } from "../ports/llm.ts";
import type { ConversationStore, VectorStore } from "../ports/store.ts";
import type { LogPort } from "../ports/log.ts";
import type {
  ChatMessage,
  ChatRequest,
  ChatResponse,
  PersonaManifest,
} from "./types.ts";
import { PersonaDaemonError } from "./errors.ts";
import { buildSystemPrompt } from "./prompt-envelope.ts";
import { placeholderSummary } from "./summarization.ts";

import type { MetricsWriter } from "./metrics.ts";

export interface OrchestratorDeps {
  personas: PersonaManifest;
  chat: ChatPort;
  store: ConversationStore;
  log: LogPort;
  maxRecentTurns: number;
  keepRecentTurns: number;
  // Optional RAG deps — when present, useKnowledge personas get retrieval.
  embed?: EmbedPort;
  vectorStore?: VectorStore;
  metrics?: MetricsWriter;
}

/**
 * Single-turn orchestration. Stateless callers pass `messages` directly.
 * Memory-enabled callers pass `conversation_id` and we prepend stored
 * history. For Commit 2 RAG retrieval is a no-op; Commit 3 will inject
 * chunks via the prompt envelope.
 */
export function createOrchestrator(deps: OrchestratorDeps) {
  const {
    personas, chat, store, log,
    maxRecentTurns, keepRecentTurns,
    embed, vectorStore, metrics,
  } = deps;

  return async function orchestrate(req: ChatRequest): Promise<ChatResponse> {
    const persona = personas[req.persona];
    if (!persona) {
      throw new PersonaDaemonError(
        "PERSONA_UNKNOWN",
        `unknown persona: ${req.persona}`,
        { available: Object.keys(personas) },
      );
    }

    // Decide which conversation we're working with (if any).
    let conversationId: string | undefined = req.conversation_id;
    if (persona.useMemory && req.new_conversation) {
      conversationId = await store.create(persona.name);
      log.info("conversation.created", { conversationId, persona: persona.name });
    }
    if (conversationId && !(await store.exists(conversationId))) {
      throw new PersonaDaemonError(
        "CONVERSATION_NOT_FOUND",
        `conversation ${conversationId} does not exist`,
      );
    }

    // The last user turn is what we'll record as "user" if memory is on.
    const lastUser = [...req.messages].reverse().find((m) => m.role === "user");
    if (!lastUser) {
      throw new PersonaDaemonError(
        "INVALID_REQUEST",
        "messages must contain at least one user turn",
      );
    }

    // Build the message list we'll send upstream.
    const summary = conversationId
      ? await store.getSummary(conversationId)
      : null;
    const historyTurns = conversationId
      ? await store.getRecent(conversationId, maxRecentTurns)
      : [];

    // Summarization gate (Commit 2: stub-only). If the stored history is
    // already over the threshold, persist a placeholder summary so future
    // recall doesn't keep replaying the same lump.
    if (conversationId && historyTurns.length >= maxRecentTurns) {
      const dropCount = historyTurns.length - keepRecentTurns;
      if (dropCount > 0) {
        const oldest = historyTurns.slice(0, dropCount);
        const { summary: placeholder, droppedTurnIds } = placeholderSummary({
          oldestTurns: oldest,
          newSummary: summary ?? undefined,
        });
        await store.setSummary(conversationId, placeholder, droppedTurnIds);
        log.warn("conversation.truncated", {
          conversationId,
          droppedTurns: dropCount,
          note: "real summarization lands in a later commit",
        });
      }
    }

    // RAG retrieval — only if persona opts in AND embed/vectorStore wired.
    // Per-request use_knowledge override wins over persona default.
    const ragEnabled = (req.use_knowledge ?? persona.useKnowledge)
      && !!embed && !!vectorStore;
    const topK = req.knowledge_top_k ?? persona.knowledgeTopK;

    let retrievedChunks: ReadonlyArray<{
      notePath: string;
      sectionTitle: string;
      score: number;
      body: string;
    }> | undefined;
    let ragDegraded = false;

    if (ragEnabled && topK > 0) {
      try {
        const [queryVec] = await embed!.embed([lastUser.content]);
        metrics?.recordEmbed("ok");
        const top = await vectorStore!.topK(queryVec, topK);
        retrievedChunks = top.map((t) => ({
          notePath: t.notePath,
          sectionTitle: t.sectionTitle,
          score: t.score,
          body: t.body,
        }));
        log.debug("retrieval.complete", {
          persona: persona.name,
          topK,
          returned: retrievedChunks.length,
        });
      } catch (e) {
        ragDegraded = true;
        retrievedChunks = undefined;
        metrics?.recordEmbed("error");
        log.warn("retrieval.degraded", {
          persona: persona.name,
          err: e instanceof Error ? e.message : String(e),
        });
      }
    }

    const systemPrompt = buildSystemPrompt({
      persona,
      summary: conversationId ? await store.getSummary(conversationId) : null,
      retrievedChunks,
    });

    const systemMsg: ChatMessage = { role: "system", content: systemPrompt };
    const historyMsgs: ChatMessage[] = (conversationId
      ? await store.getRecent(conversationId, keepRecentTurns)
      : [])
      .filter((t) => t.role !== "system")
      .map((t) => ({ role: t.role, content: t.content }));

    // The caller's `messages` payload may contain just the new user turn
    // (typical hwc-llm usage) or a full transcript (typical OpenAI clients).
    // We strip any system/assistant they sent and use ours, but keep the
    // trailing user message verbatim. For new conversations with no stored
    // history we forward their user-side history as-is.
    const incomingUserAndAssistant = req.messages.filter(
      (m: ChatMessage) => m.role !== "system",
    );

    const upstreamMessages: ChatMessage[] = conversationId
      ? [systemMsg, ...historyMsgs, lastUser]
      : [systemMsg, ...incomingUserAndAssistant];

    const t0 = performance.now();
    const result = await chat.chat({
      backend: persona.model,
      messages: upstreamMessages,
      temperature: req.temperature ?? persona.temperature,
      topP: req.top_p ?? persona.topP,
      maxTokens: req.max_tokens ?? persona.maxTokens,
    });
    const elapsedMs = Math.round(performance.now() - t0);

    log.info("chat.completed", {
      persona: persona.name,
      backend: persona.model,
      conversationId,
      elapsedMs,
      promptTokens: result.promptTokens,
      completionTokens: result.completionTokens,
      ragEnabled,
      ragDegraded,
      retrievedChunks: retrievedChunks?.length ?? 0,
    });

    metrics?.recordChat({
      persona: persona.name,
      backend: persona.model,
      status: "ok",
      durationMs: elapsedMs,
      retrievalChunks: retrievedChunks?.length ?? 0,
    });

    // Persist both sides if memory is on.
    if (conversationId && persona.useMemory) {
      await store.appendTurn({
        conversationId,
        role: "user",
        content: lastUser.content,
        tokenCount: result.promptTokens,
      });
      await store.appendTurn({
        conversationId,
        role: "assistant",
        content: result.message.content,
        tokenCount: result.completionTokens,
      });
    }

    return {
      id: result.id,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: result.model,
      choices: [{
        index: 0,
        message: result.message,
        finish_reason: result.finishReason,
      }],
      usage: {
        prompt_tokens: result.promptTokens,
        completion_tokens: result.completionTokens,
        total_tokens: result.promptTokens + result.completionTokens,
      },
      persona: persona.name,
      conversation_id: conversationId,
    };
  };
}
