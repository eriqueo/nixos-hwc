/**
 * PaveClient unit tests — retry logic, backoff timing, error detection, payload format.
 *
 * Uses Node.js built-in test runner (node --test).
 */

import { describe, it, mock, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { PaveClient } from "../src/pave/client.js";

// Suppress log output during tests
import { setLogLevel } from "../src/logging/logger.js";
setLogLevel("error");

const TEST_CONFIG = {
  grantKey: "test-grant-key-123",
  orgId: "test-org-id",
  userId: "test-user-id",
  apiUrl: "https://api.test.com/pave",
};

/**
 * Helper: create a mock fetch that returns a sequence of responses.
 */
function mockFetch(responses: Array<{ ok: boolean; status?: number; body?: unknown; throw?: boolean }>) {
  let callIndex = 0;
  const calls: Array<{ url: string; init: RequestInit }> = [];

  const fetchFn = async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: url.toString(), init: init ?? {} });
    const response = responses[Math.min(callIndex++, responses.length - 1)];

    if (response.throw) {
      throw new Error("fetch failed: ECONNRESET");
    }

    return {
      ok: response.ok,
      status: response.status ?? (response.ok ? 200 : 500),
      statusText: response.ok ? "OK" : "Internal Server Error",
      json: async () => response.body ?? {},
    } as Response;
  };

  return { fetchFn, calls };
}

describe("PaveClient", () => {
  let originalFetch: typeof globalThis.fetch;

  beforeEach(() => {
    originalFetch = globalThis.fetch;
  });

  function restoreFetch() {
    globalThis.fetch = originalFetch;
  }

  describe("PAVE graph payload format", () => {
    it("query() should build correct graph payload with grantKey", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { query: { organization: { accounts: { nodes: [] } } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.query({ entity: "account" });

      const body = JSON.parse(calls[0].init.body as string);
      assert.ok(body.query, "payload should have query key");
      assert.equal(body.query.$?.grantKey, "test-grant-key-123");
      assert.ok(body.query.organization, "payload should have organization");
      assert.ok(body.query.organization.accounts, "payload should pluralize entity");
      assert.equal(body.query.organization.accounts.$?.size, 25, "default size should be 25");

      restoreFetch();
    });

    it("query() should include where clause from filter", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { query: { organization: { accounts: { nodes: [] } } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.query({
        entity: "account",
        filter: {
          operator: "and",
          conditions: [
            { field: "name", operator: "like", value: "%Margulies%" },
            { field: "type", operator: "eq", value: "customer" },
          ],
        },
      });

      const body = JSON.parse(calls[0].init.body as string);
      const where = body.query.organization.accounts.$?.where;
      assert.ok(where, "should have where clause");
      assert.ok(where.and, "should use and operator");
      assert.equal(where.and[0][0][0], "name", "first condition field");
      assert.equal(where.and[0][0][1], "like", "like operator stays as-is");
      assert.equal(where.and[0][1][0], "type", "second condition field");
      assert.equal(where.and[0][1][1], "=", "eq maps to =");
      assert.equal(where.and[0][1][2], "customer");

      restoreFetch();
    });

    it("query() should pass limit as size and offset", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { query: { organization: { jobs: { nodes: [] } } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.query({ entity: "job", limit: 10, offset: 20 });

      const body = JSON.parse(calls[0].init.body as string);
      assert.equal(body.query.organization.jobs.$?.size, 10);
      assert.equal(body.query.organization.jobs.$?.offset, 20);

      restoreFetch();
    });

    it("create() should build mutation payload", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { mutation: { createAccount: { id: "123", name: "Test" } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.create("account", { name: "Test", type: "customer" });

      const body = JSON.parse(calls[0].init.body as string);
      assert.ok(body.mutation, "payload should have mutation key");
      assert.equal(body.mutation.$?.grantKey, "test-grant-key-123");
      assert.ok(body.mutation.createAccount, "should have createAccount");
      assert.equal(body.mutation.createAccount.$?.name, "Test");
      assert.equal(body.mutation.createAccount.$?.type, "customer");

      restoreFetch();
    });

    it("update() should build mutation payload with id in data", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { mutation: { updateAccount: { id: "abc", name: "Updated" } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.update("account", "abc", { name: "Updated" });

      const body = JSON.parse(calls[0].init.body as string);
      assert.ok(body.mutation.updateAccount, "should have updateAccount");
      assert.equal(body.mutation.updateAccount.$?.id, "abc");
      assert.equal(body.mutation.updateAccount.$?.name, "Updated");

      restoreFetch();
    });

    it("read() should build query payload with id param", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { query: { organization: { account: { id: "123" } } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.read("account", "123");

      const body = JSON.parse(calls[0].init.body as string);
      assert.ok(body.query.organization.account, "should use singular entity name");
      assert.equal(body.query.organization.account.$?.id, "123");

      restoreFetch();
    });

    it("fields should be converted to nodes object format", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { query: { organization: { accounts: { nodes: [] } } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.query({
        entity: "account",
        fields: [
          { field: "id" },
          { field: "name" },
          { field: "customFieldValues", fields: [{ field: "id" }, { field: "value" }] },
        ],
      });

      const body = JSON.parse(calls[0].init.body as string);
      const nodes = body.query.organization.accounts.nodes;
      assert.deepEqual(nodes.id, {}, "flat field should be {}");
      assert.deepEqual(nodes.name, {}, "flat field should be {}");
      assert.ok(nodes.customFieldValues?.nodes, "nested field should have nodes");
      assert.deepEqual(nodes.customFieldValues.nodes.id, {});

      restoreFetch();
    });
  });

  describe("PAVE errors detection", () => {
    it("should detect errors in response body and return failure", async () => {
      const { fetchFn } = mockFetch([
        {
          ok: true,
          body: {
            errors: [{ message: "Account not found", code: "NOT_FOUND" }],
          },
        },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.read("account", "nonexistent");

      assert.equal(result.success, false);
      assert.equal(result.code, "PAVE_ERROR");
      assert.ok(result.error?.includes("Account not found"));

      restoreFetch();
    });

    it("should return success when no errors present", async () => {
      const { fetchFn } = mockFetch([
        { ok: true, body: { data: { query: { organization: { account: { id: "123", name: "Test Account" } } } } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.read("account", "123");

      assert.equal(result.success, true);
      assert.deepEqual(result.data, { id: "123", name: "Test Account" });

      restoreFetch();
    });
  });

  describe("retry logic with exponential backoff", () => {
    it("should retry on transient network errors", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: false, throw: true }, // 1st: network error
        { ok: false, throw: true }, // 2nd: network error
        { ok: true, body: { data: { query: { organization: { account: { id: "123" } } } } } }, // 3rd: success
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.read("account", "123");

      assert.equal(result.success, true);
      assert.equal(calls.length, 3);

      restoreFetch();
    });

    it("should not retry on non-transient errors", async () => {
      const { fetchFn, calls } = mockFetch([
        {
          ok: true,
          body: { errors: [{ message: "Invalid field" }] },
        },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.create("account", { badField: true });

      assert.equal(result.success, false);
      assert.equal(calls.length, 1);

      restoreFetch();
    });

    it("should return NETWORK_ERROR after exhausting retries", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: false, throw: true },
        { ok: false, throw: true },
        { ok: false, throw: true },
        { ok: false, throw: true }, // All 4 attempts fail (1 initial + 3 retries)
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.read("account", "123");

      assert.equal(result.success, false);
      assert.equal(result.code, "NETWORK_ERROR");
      assert.equal(calls.length, 4);

      restoreFetch();
    });

    it("should handle HTTP error status codes", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: false, status: 500 },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.read("account", "123");

      assert.equal(result.success, false);
      assert.ok(result.error?.includes("500"));

      restoreFetch();
    });
  });
});
