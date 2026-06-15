// Tests for the SSR Kanban render. Asserts HTML escaping (incl. single quotes)
// and that cards land in the correct lane with accurate counts.

import { test } from "node:test";
import assert from "node:assert/strict";
import type { Card } from "../src/parse.ts";
import { renderPage } from "../src/render.ts";

const card = (over: Partial<Card> = {}): Card => ({
  goalId: "goal-a",
  file: "01-x.md",
  title: "Title",
  status: "queued",
  group: "queued",
  gate: null,
  step: "",
  run: "",
  pr: "",
  ...over,
});

test("renderPage escapes all five HTML-significant chars in untrusted text", () => {
  const html = renderPage(
    [card({ title: `A & B <x> "q" 'z'` })],
    [{ section: "new", goalId: "g", text: `idea <b>&'"` }],
  );
  assert.ok(!html.includes("<x>"), "raw angle brackets must be escaped");
  assert.ok(html.includes("&amp;"));
  assert.ok(html.includes("&lt;x&gt;"));
  assert.ok(html.includes("&quot;q&quot;"));
  assert.ok(html.includes("&#39;z&#39;"), "single quotes must be escaped");
});

test("renderPage groups cards into their lanes with correct counts", () => {
  const html = renderPage(
    [
      card({ group: "queued", file: "a.md" }),
      card({ group: "queued", file: "b.md" }),
      card({ group: "done", file: "c.md" }),
    ],
    [],
  );
  // header summary reflects total card count
  assert.ok(html.includes("3 cards"));
  // a lane with two queued cards shows count 2
  assert.match(html, /Queued <span class="count">2<\/span>/);
  assert.match(html, /Done <span class="count">1<\/span>/);
  assert.match(html, /Failed <span class="count">0<\/span>/);
});

test("renderPage omits the idea lane when there are no ideas", () => {
  const html = renderPage([card()], []);
  // The .col-idea CSS rule lives in the static <style> block regardless; the
  // invariant is that the idea *section* is not rendered.
  assert.ok(!html.includes('<section class="col col-idea">'));
  assert.ok(html.includes("0 ideas"));
});

test("renderPage renders the gate badge only when a gate is present", () => {
  const withGate = renderPage([card({ gate: "human-review" })], []);
  assert.ok(withGate.includes("human-review"));
  const without = renderPage([card({ gate: null })], []);
  assert.ok(!without.includes('class="gate"'));
});
