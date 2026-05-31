/**
 * Runtime config schema — the contract between Nix-declared data and
 * the TS service.
 *
 * The NixOS module writes a single JSON file (`runtime-config.json`)
 * into the Nix store at build time, containing the fully resolved
 * channel list and routing table. Channel `secretRef` strings are
 * dereferenced at module-eval into `secretFile` absolute paths
 * pointing at /run/agenix/<name>; the TS service never sees the
 * secret-ref names.
 *
 * The service reads the JSON once at startup, validates it through
 * `RuntimeConfigSchema`, builds the channel instances, and uses the
 * routing table to pick channels per notification.
 */

import { z } from "zod";
import { PrioritySchema } from "./notification.js";

// ── channels ───────────────────────────────────────────────────────────

/** Adapter tag. New adapters must be added here + handled in main.ts. */
export const AdapterSchema = z.union([
  z.literal("discord"),
  z.literal("smtp"),
  z.literal("log-only"),
]);

/** Discord-specific channel params. */
const DiscordParamsSchema = z.object({
  /** Absolute path to a file containing the webhook URL (agenix-mounted). */
  secretFile: z.string().min(1),
  /** Username shown in the Discord channel. */
  username: z.string().min(1).max(80).default("HWC Notify"),
  /** Per-attempt network timeout. */
  timeoutMs: z.number().int().positive().max(60_000).default(5_000),
});

/** SMTP-specific channel params. Designed for Proton Bridge on loopback. */
const SmtpParamsSchema = z.object({
  host: z.string().min(1),
  port: z.number().int().positive().max(65535),
  /** STARTTLS upgrade after EHLO. For Proton Bridge on 127.0.0.1: false. */
  requireTls: z.boolean().default(false),
  /** SMTP AUTH username (typically the from address). */
  login: z.string().min(1),
  /** Absolute path to a file containing the SMTP password. */
  passwordFile: z.string().min(1),
  /** From header (must be a Bridge-recognized identity). */
  from: z.string().email(),
  /** Single recipient. Multi-recipient lands when a real case needs it. */
  to: z.string().email(),
  /** Per-attempt socket timeout. */
  timeoutMs: z.number().int().positive().max(60_000).default(10_000),
});

const LogOnlyParamsSchema = z.object({});

/** Discriminated by `adapter`. */
export const ChannelConfigSchema = z.discriminatedUnion("adapter", [
  z.object({
    id: z.string().min(1).max(64),
    name: z.string().min(1).max(120),
    adapter: z.literal("discord"),
    params: DiscordParamsSchema,
  }),
  z.object({
    id: z.string().min(1).max(64),
    name: z.string().min(1).max(120),
    adapter: z.literal("smtp"),
    params: SmtpParamsSchema,
  }),
  z.object({
    id: z.string().min(1).max(64),
    name: z.string().min(1).max(120),
    adapter: z.literal("log-only"),
    params: LogOnlyParamsSchema.default({}),
  }),
]);

export type ChannelConfig = z.infer<typeof ChannelConfigSchema>;

// ── routing ────────────────────────────────────────────────────────────

/**
 * Routing match predicate. Every set field is an exact match against the
 * notification field of the same name. An empty `match` is the catch-all.
 *
 * Nix submodules with `nullOr T; default = null;` serialise unset fields
 * as `null`, not `undefined`. `.nullable().optional()` accepts both so
 * the JSON round-trip works; the router treats `== null` as "unset".
 */
export const RouteMatchSchema = z.object({
  topic: z.string().min(1).nullable().optional(),
  source: z.string().min(1).nullable().optional(),
  priority: PrioritySchema.nullable().optional(),
});

export const RoutingRuleSchema = z.object({
  /** Human label for logs / introspection. Doesn't affect matching. */
  name: z.string().min(1).max(120).default("unnamed-rule"),
  match: RouteMatchSchema.default({}),
  /** Channel IDs to dispatch to. Must reference existing channels. */
  channels: z.array(z.string().min(1)).min(1),
});

export type RoutingRule = z.infer<typeof RoutingRuleSchema>;

// ── top-level ──────────────────────────────────────────────────────────

export const RuntimeConfigSchema = z.object({
  channels: z.array(ChannelConfigSchema).min(0),
  routes: z.array(RoutingRuleSchema).default([]),
  /** Channels to dispatch to when no routing rule matches. */
  defaultChannels: z.array(z.string().min(1)).default([]),
});

export type RuntimeConfig = z.infer<typeof RuntimeConfigSchema>;

/** Parse + cross-reference-validate the runtime config JSON. */
export function parseRuntimeConfig(raw: unknown): RuntimeConfig {
  const parsed = RuntimeConfigSchema.parse(raw);

  // Cross-ref check: every channel ID referenced in routes must exist.
  const knownIds = new Set(parsed.channels.map((c) => c.id));
  const orphanIds = new Set<string>();
  for (const rule of parsed.routes) {
    for (const id of rule.channels) if (!knownIds.has(id)) orphanIds.add(id);
  }
  for (const id of parsed.defaultChannels) if (!knownIds.has(id)) orphanIds.add(id);
  if (orphanIds.size > 0) {
    throw new Error(
      `runtime-config: routes/defaultChannels reference unknown channel ids: ${[...orphanIds].join(", ")}`,
    );
  }

  // Cross-ref check: no duplicate channel IDs.
  if (knownIds.size !== parsed.channels.length) {
    throw new Error("runtime-config: duplicate channel id in channels list");
  }

  return parsed;
}
