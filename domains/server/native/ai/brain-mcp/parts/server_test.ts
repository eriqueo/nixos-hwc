/**
 * brain-mcp/parts/server_test.ts
 *
 * Unit tests for the code-stripping helpers used by lint_wiki. These pin the
 * fence + inline-span suppression behaviour so that future edits to server.ts
 * can't silently bring back the phantom-broken-link bug (29 false positives
 * across five consecutive vault-hygiene runs).
 *
 * NOTE: server.ts guards its KEY_FILE read and Deno.serve call with
 * `import.meta.main`, so importing helpers here neither hits the filesystem
 * nor binds a socket. Run with: `deno test --allow-read`.
 */

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { stripCode, stripInlineCodeSpans } from "./server.ts";

// The same pattern lint_wiki uses to find link targets. Tests scan
// stripCode(content) the way the handler does in production.
const LINK_RE = /\[\[([^\]|#]+)/g;

function findTargets(content: string): string[] {
  return [...stripCode(content).matchAll(LINK_RE)].map((m) => m[1].trim());
}

Deno.test("stripCode: blanks wikilinks inside fenced ``` code blocks", () => {
  const md = [
    "Real link: [[real-page]]",
    "```",
    "[[fake-in-fence]]",
    "still inside",
    "```",
    "After fence: [[after-fence]]",
  ].join("\n");

  const targets = findTargets(md);
  assertEquals(targets, ["real-page", "after-fence"]);
});

Deno.test("stripCode: blanks wikilinks inside ~~~ fences too", () => {
  const md = [
    "~~~",
    "[[fake-tilde]]",
    "~~~",
    "[[ok]]",
  ].join("\n");
  assertEquals(findTargets(md), ["ok"]);
});

Deno.test("stripCode: blanks wikilinks inside inline `code` spans", () => {
  const md = "Use `[[inline-fake]]` to write a link, but [[real]] is real.";
  assertEquals(findTargets(md), ["real"]);
});

Deno.test("stripCode: handles double-backtick spans containing a tick", () => {
  const md = "Token ``a `[[fake]]` b`` then [[real]]";
  // Inside the `` `` span the [[fake]] is suppressed; [[real]] survives.
  assertEquals(findTargets(md), ["real"]);
});

Deno.test("stripCode: leaves plain broken wikilink visible", () => {
  const md = "Broken: [[no-such-page]] here.";
  assertEquals(findTargets(md), ["no-such-page"]);
});

Deno.test("stripCode: preserves line count and offsets", () => {
  const md = "a\n```\n[[x]]\n```\nb\n";
  const stripped = stripCode(md);
  assertEquals(stripped.split("\n").length, md.split("\n").length);
  assertEquals(stripped.length, md.length);
});

Deno.test("stripCode: nested fences toggle properly (open/close)", () => {
  // ``` opens, ``` closes — second pair is its own block.
  const md = [
    "```",
    "[[a]]",
    "```",
    "[[b]]",
    "```",
    "[[c]]",
    "```",
  ].join("\n");
  assertEquals(findTargets(md), ["b"]);
});

Deno.test("stripCode: does not cross fence boundaries with mismatched char", () => {
  // A ~~~ inside a ``` block must NOT close it.
  const md = [
    "```",
    "~~~",
    "[[still-in-fence]]",
    "~~~",
    "[[still-in-fence-2]]",
    "```",
    "[[real]]",
  ].join("\n");
  assertEquals(findTargets(md), ["real"]);
});

Deno.test("stripCode: aliases and headings on real link survive (lint matches base)", () => {
  // The lint regex captures the part before #/|, so these reduce to the base
  // target. Wikilink resolution itself is the handler's job; here we verify
  // stripCode doesn't accidentally eat the link.
  const md = "[[page|alias]] and [[page#heading]] and `[[inline|alias]]`";
  assertEquals(findTargets(md), ["page", "page"]);
});

Deno.test("stripInlineCodeSpans: same-length replacement", () => {
  const line = "x `code` y";
  const out = stripInlineCodeSpans(line);
  assertEquals(out.length, line.length);
  assertStringIncludes(out, "x ");
  assertStringIncludes(out, " y");
  assert(!out.includes("code"));
});
