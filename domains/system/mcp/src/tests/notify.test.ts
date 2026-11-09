import { afterEach, describe, expect, it, vi } from "vitest";
import { notifyTools } from "../src/tools/notify.js";

const send = () => notifyTools()[0]!.handler({ action: "send", topic: "monitoring", title: "Test", body: "Details" });
afterEach(() => vi.unstubAllGlobals());

function reply(httpStatus: number, data: unknown, invalidJson = false) {
  const fetch = vi.fn().mockResolvedValue({
    status: httpStatus,
    json: invalidJson ? vi.fn().mockRejectedValue(new SyntaxError("invalid JSON")) : vi.fn().mockResolvedValue(data),
  });
  vi.stubGlobal("fetch", fetch);
  return fetch;
}

describe("hwc_notify delivery outcome", () => {
  it.each([
    [200, 2, 2, 0, "ok", "all 2 channels"],
    [207, 2, 1, 1, "partial", "1/2 channels"],
    [502, 2, 0, 2, "error", "failed on all 2 channels"],
    [202, 0, 0, 0, "error", "reached no channels"],
  ] as const)("reports HTTP %i from actual counts", async (httpStatus, attempted, succeeded, failed, status, message) => {
    const data = { notificationId: "n1", attempted, succeeded, failed, results: [{ channelId: "mail", ok: false }] };
    const fetch = reply(httpStatus, data);
    const result = await send();
    expect(result.status).toBe(status);
    expect(result.message).toContain(message);
    expect(result.data).toEqual({ httpStatus, data });
    expect(fetch).toHaveBeenCalledTimes(1);
    expect(fetch.mock.calls[0]![1]).toMatchObject({ method: "POST" });
    expect(JSON.parse(fetch.mock.calls[0]![1].body)).toEqual({ topic: "monitoring", title: "Test", body: "Details", priority: 3, source: "mcp" });
  });

  it("preserves validation errors without claiming delivery", async () => {
    const data = { code: "VALIDATION_ERROR", issues: [{ path: ["title"], message: "too long" }] };
    const fetch = reply(400, data);
    expect(await send()).toMatchObject({ status: "error", error_type: "VALIDATION_ERROR", data: { httpStatus: 400, data } });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it.each([
    null,
    [],
    { attempted: 1, succeeded: 1 },
    { attempted: "1", succeeded: 1, failed: 0 },
    { attempted: -1, succeeded: 0, failed: -1 },
    { attempted: 1.5, succeeded: 1.5, failed: 0 },
    { attempted: 2, succeeded: 2, failed: 1 },
    { attempted: 1, succeeded: 0, failed: 1 },
  ])("rejects missing, invalid or contradictory success counts: %j", async data => {
    const fetch = reply(200, data);
    const result = await send();
    expect(result.status).toBe("error");
    expect(result.data).toEqual({ httpStatus: 200, data });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it.each([200, 502])("retains HTTP %i when JSON is unreadable and never retries", async httpStatus => {
    const fetch = reply(httpStatus, undefined, true);
    expect(await send()).toMatchObject({ status: "error", data: { httpStatus, data: null } });
    expect(fetch).toHaveBeenCalledTimes(1);
  });

  it("does not resend after a connection error with unknown delivery", async () => {
    const fetch = vi.fn().mockRejectedValue(new Error("connection reset"));
    vi.stubGlobal("fetch", fetch);
    expect((await send()).status).toBe("error");
    expect(fetch).toHaveBeenCalledTimes(1);
  });
});
