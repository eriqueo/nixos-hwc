import { test } from "node:test";
import assert from "node:assert/strict";
import { ENHANCER_SCRIPT, boardEnhancer } from "../src/shells/enhance.js";

// The hooks ARE the shipped code: boardEnhancer is stringified into the page,
// and boardEnhancer(true) returns the same inner functions for testing.
const hooks = boardEnhancer(true)!;

test("sortKeyFromText: the board's numeric shapes parse on the leading number", () => {
  assert.equal(hooks.sortKeyFromText("88.8%"), 88.8);
  assert.equal(hooks.sortKeyFromText("≤0.27M / ≤1.75M (n=3)"), 0.27);
  assert.equal(hooks.sortKeyFromText("1.2 / 2.8"), 1.2);
  assert.equal(hooks.sortKeyFromText("27 (22/5⑂)"), 27);
  assert.equal(hooks.sortKeyFromText("4 (4)"), 4);
  assert.equal(hooks.sortKeyFromText("-3.5"), -3.5);
  assert.equal(hooks.sortKeyFromText("—"), null);
  assert.equal(hooks.sortKeyFromText(""), null);
});

test("compareKeys: empties last in BOTH directions", () => {
  const ks = [88.8, null, 0.27, null, 95.7];
  const asc = [...ks].sort((a, b) => hooks.compareKeys(a, b, 1));
  assert.deepEqual(asc, [0.27, 88.8, 95.7, null, null]);
  const desc = [...ks].sort((a, b) => hooks.compareKeys(a, b, -1));
  assert.deepEqual(desc, [95.7, 88.8, 0.27, null, null]);
});

test("sortGroups: row groups travel whole — sub-rows stay with their cohort", () => {
  // Two cohorts: A (main + diverged sub-row + expansion), B (main only).
  const groups = [
    { key: 74.3, text: "74.3%", rows: ["A-main", "A-sub"] },
    { key: 88.8, text: "88.8%", rows: ["B-main"] },
    { key: null, text: "—", rows: ["C-main", "C-sub"] },
  ];
  const desc = hooks.sortGroups(groups, -1).flatMap((g) => g.rows);
  assert.deepEqual(desc, ["B-main", "A-main", "A-sub", "C-main", "C-sub"], "desc: sub travels, empty last");
  const asc = hooks.sortGroups(groups, 1).flatMap((g) => g.rows);
  assert.deepEqual(asc, ["A-main", "A-sub", "B-main", "C-main", "C-sub"], "asc: empty still last");
});

test("sortGroups: mostly-text columns fall back to locale compare, empties last", () => {
  const groups = [
    { key: null, text: "receipt processor", rows: ["r"] },
    { key: null, text: "", rows: ["empty"] },
    { key: null, text: "grammar checker", rows: ["g"] },
  ];
  assert.deepEqual(hooks.sortGroups(groups, 1).map((g) => g.rows[0]), ["g", "r", "empty"]);
});

test("the shipped script is self-contained vanilla JS", () => {
  assert.ok(ENHANCER_SCRIPT.startsWith("<script>(") && ENHANCER_SCRIPT.endsWith(")();</script>"));
  assert.ok(!/https?:\/\//.test(ENHANCER_SCRIPT), "no external URLs/CDN");
  assert.ok(!ENHANCER_SCRIPT.slice(8, -9).includes("</script"), "no premature close tag");
  assert.ok(ENHANCER_SCRIPT.includes('data-enhance="table"') && ENHANCER_SCRIPT.includes('data-enhance="lanes"'));
});
