/**
 * PaveClient unit tests — retry logic, backoff timing, error detection, auth header injection.
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

  // Restore after each test — using afterEach equivalent
  function restoreFetch() {
    globalThis.fetch = originalFetch;
  }

  describe("auth header injection", () => {
    it("should include Bearer token in Authorization header", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { id: "123" } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.create("account", { name: "Test" });

      assert.equal(calls.length, 1);
      const headers = calls[0].init.headers as Record<string, string>;
      assert.equal(headers["Authorization"], "Bearer test-grant-key-123");
      assert.equal(headers["Content-Type"], "application/json");

      restoreFetch();
    });

    it("should inject orgId, userId, and notify:false into request body", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: {} } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.create("account", { name: "Test" });

      const body = JSON.parse(calls[0].init.body as string);
      assert.equal(body.organizationId, "test-org-id");
      assert.equal(body.userId, "test-user-id");
      assert.equal(body.notify, false);
      assert.equal(body.action, "create");
      assert.equal(body.entity, "account");

      restoreFetch();
    });
  });

  describe("PAVE 200-with-errors detection", () => {
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
        { ok: true, body: { data: { id: "123", name: "Test Account" } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.read("account", "123");

      assert.equal(result.success, true);
      assert.deepEqual(result.data, { id: "123", name: "Test Account" });

      restoreFetch();
    });

    it("should handle multiple errors in response", async () => {
      const { fetchFn } = mockFetch([
        {
          ok: true,
          body: {
            errors: [
              { message: "Field required: name" },
              { message: "Invalid type: accountType" },
            ],
          },
        },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      const result = await client.create("account", {});

      assert.equal(result.success, false);
      assert.ok(result.error?.includes("Field required: name"));
      assert.ok(result.error?.includes("Invalid type: accountType"));

      restoreFetch();
    });
  });

  describe("retry logic with exponential backoff", () => {
    it("should retry on transient network errors", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: false, throw: true }, // 1st: network error
        { ok: false, throw: true }, // 2nd: network error
        { ok: true, body: { data: { id: "123" } } }, // 3rd: success
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

      // PAVE errors (200 with errors) are NOT retried
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
      assert.equal(calls.length, 4); // 1 initial + 3 retries

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

  describe("convenience methods", () => {
    it("query() should set action to 'query'", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: [] } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.query({ entity: "account" });

      const body = JSON.parse(calls[0].init.body as string);
      assert.equal(body.action, "query");
      assert.equal(body.entity, "account");

      restoreFetch();
    });

    it("update() should merge id into data", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: { id: "abc", name: "Updated" } } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.update("account", "abc", { name: "Updated" });

      const body = JSON.parse(calls[0].init.body as string);
      assert.equal(body.action, "update");
      assert.equal(body.data.id, "abc");
      assert.equal(body.data.name, "Updated");

      restoreFetch();
    });

    it("query() should pass limit and offset", async () => {
      const { fetchFn, calls } = mockFetch([
        { ok: true, body: { data: [] } },
      ]);
      globalThis.fetch = fetchFn as typeof fetch;

      const client = new PaveClient(TEST_CONFIG);
      await client.query({ entity: "job", limit: 10, offset: 20 });

      const body = JSON.parse(calls[0].init.body as string);
      assert.equal(body.limit, 10);
      assert.equal(body.offset, 20);

      restoreFetch();
    });
  });
});
