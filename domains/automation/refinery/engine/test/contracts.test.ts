import { test } from "node:test";
import assert from "node:assert/strict";
import { ItemSchema } from "../src/contracts.js";

test("ItemSchema accepts a well-formed item", () => {
  const result = ItemSchema.safeParse({
    id: "x",
    genre: "leads",
    stage: "intake",
    stageStatus: "pending",
    payload: { any: "shape" },
    history: [],
  });
  assert.equal(result.success, true);
});

test("ItemSchema rejects unknown stageStatus", () => {
  const result = ItemSchema.safeParse({
    id: "x",
    genre: "leads",
    stage: "intake",
    stageStatus: "wat",
    payload: {},
    history: [],
  });
  assert.equal(result.success, false);
});
