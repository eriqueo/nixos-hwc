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

test("mdToHtml leaves no raw angle brackets from input (no injection)", () => {
  const html = mdToHtml("<img src=x onerror=alert(1)>");
  assert.ok(!html.includes("<img"), "raw tags escaped");
});
