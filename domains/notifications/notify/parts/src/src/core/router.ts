/**
 * Router — pure function from Notification + routes → channel IDs.
 *
 * First-rule-wins. A rule matches when every field set in `match`
 * equals the corresponding field on the notification; an empty
 * `match` matches everything. When no rule matches, `defaultChannels`
 * is the fallback (may itself be empty, producing zero deliveries).
 *
 * Phase 1.3: exact match only on (topic, source, priority). More
 * sophisticated predicates (regex, tags-any, priority-at-most) land
 * when a real case demands them — not before.
 */

import type { Notification } from "./types.js";
import type { RoutingRule } from "../schemas/runtime-config.js";

function ruleMatches(rule: RoutingRule, notif: Notification): boolean {
  // `!= null` matches both null and undefined; the Nix submodule emits
  // `null` for unset fields, while a hand-crafted JSON might omit them.
  const m = rule.match;
  if (m.topic != null && m.topic !== notif.topic) return false;
  if (m.source != null && m.source !== notif.source) return false;
  if (m.priority != null && m.priority !== notif.priority) return false;
  return true;
}

export interface RouteDecision {
  readonly channelIds: readonly string[];
  /** Which rule matched, or null when falling back to defaultChannels. */
  readonly matchedRule: string | null;
}

export function route(
  notification: Notification,
  rules: readonly RoutingRule[],
  defaultChannels: readonly string[],
): RouteDecision {
  for (const rule of rules) {
    if (ruleMatches(rule, notification)) {
      return { channelIds: rule.channels, matchedRule: rule.name };
    }
  }
  return { channelIds: defaultChannels, matchedRule: null };
}
