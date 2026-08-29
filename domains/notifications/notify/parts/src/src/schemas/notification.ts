/**
 * Notification schema — the single contract at every shell boundary.
 *
 * Per engineering-principles.md Principle 2 (Parse, Don't Validate —
 * Contracts at Boundaries): every byte crossing a trust boundary is parsed by this schema
 * before core touches it. HTTP request bodies, CLI arg payloads, MCP
 * tool inputs all go through `parseNotificationInput` (lenient — fills
 * defaults like a generated id and occurredAt) or `parseNotification`
 * (strict — for stored / re-serialized notifications where every field
 * is already canonical).
 */

import { z } from "zod";
import { randomUUID } from "node:crypto";
import type { Notification } from "../core/types.js";

/** Priority enum, exposed as Zod for schema reuse. */
export const PrioritySchema = z.union([
  z.literal(1),
  z.literal(2),
  z.literal(3),
  z.literal(4),
  z.literal(5),
]);

/** Topic slug — lowercase letters, digits, dashes. Mirrors n8n webhook path constraints. */
const TopicSchema = z
  .string()
  .min(1)
  .max(64)
  .regex(/^[a-z0-9][a-z0-9-]*$/, "topic must be a lowercase kebab-case slug");

const ExploreLabelSchema = z.string().min(1).max(80);
const ExploreTargetSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("url"), label: ExploreLabelSchema, target: z.string().url() }),
  z.object({ kind: z.literal("file"), label: ExploreLabelSchema, target: z.string().startsWith("/").max(1024) }),
  z.object({ kind: z.literal("conversation"), label: ExploreLabelSchema, target: z.string().min(1).max(1024) }),
  z.object({ kind: z.literal("command"), label: ExploreLabelSchema, target: z.string().min(1).max(1024) }),
  z.object({ kind: z.literal("record"), label: ExploreLabelSchema, target: z.string().min(1).max(1024) }),
]);

export const ExecutiveBriefSchema = z.object({
  kind: z.enum(["action", "decision", "watch", "handled", "fyi"]),
  meaning: z.string().min(1).max(1000),
  recommendation: z.string().min(1).max(500),
  explore: ExploreTargetSchema,
});

// NOTE: a "strict canonical" NotificationSchema for replay / audit-log
// reads will land in Phase 1.5 when those use-cases exist. For now the
// only schema in play is the lenient input shape below.

/**
 * Lenient inbound shape — `id` and `occurredAt` are server-fillable;
 * `tags`, `context`, `source` have safe defaults. This is what the
 * HTTP `POST /notify` shell parses incoming bodies against.
 */
export const NotificationInputSchema = z.object({
  id: z.string().min(1).max(128).optional(),
  title: z.string().min(1).max(200),
  // 4000 was a Discord-shaped bound applied to every channel, and it made
  // long-form email undeliverable: research_scout's weekly digest failed 6/6
  // sends over three weeks with a 400, silently, because a 60-paper markdown
  // body is ~5x this. Discord is not the constraint it looked like — the
  // Discord adapter already truncates body to the 4096 embed limit itself
  // (adapters/channel-discord.ts), so a long body degrades there instead of
  // failing everywhere. 64k bounds the request without capping mail.
  body: z.string().max(64000).default(""),
  executive: ExecutiveBriefSchema.optional(),
  priority: PrioritySchema.default(3),
  topic: TopicSchema,
  source: z.string().min(1).max(64).default("manual"),
  tags: z.array(z.string().min(1).max(64)).max(32).default([]),
  context: z.record(z.string(), z.unknown()).default({}),
  occurredAt: z.string().datetime({ offset: true }).optional(),
});

export type NotificationInput = z.infer<typeof NotificationInputSchema>;

/**
 * Parse inbound JSON into a canonical Notification, server-filling
 * id and occurredAt when omitted. Throws on invalid shape.
 */
export function parseNotificationInput(raw: unknown): Notification {
  const input = NotificationInputSchema.parse(raw);
  return {
    id: input.id ?? randomUUID(),
    title: input.title,
    body: input.body,
    ...(input.executive !== undefined ? { executive: input.executive } : {}),
    priority: input.priority,
    topic: input.topic,
    source: input.source,
    tags: input.tags,
    context: input.context,
    occurredAt: input.occurredAt ?? new Date().toISOString(),
  };
}

/** Result of a non-throwing parse — mirrors zod.safeParse. */
export type ParseResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly issues: readonly z.ZodIssue[] };

/** Non-throwing wrapper around parseNotificationInput. */
export function safeParseNotificationInput(raw: unknown): ParseResult<Notification> {
  const result = NotificationInputSchema.safeParse(raw);
  if (!result.success) {
    return { ok: false, issues: result.error.issues };
  }
  const input = result.data;
  return {
    ok: true,
    value: {
      id: input.id ?? randomUUID(),
      title: input.title,
      body: input.body,
      ...(input.executive !== undefined ? { executive: input.executive } : {}),
      priority: input.priority,
      topic: input.topic,
      source: input.source,
      tags: input.tags,
      context: input.context,
      occurredAt: input.occurredAt ?? new Date().toISOString(),
    },
  };
}
