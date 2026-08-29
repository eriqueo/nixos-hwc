import assert from "node:assert/strict";
import test from "node:test";

import { renderDiscordEmbed } from "../adapters/channel-discord.js";
import { renderBody } from "../adapters/channel-smtp.js";
import { safeParseNotificationInput } from "../schemas/notification.js";

const base = {
  title: "Two invoices need a collection decision",
  body: "legacy body",
  priority: 2 as const,
  topic: "finance",
  source: "morning-briefing",
  tags: ["receivables"],
  context: {},
  occurredAt: "2026-08-29T12:00:00.000Z",
};

test("legacy notification payloads remain valid during migration", () => {
  const parsed = safeParseNotificationInput(base);
  assert.equal(parsed.ok, true);
  if (parsed.ok) assert.equal(parsed.value.executive, undefined);
});

test("executive payload requires a valid exploration target", () => {
  const parsed = safeParseNotificationInput({ ...base, executive: {
    kind: "action", meaning: "$9,284 is overdue; the oldest invoice is 253 days late.",
    recommendation: "Choose whether to collect, revise, or close each balance.",
    explore: { kind: "url", label: "Review invoices", target: "not-a-url" },
  }});
  assert.equal(parsed.ok, false);
});

test("Discord renders decision content first and demotes machine metadata", () => {
  const parsed = safeParseNotificationInput({ ...base, executive: {
    kind: "action", meaning: "$9,284 is overdue; the oldest invoice is 253 days late.",
    recommendation: "Choose whether to collect, revise, or close each balance.",
    explore: { kind: "url", label: "Review invoices", target: "https://app.jobtread.com" },
  }});
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  const embed = renderDiscordEmbed(parsed.value);
  assert.equal(embed.description, parsed.value.executive?.meaning);
  assert.deepEqual(embed.fields.map((field) => field.name), ["Recommendation", "Explore"]);
  assert.equal(embed.url, "https://app.jobtread.com");
  assert.equal(embed.footer.text, "morning-briefing · finance · receivables");
  assert.doesNotMatch(embed.fields.map((field) => field.name).join(" "), /Topic|Source|Tags/);
});

test("SMTP preserves the same meaning, recommendation, and exploration route", () => {
  const parsed = safeParseNotificationInput({ ...base, executive: {
    kind: "decision", meaning: "A vendor choice is blocking tomorrow's work.",
    recommendation: "Choose option A or B before 4pm.",
    explore: { kind: "conversation", label: "Open decision thread", target: "Discord #ops / 123" },
  }});
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  const body = renderBody(parsed.value);
  assert.match(body, /^A vendor choice is blocking tomorrow's work\./);
  assert.match(body, /Recommendation: Choose option A or B before 4pm\./);
  assert.match(body, /Explore: Open decision thread — Discord #ops \/ 123/);
});
