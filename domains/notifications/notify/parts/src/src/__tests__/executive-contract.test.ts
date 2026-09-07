import assert from "node:assert/strict";
import test from "node:test";

import { makeDiscordChannel, renderDiscordEmbed } from "../adapters/channel-discord.js";
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
  assert.deepEqual(embed.fields.map((field) => field.name), ["Recommendation", "Explore", "Details"]);
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

// --- body detail preservation -------------------------------------------
//
// The executive brief summarises; it does not replace. Producers such as
// research_scout put the digest itself in `body`, and rendering only `meaning`
// deleted it on both channels.

function fieldValue(
  fields: ReadonlyArray<{ name: string; value: string }>,
  name: string,
): string {
  const field = fields.find((f) => f.name === name);
  assert.notEqual(field, undefined, `embed is missing the ${name} field`);
  return field?.value ?? "";
}

const executive = {
  kind: "action" as const,
  meaning: "Six papers matched this week's watchlist.",
  recommendation: "Read the two flagged for the estimator work.",
  explore: { kind: "url" as const, label: "Open the digest", target: "https://brain.hwc/digest" },
};

test("legacy Discord rendering is unchanged when executive is absent", () => {
  const parsed = safeParseNotificationInput({ ...base, body: "legacy body" });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  const embed = renderDiscordEmbed(parsed.value);
  assert.equal(embed.description, "legacy body");
  assert.deepEqual(embed.fields, []);
  assert.equal(embed.url, undefined);
  assert.equal(embed.footer.text, "morning-briefing · finance · receivables");
});

test("legacy SMTP rendering is unchanged when executive is absent", () => {
  const parsed = safeParseNotificationInput({ ...base, body: "legacy body" });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  const body = renderBody(parsed.value);
  assert.match(body, /^legacy body\n/);
  assert.doesNotMatch(body, /Details:/);
  assert.doesNotMatch(body, /Recommendation:/);
});

test("Discord keeps the body as a labelled Details field beside the brief", () => {
  const parsed = safeParseNotificationInput({
    ...base,
    body: "1. Sparse attention for estimators\n2. Retrieval over job histories",
    executive,
  });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  const embed = renderDiscordEmbed(parsed.value);
  assert.equal(embed.description, executive.meaning);
  assert.deepEqual(embed.fields.map((f) => f.name), ["Recommendation", "Explore", "Details"]);
  assert.equal(embed.fields[0]?.value, executive.recommendation);
  assert.match(embed.fields[1]?.value ?? "", /https:\/\/brain\.hwc\/digest/);
  assert.equal(embed.fields[2]?.value, parsed.value.body);
});

test("SMTP keeps the body as a Details section after the brief", () => {
  const parsed = safeParseNotificationInput({
    ...base,
    body: "1. Sparse attention for estimators\n2. Retrieval over job histories",
    executive,
  });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  const body = renderBody(parsed.value);
  assert.match(body, /^Six papers matched this week's watchlist\./);
  assert.match(body, /Recommendation: Read the two flagged for the estimator work\./);
  assert.match(body, /Explore: Open the digest — https:\/\/brain\.hwc\/digest/);
  assert.match(body, /\nDetails:\n1\. Sparse attention for estimators\n2\. Retrieval over job histories/);
  // Order: the decision comes before the long form, and both before metadata.
  assert.ok(body.indexOf("Recommendation:") < body.indexOf("Details:"));
  assert.ok(body.indexOf("Details:") < body.indexOf("Priority:"));
});

test("a body that only repeats the meaning is not rendered twice", () => {
  const parsed = safeParseNotificationInput({
    ...base,
    body: `  ${executive.meaning}\n `,
    executive,
  });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  const embed = renderDiscordEmbed(parsed.value);
  assert.deepEqual(embed.fields.map((f) => f.name), ["Recommendation", "Explore"]);
  const mail = renderBody(parsed.value);
  assert.doesNotMatch(mail, /Details:/);
  assert.equal(mail.split(executive.meaning).length - 1, 1);
});

test("an empty body adds no Details section", () => {
  const parsed = safeParseNotificationInput({ ...base, body: "   ", executive });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;
  assert.deepEqual(renderDiscordEmbed(parsed.value).fields.map((f) => f.name), ["Recommendation", "Explore"]);
  assert.doesNotMatch(renderBody(parsed.value), /Details:/);
});

test("an over-long body is visibly truncated on Discord and whole on SMTP", () => {
  const long = "paper. ".repeat(2000).trim(); // 13999 chars — past every embed bound
  const parsed = safeParseNotificationInput({ ...base, body: long, executive });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;

  const embed = renderDiscordEmbed(parsed.value);
  const details = fieldValue(embed.fields, "Details"); // bounded, never dropped
  assert.ok(details.length <= 1024, `field value was ${details.length}`);
  assert.match(details, /\n… \[truncated — full 13999 characters at: https:\/\/brain\.hwc\/digest\]$/);
  assert.ok(details.startsWith("paper. "));

  // The exact explore location survives truncation in three places.
  assert.equal(embed.url, "https://brain.hwc/digest");
  assert.match(fieldValue(embed.fields, "Explore"), /https:\/\/brain\.hwc\/digest/);

  // Whole embed stays inside Discord's 6000-character total.
  const total = embed.title.length + embed.description.length + embed.footer.text.length
    + embed.fields.reduce((n, f) => n + f.name.length + f.value.length, 0);
  assert.ok(total <= 6000, `embed total was ${total}`);

  // Email is the complete copy; nothing is cut there.
  assert.ok(renderBody(parsed.value).includes(long));
});

// --- production wiring ---------------------------------------------------
//
// Everything above tests the renderer. This tests that `send` puts *that*
// renderer's output on the wire: reverting the `renderDiscordEmbed` call in
// the payload would leave the pure tests green and only fail here.

test("Discord send posts the rendered executive embed to the webhook", async (t) => {
  const parsed = safeParseNotificationInput({
    ...base,
    body: "1. Sparse attention for estimators\n2. Retrieval over job histories",
    executive,
  });
  assert.equal(parsed.ok, true);
  if (!parsed.ok) return;

  const calls: Array<{ url: string; init: RequestInit }> = [];
  const g = globalThis as { fetch: typeof globalThis.fetch };
  const realFetch = g.fetch;
  g.fetch = (async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return new Response(null, { status: 204 });
  }) as unknown as typeof globalThis.fetch;
  // Restored whether the assertions below pass, fail, or throw.
  t.after(() => {
    g.fetch = realFetch;
  });

  const channel = makeDiscordChannel({
    id: "discord-test",
    name: "test",
    webhookUrl: "https://discord.invalid/api/webhooks/0/fake",
  });
  const result = await channel.send(parsed.value);

  assert.equal(calls.length, 1);
  const call = calls[0];
  assert.equal(call?.url, "https://discord.invalid/api/webhooks/0/fake");
  assert.equal(call?.init.method, "POST");

  const payload = JSON.parse(String(call?.init.body)) as {
    embeds: Array<ReturnType<typeof renderDiscordEmbed>>;
  };
  const embed = payload.embeds[0];
  assert.notEqual(embed, undefined, "the POST carried no embed");
  // Same object the pure renderer produces, not a re-derived one.
  assert.deepEqual(embed, JSON.parse(JSON.stringify(renderDiscordEmbed(parsed.value))));
  assert.equal(embed?.description, executive.meaning);
  assert.deepEqual(embed?.fields.map((f) => f.name), ["Recommendation", "Explore", "Details"]);
  assert.equal(fieldValue(embed?.fields ?? [], "Recommendation"), executive.recommendation);
  assert.match(fieldValue(embed?.fields ?? [], "Explore"), /https:\/\/brain\.hwc\/digest/);
  assert.equal(fieldValue(embed?.fields ?? [], "Details"), parsed.value.body);

  assert.equal(result.ok, true);
  assert.equal(result.channelId, "discord-test");
  assert.equal(result.statusCode, 204);
  assert.equal(result.message, undefined);
  assert.equal(typeof result.durationMs, "number");
});
