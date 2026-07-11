import { test } from "node:test";
import assert from "node:assert/strict";
import { mdToHtml } from "../src/shells/markdown.js";

test("mdToHtml renders headings, bold, code, lists, links and escapes HTML", () => {
  const html = mdToHtml([
    "## Verdict",
    "It **worked** with `jq` and a <script> tag.",
    "",
    "- one",
    "- two",
    "",
    "```",
    "rg -l 'x' | sort",
    "```",
    "See [docs](https://example.com).",
  ].join("\n"));
  assert.ok(html.includes("<h3>Verdict</h3>"), "## → h3 (shifted under page h2)");
  assert.ok(html.includes("<strong>worked</strong>"));
  assert.ok(html.includes("<code>jq</code>"));
  assert.ok(html.includes("&lt;script&gt;"), "HTML is escaped");
  assert.ok(html.includes("<ul>") && html.includes("<li>one</li>"));
  assert.ok(html.includes('<pre class="code"><code>'));
  assert.ok(html.includes('<a href="https://example.com">docs</a>'));
});

test("mdToHtml renders OKF vault links as obsidian deep links, http stays a link", () => {
  const html = mdToHtml(
    "See the [design](tech/development/builds/refinery/design.md) and [docs](https://x.io).",
  );
  assert.ok(
    html.includes(
      '<a class="vlink" href="obsidian://open?vault=brain&amp;file=tech%2Fdevelopment%2Fbuilds%2Frefinery%2Fdesign" title="tech/development/builds/refinery/design.md">design</a>',
    ),
    "relative .md link → obsidian://open deep link",
  );
  assert.ok(!html.includes('href="tech/'), "vault link never becomes a relative href");
  assert.ok(html.includes('<a href="https://x.io">docs</a>'), "http link unaffected");
});

test("mdToHtml drops the anchor and leading slash from an OKF deep link", () => {
  const html = mdToHtml("[the open section](/_charter/vault-constitution.md#link-standard)");
  assert.ok(
    html.includes(
      '<a class="vlink" href="obsidian://open?vault=brain&amp;file=_charter%2Fvault-constitution" title="/_charter/vault-constitution.md#link-standard">the open section</a>',
    ),
  );
});

test("mdToHtml renders legacy wikilinks as obsidian deep links", () => {
  const html = mdToHtml("See [[local-llm-landscape]] and [[refinery/design|the design]].");
  assert.ok(
    html.includes(
      '<a class="vlink" href="obsidian://open?vault=brain&amp;file=local-llm-landscape" title="local-llm-landscape">local-llm-landscape</a>',
    ),
    "bare wikilink → obsidian link labeled by target",
  );
  assert.ok(
    html.includes(
      '<a class="vlink" href="obsidian://open?vault=brain&amp;file=refinery%2Fdesign" title="refinery/design">the design</a>',
    ),
    "aliased wikilink → obsidian link labeled by alias",
  );
});

test("mdToHtml leaves no raw angle brackets from input (no injection)", () => {
  const html = mdToHtml("<img src=x onerror=alert(1)>");
  assert.ok(!html.includes("<img"), "raw tags escaped");
});
