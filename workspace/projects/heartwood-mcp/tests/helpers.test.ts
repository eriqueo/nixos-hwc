/**
 * Helpers unit tests — filter builders, pickDefined, requireString, pagination.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  buildFilter,
  buildSearchFilter,
  pickDefined,
  requireString,
  getPagination,
  ALLOWED_ENTITY_TYPES,
} from "../src/tools/jt/helpers.js";

describe("buildFilter", () => {
  it("should return undefined when no params match", () => {
    const result = buildFilter({}, [
      { param: "jobId", field: "jobId" },
    ]);
    assert.equal(result, undefined);
  });

  it("should build filter for present params only", () => {
    const result = buildFilter(
      { jobId: "j1", type: "open" },
      [
        { param: "jobId", field: "jobId" },
        { param: "type", field: "type" },
        { param: "missing", field: "missing" },
      ]
    );
    assert.deepEqual(result, {
      operator: "and",
      conditions: [
        { field: "jobId", operator: "eq", value: "j1" },
        { field: "type", operator: "eq", value: "open" },
      ],
    });
  });

  it("should preserve empty string values (not drop them)", () => {
    const result = buildFilter(
      { name: "" },
      [{ param: "name", field: "name" }]
    );
    assert.ok(result !== undefined);
    assert.equal(result!.conditions![0].value, "");
  });

  it("should preserve zero values", () => {
    const result = buildFilter(
      { amount: 0 },
      [{ param: "amount", field: "amount" }]
    );
    assert.ok(result !== undefined);
    assert.equal(result!.conditions![0].value, 0);
  });

  it("should use custom operator when specified", () => {
    const result = buildFilter(
      { startDate: "2026-01-01" },
      [{ param: "startDate", field: "date", operator: "gte" }]
    );
    assert.equal(result!.conditions![0].operator, "gte");
  });
});

describe("buildSearchFilter", () => {
  it("should wrap search term with %", () => {
    const result = buildSearchFilter({ searchTerm: "test" }, "searchTerm", "name");
    assert.equal(result!.conditions![0].value, "%test%");
    assert.equal(result!.conditions![0].operator, "like");
  });

  it("should include extra mappings", () => {
    const result = buildSearchFilter(
      { searchTerm: "test", type: "customer" },
      "searchTerm",
      "name",
      [{ param: "type", field: "type" }]
    );
    assert.equal(result!.conditions!.length, 2);
  });
});

describe("pickDefined", () => {
  it("should only pick defined fields", () => {
    const result = pickDefined(
      { a: "hello", b: undefined, c: 0, d: "" },
      ["a", "b", "c", "d", "e"]
    );
    assert.deepEqual(result, { a: "hello", c: 0, d: "" });
  });

  it("should return empty object when nothing matches", () => {
    const result = pickDefined({}, ["a", "b"]);
    assert.deepEqual(result, {});
  });
});

describe("requireString", () => {
  it("should return value for valid string", () => {
    const result = requireString({ id: "abc123" }, "id");
    assert.ok("value" in result);
    assert.equal(result.value, "abc123");
  });

  it("should return error for missing param", () => {
    const result = requireString({}, "id");
    assert.ok("error" in result);
    assert.equal(result.error.success, false);
    assert.equal(result.error.code, "VALIDATION_ERROR");
  });

  it("should return error for empty string", () => {
    const result = requireString({ id: "" }, "id");
    assert.ok("error" in result);
  });

  it("should return error for number", () => {
    const result = requireString({ id: 123 }, "id");
    assert.ok("error" in result);
  });
});

describe("getPagination", () => {
  it("should extract limit and offset", () => {
    const result = getPagination({ limit: 10, offset: 20 });
    assert.deepEqual(result, { limit: 10, offset: 20 });
  });

  it("should ignore non-number values", () => {
    const result = getPagination({ limit: "ten", offset: null });
    assert.deepEqual(result, {});
  });

  it("should return empty when no pagination params", () => {
    const result = getPagination({ jobId: "abc" });
    assert.deepEqual(result, {});
  });
});

describe("ALLOWED_ENTITY_TYPES", () => {
  it("should include core entity types", () => {
    assert.ok(ALLOWED_ENTITY_TYPES.includes("account"));
    assert.ok(ALLOWED_ENTITY_TYPES.includes("job"));
    assert.ok(ALLOWED_ENTITY_TYPES.includes("document"));
    assert.ok(ALLOWED_ENTITY_TYPES.includes("timeEntry"));
  });
});
