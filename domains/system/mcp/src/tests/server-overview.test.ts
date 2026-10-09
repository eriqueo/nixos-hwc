/**
 * hwc_server_overview — the Server hub's one board over six status tools.
 * Every failure shape must surface as a Needs-you card; the cache and the
 * single-flight bound the load this composite puts on the shared gateway.
 */
import { describe, expect, it, vi } from "vitest";
import { OVERVIEW_SOURCES, serverOverviewTool } from "../src/tools/server-overview.js";
import type { ToolDef, ToolResult } from "../src/types.js";

type Card = { id: string; status: string; reason: string; facts: [string, string][] };
type Column = { id: string; title: string; cards: Card[] };

const status = (checks: { status: string; name: string; note?: string }[]): ToolResult => ({
  status: "ok", message: "ok", view: { kind: "status", data: { overall: "ok", checks } },
});

const healthy = () => status([{ status: "ok", name: "all", note: "fine" }]);

function registry(overrides: Record<string, ToolDef["handler"]> = {}): { tools: ToolDef[]; calls: Record<string, number> } {
  const calls: Record<string, number> = {};
  const tools = OVERVIEW_SOURCES.map(({ tool }) => ({
    name: tool, description: "", inputSchema: {},
    handler: async (args: Record<string, unknown>) => {
      calls[tool] = (calls[tool] ?? 0) + 1;
      return (overrides[tool] ?? healthy)(args);
    },
  }));
  return { tools, calls };
}

async function stages(tool: ToolDef, args: Record<string, unknown> = {}): Promise<Column[]> {
  const data = (await tool.handler(args)).view!.data as { stages: Column[] };
  expect(data).not.toHaveProperty("columns");
  return data.stages;
}

describe("hwc_server_overview", () => {
  it("puts non-ok checks in Needs you and healthy ones under their system", async () => {
    const { tools } = registry({
      hwc_media_status: async () => status([{ status: "down", name: "sonarr", note: ":8989" }, { status: "up", name: "jellyfin" }]),
    });
    const cols = await stages(serverOverviewTool(tools));
    expect(cols[0]).toMatchObject({ id: "needs-you", title: "Needs you" });
    expect(cols[0].cards.map((c) => c.id)).toEqual(["hwc_media_status:sonarr"]);
    expect(cols.find((c) => c.id === "hwc_media_status")!.cards.map((c) => c.id)).toEqual(["hwc_media_status:jellyfin"]);
    expect(cols.map((c) => c.title)).toEqual(["Needs you", ...OVERVIEW_SOURCES.map((s) => s.system)]);
  });

  it.each([
    ["a throw", async () => { throw new Error("boom"); }, "INTERNAL_ERROR"],
    ["an error result", async () => ({ status: "error", message: "denied", error_type: "PERMISSION_DENIED" }), "PERMISSION_DENIED"],
    ["an error result without a type", async () => ({ status: "error", message: "nope" }), "COMMAND_FAILED"],
    ["a missing view", async () => ({ status: "ok", message: "text only" }), "NO_VIEW"],
    ["a non-status view", async () => ({ status: "ok", message: "", view: { kind: "text", data: {} } }), "MALFORMED"],
    ["an unknown status word", async () => status([{ status: "purple", name: "x" }]), "MALFORMED"],
    ["checks that are not a list", async () => ({ status: "ok", message: "", view: { kind: "status", data: { checks: {} } } }), "MALFORMED"],
    ["a partial result", async () => ({ ...status([{ status: "ok", name: "half" }]), status: "partial" as const, message: "1 of 2" }), "PARTIAL"],
  ] as [string, ToolDef["handler"], string][])("turns %s into a Needs-you card naming the tool and code", async (_name, handler, code) => {
    const { tools } = registry({ hwc_storage_status: handler });
    const needs = (await stages(serverOverviewTool(tools)))[0].cards;
    expect(needs).toHaveLength(1);
    expect(needs[0]).toMatchObject({ id: "hwc_storage_status:read", status: "error" });
    expect(needs[0].facts).toContainEqual(["tool", "hwc_storage_status"]);
    expect(needs[0].facts).toContainEqual(["code", code]);
  });

  it("times a slow sub-read out without holding the board", async () => {
    const { tools } = registry({ hwc_network: () => new Promise(() => {}) });
    const needs = (await stages(serverOverviewTool(tools, { timeoutMs: 20 })))[0].cards;
    expect(needs[0].facts).toContainEqual(["code", "TIMEOUT"]);
  });

  it("names a tool missing from the registry", async () => {
    const { tools } = registry();
    const needs = (await stages(serverOverviewTool(tools.filter((t) => t.name !== "hwc_network"))))[0].cards;
    expect(needs[0].facts).toContainEqual(["code", "NOT_FOUND"]);
  });

  it("runs one fan-out for concurrent cold reads, then serves the cache", async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => { release = r; });
    const { tools, calls } = registry({ hwc_services: async () => { await gate; return healthy(); } });
    const tool = serverOverviewTool(tools);
    const both = Promise.all([tool.handler({}), tool.handler({})]);
    release();
    await both;
    expect(calls.hwc_services).toBe(1);
    const cached = await tool.handler({});
    expect(cached.view!.meta).toMatchObject({ cached: true });
    expect(calls.hwc_services).toBe(1);
  });

  it("fresh=true skips the cache, and the cache expires after 30 s", async () => {
    let now = 1_000;
    const { tools, calls } = registry();
    const tool = serverOverviewTool(tools, { now: () => now });
    await tool.handler({});
    await tool.handler({ fresh: true });
    expect(calls.hwc_services).toBe(2);
    now += 29_999;
    await tool.handler({});
    expect(calls.hwc_services).toBe(2);
    now += 2;
    await tool.handler({});
    expect(calls.hwc_services).toBe(3);
  });
});

describe("gateway registration", () => {
  it("allTools registers hwc_server_overview and it reads through the ToolRegistry", async () => {
    vi.resetModules();
    const { allTools } = await import("../src/tools/index.js");
    const { ToolRegistry } = await import("../src/tools/registry.js");
    const { loadConfig } = await import("../src/config.js");
    const reg = new ToolRegistry();
    reg.register(allTools(loadConfig()));
    const overview = reg.get("hwc_server_overview");
    expect(overview).toBeDefined();
    // Live sub-tools may fail in the sandbox; the composite must still answer
    // with a board whose stages cover every system.
    const result = await overview!.handler({});
    expect(result.status).toBe("ok");
    const cols = (result.view!.data as { stages: Column[] }).stages;
    expect(cols.map((c) => c.id)).toEqual(["needs-you", ...OVERVIEW_SOURCES.map((s) => s.tool)]);
  }, 30_000);
});
