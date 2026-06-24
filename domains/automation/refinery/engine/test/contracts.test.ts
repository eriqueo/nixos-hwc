import { test } from "node:test";
import assert from "node:assert/strict";
import { ItemSchema } from "../src/contracts.js";

test("ItemSchema accepts a well-formed item", () => {
  const result = ItemSchema.safeParse({
    id: "x",
    pipeline: "leads",
    step: "intake",
    state: "pending",
    payload: { any: "shape" },
    history: [],
  });
  assert.equal(result.success, true);
});

test("ItemSchema rejects unknown state", () => {
  const result = ItemSchema.safeParse({
    id: "x",
    pipeline: "leads",
    step: "intake",
    state: "wat",
    payload: {},
    history: [],
  });
  assert.equal(result.success, false);
});
