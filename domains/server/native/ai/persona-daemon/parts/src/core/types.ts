import { z } from "zod";

// ─────────────────────────────────────────────────────────────────────────
// Persona library (loaded from JSON manifest produced by Nix at build time)
// ─────────────────────────────────────────────────────────────────────────

export const PersonaMetaSchema = z.object({
  name: z.string().min(1),
  model: z.enum(["gpu", "cpu"]),
  temperature: z.number().min(0).max(2),
  topP: z.number().min(0).max(1),
  maxTokens: z.number().int().positive(),
  description: z.string(),
  systemPrompt: z.string(),
  useMemory: z.boolean(),
  useKnowledge: z.boolean(),
  knowledgeTopK: z.number().int().nonnegative(),
});
export type PersonaMeta = z.infer<typeof PersonaMetaSchema>;

export const PersonaManifestSchema = z.record(z.string(), PersonaMetaSchema);
export type PersonaManifest = z.infer<typeof PersonaManifestSchema>;

// ─────────────────────────────────────────────────────────────────────────
// Inbound request — OpenAI chat-completions shape + persona-daemon extras
// ─────────────────────────────────────────────────────────────────────────

export const ChatRoleSchema = z.enum(["system", "user", "assistant"]);
export type ChatRole = z.infer<typeof ChatRoleSchema>;

export const ChatMessageSchema = z.object({
  role: ChatRoleSchema,
  content: z.string(),
});
export type ChatMessage = z.infer<typeof ChatMessageSchema>;

export const ChatRequestSchema = z.object({
  // Persona-daemon extras
  persona: z.string().min(1),
  conversation_id: z.string().uuid().optional(),
  new_conversation: z.boolean().default(false),
  use_knowledge: z.boolean().optional(),       // Commit 3 honors this
  knowledge_top_k: z.number().int().positive().optional(),

  // Standard OpenAI fields
  messages: z.array(ChatMessageSchema).min(1),
  temperature: z.number().min(0).max(2).optional(),
  top_p: z.number().min(0).max(1).optional(),
  max_tokens: z.number().int().positive().optional(),

  // Allowlist of common OpenAI fields we accept but currently ignore
  stream: z.boolean().optional(),
  user: z.string().optional(),
}).strict();
export type ChatRequest = z.infer<typeof ChatRequestSchema>;

// ─────────────────────────────────────────────────────────────────────────
// Outbound response — OpenAI shape + persona-daemon extras
// ─────────────────────────────────────────────────────────────────────────

export const ChatChoiceSchema = z.object({
  index: z.number().int(),
  message: ChatMessageSchema,
  finish_reason: z.string().nullable(),
});

export const ChatUsageSchema = z.object({
  prompt_tokens: z.number().int(),
  completion_tokens: z.number().int(),
  total_tokens: z.number().int(),
});

export const ChatResponseSchema = z.object({
  id: z.string(),
  object: z.literal("chat.completion"),
  created: z.number().int(),
  model: z.string(),
  choices: z.array(ChatChoiceSchema),
  usage: ChatUsageSchema.optional(),
  // persona-daemon extras
  persona: z.string(),
  conversation_id: z.string().uuid().optional(),
});
export type ChatResponse = z.infer<typeof ChatResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────
// llama.cpp wire format (we re-parse on the way back from llama-server)
// ─────────────────────────────────────────────────────────────────────────

export const LlamaChatResponseSchema = z.object({
  id: z.string(),
  object: z.string(),
  created: z.number(),
  model: z.string(),
  choices: z.array(z.object({
    index: z.number(),
    message: ChatMessageSchema,
    finish_reason: z.string().nullable(),
  })).min(1),
  usage: ChatUsageSchema.optional(),
}).passthrough();
export type LlamaChatResponse = z.infer<typeof LlamaChatResponseSchema>;

export const LlamaEmbedItemSchema = z.object({
  object: z.literal("embedding"),
  index: z.number().int(),
  embedding: z.array(z.number()),
});

export const LlamaEmbedResponseSchema = z.object({
  object: z.literal("list"),
  data: z.array(LlamaEmbedItemSchema).min(1),
  model: z.string(),
  usage: ChatUsageSchema.partial().optional(),
});
export type LlamaEmbedResponse = z.infer<typeof LlamaEmbedResponseSchema>;

// ─────────────────────────────────────────────────────────────────────────
// Storage domain types (used by ConversationStore)
// ─────────────────────────────────────────────────────────────────────────

export interface Turn {
  id: string;
  conversationId: string;
  role: ChatRole;
  content: string;
  tokenCount: number | null;
  createdAt: number;     // unix ms
}

export interface ConversationMeta {
  id: string;
  personaId: string;
  title: string | null;
  createdAt: number;
  updatedAt: number;
  turnCount: number;
}

// ─────────────────────────────────────────────────────────────────────────
// Error envelope (mirrors Anthropic shape)
// ─────────────────────────────────────────────────────────────────────────

export const ErrorResponseSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    detail: z.record(z.string(), z.unknown()).optional(),
  }),
});
export type ErrorResponse = z.infer<typeof ErrorResponseSchema>;
