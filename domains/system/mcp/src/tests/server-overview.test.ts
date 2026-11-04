/**
 * hwc_server_overview — the Server hub's one board over six status tools.
 * Every failure shape must surface as a Needs-you card; the cache and the
 * single-flight bound the load this composite puts on the shared gateway.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { OVERVIEW_SOURCES, serverOverviewTool } from "../src/tools/server-overview.js";
import type { ToolDef, ToolResult } from "../src/types.js";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import ts from "typescript";

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

describe("status read scheduling", () => {
  afterEach(() => {
    vi.doUnmock("../src/executors/shell.js");
    vi.doUnmock("../src/executors/systemd.js");
    vi.doUnmock("../src/executors/podman.js");
    vi.unstubAllGlobals();
    vi.resetModules();
  });

  const turn = () => new Promise<void>((resolve) => setImmediate(resolve));

  it("keeps read results in input order even when completion order differs", async () => {
    const { mapReads } = await import("../src/executors/concurrency.js");
    const release: Array<() => void> = [];
    const pending = mapReads([0, 1, 2], (n) => new Promise<number>((resolve) => {
      release[n] = () => resolve(n * 2);
    }));
    release[2](); release[1](); release[0]();
    expect(await pending).toEqual([0, 2, 4]);
    const read = vi.fn();
    expect(await mapReads([], read)).toEqual([]);
    expect(read).not.toHaveBeenCalled();
  });

  it("stops admitting reads on failure and drains in-flight work before rejecting", async () => {
    const { mapReads } = await import("../src/executors/concurrency.js");
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    let started = 0, active = 0, settled = false;
    const failure = new Error("read failed");
    const pending = mapReads(Array.from({ length: 20 }, (_, i) => i), async (n) => {
      started++;
      if (n === 0) { await Promise.resolve(); throw failure; }
      active++;
      await gate;
      active--;
      return n;
    });
    void pending.then(() => { settled = true; }, () => { settled = true; });
    try {
      await turn();
      expect(started).toBe(8);
      expect(active).toBe(7);
      expect(settled).toBe(false);
    } finally { release(); }
    await expect(pending).rejects.toBe(failure);
    expect(active).toBe(0);
    expect(started).toBe(8);
  });

  it("overlaps service reads with a bounded worker pool, preserving order and failures", async () => {
    vi.resetModules();
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const units = Array.from({ length: 20 }, (_, i) => `hwc-test-${i}.service`);
    let active = 0, peak = 0, started = 0;
    vi.doMock("../src/executors/shell.js", () => ({
      safeExec: async (_command: string, args: string[]) => {
        if (args[0] === "list-units") return { stdout: units.join("\n"), stderr: "", exitCode: 0 };
        active++;
        started++;
        peak = Math.max(peak, active);
        await gate;
        active--;
        if (args[1] === units[9]) throw new Error("query failed");
        return { stdout: "ActiveState=active\nSubState=running", stderr: "", exitCode: 0 };
      },
    }));
    const { listServices } = await import("../src/executors/systemd.js");
    const pending = listServices();
    try {
      await turn();
      expect(started).toBe(8);
    } finally { release(); }
    const result = await pending;
    expect(peak).toBe(8);
    expect(result.map((s) => s.name)).toEqual(units);
    expect(result[9].activeState).toBe("error");
    expect(result[10].activeState).toBe("active");
  });

  it("starts all health components before any completes and keeps component order", async () => {
    vi.resetModules();
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const services = vi.fn(async () => { await gate; throw new Error("offline"); });
    const containers = vi.fn(async () => [{ Names: ["test"], State: "running" }]);
    const disk = vi.fn(async () => ({ stdout: "Mounted on Use% Avail\n/ 10% 1G", exitCode: 0 }));
    vi.doMock("../src/executors/systemd.js", () => ({ listServices: services }));
    vi.doMock("../src/executors/podman.js", () => ({ listContainers: containers }));
    vi.doMock("../src/executors/shell.js", () => ({ safeExec: disk }));
    const { executeHealthCheck } = await import("../src/tools/monitoring.js");
    const pending = executeHealthCheck();
    try {
      await turn();
      expect(disk).toHaveBeenCalledTimes(1);
      expect(containers).toHaveBeenCalledTimes(1);
    } finally { release(); }
    const result = await pending;
    expect(result.status).toBe("partial");
    expect((result.data as { components: { name: string }[] }).components.map((c) => c.name))
      .toEqual(["services", "storage", "containers"]);
    services.mockClear(); containers.mockClear(); disk.mockClear();
    await executeHealthCheck(["storage"]);
    expect(services).not.toHaveBeenCalled();
    expect(containers).not.toHaveBeenCalled();
    expect(disk).toHaveBeenCalledTimes(1);
  });

  it("overlaps media endpoints and download clients while retaining partial endpoint results", async () => {
    vi.resetModules();
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const fetcher = vi.fn(async (url: string) => {
      if (url.endsWith("/health")) { await gate; throw new Error("health unavailable"); }
      const data = url.endsWith("/queue") ? { totalRecords: 3 }
        : url.includes(":8080/") ? [] : url.includes(":8081/") ? { queue: { slots: [] } } : { version: "1" };
      return { ok: true, status: 200, json: async () => data };
    });
    vi.stubGlobal("fetch", fetcher);
    const { mediaTools } = await import("../src/tools/media.js");
    const pending = mediaTools()[0].handler({ service: "sonarr" });
    try {
      await turn();
      await vi.waitFor(() => {
        const urls = fetcher.mock.calls.map(([url]) => url);
        expect(urls.some((url) => url.endsWith("/queue"))).toBe(true);
        expect(urls.some((url) => url.includes(":8080/"))).toBe(true);
        expect(urls.some((url) => url.includes(":8081/"))).toBe(true);
      });
    } finally { release(); }
    const result = await pending;
    expect(result.data).toMatchObject({
      arr: { services: [{ name: "sonarr", running: true, healthWarnings: [], queueCount: 3 }] },
      downloads: { qbittorrent: { totalTorrents: 0 }, sabnzbd: { items: 0 } },
    });
    expect(result.message).toBe("1/1 arr services, downloads checked");
  });

  it("overlaps storage mounts and backup reads with stable output and mount failures", async () => {
    vi.resetModules();
    let release!: () => void;
    const gate = new Promise<void>((resolve) => { release = resolve; });
    const exec = vi.fn(async (command: string, args: string[]) => {
      if (command === "df") {
        await gate;
        if (args[1] === "/mnt/hot") throw new Error("unavailable");
        return { stdout: `Filesystem Size Used Avail Use% Mounted on\ndev 10G 1G 9G 10% ${args[1]}`, exitCode: 0 };
      }
      return { stdout: "ActiveState=inactive\nExecMainStatus=0", exitCode: 0 };
    });
    vi.doMock("../src/executors/shell.js", () => ({ safeExec: exec }));
    const { storageTools } = await import("../src/tools/storage.js");
    const pending = storageTools()[0].handler({});
    try {
      await turn();
      expect(exec.mock.calls.filter(([cmd]) => cmd === "df")).toHaveLength(4);
      expect(exec.mock.calls.filter(([cmd]) => cmd !== "df")).toHaveLength(3);
    } finally { release(); }
    const result = await pending;
    const data = result.data as { disk: { mounts: { tier: string; error?: string }[] } };
    expect(data.disk.mounts.map((m) => m.tier)).toEqual(["root", "hot", "media", "backup"]);
    expect(data.disk.mounts[1].error).toBe("Mount not available");
    expect(result.message).toBe("Disk: worst 10%, Backup: inactive");
  });
});

describe("request parsing and fixed pattern allocations", () => {
  const sourceDir = join(import.meta.dirname, "../src");

  it("keeps fixed regex literals outside functions throughout the gateway", () => {
    const violations: string[] = [];
    function scan(dir: string) {
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const path = join(dir, entry.name);
        if (entry.isDirectory()) { scan(path); continue; }
        if (!entry.name.endsWith(".ts")) continue;
        const file = ts.createSourceFile(path, readFileSync(path, "utf8"), ts.ScriptTarget.Latest, true);
        function walk(node: ts.Node, inFunction = false) {
          const inside = inFunction || ts.isFunctionLike(node);
          if (inside && ts.isRegularExpressionLiteral(node)) {
            violations.push(`${path}:${file.getLineAndCharacterOfPosition(node.getStart(file)).line + 1}`);
          }
          ts.forEachChild(node, (child) => walk(child, inside));
        }
        walk(file);
      }
    }
    scan(sourceDir);
    expect(violations).toEqual([]);
  });

  it("preserves URL query decoding without constructing a full URL in the SSE handler", () => {
    const path = join(sourceDir, "index.ts");
    const file = ts.createSourceFile(path, readFileSync(path, "utf8"), ts.ScriptTarget.Latest, true);
    let production = "";
    function find(node: ts.Node) {
      if (ts.isNewExpression(node) && node.expression.getText(file) === "URLSearchParams") {
        let statement: ts.Node = node;
        while (!ts.isVariableStatement(statement)) statement = statement.parent;
        const block = statement.parent as ts.Block;
        const index = block.statements.indexOf(statement);
        production = block.statements.slice(index - 3, index + 1).map((s) => s.getText(file)).join("\n");
      }
      ts.forEachChild(node, find);
    }
    find(file);
    expect(production).toContain("new URLSearchParams");
    expect(production).not.toContain("new URL(");
    const parse = new Function("url", `${production}\nreturn params;`) as (url: string) => URLSearchParams;
    for (const target of [
      "/messages", "/messages?", "/messages?sessionId=", "/messages?sessionId=one&sessionId=two",
      "/messages?sessionId=a+b", "/messages?sessionId=a%2Bb%26c", "/messages?other=a?b&sessionId=%E2%9C%93",
      "/messages?sessionId=one#ignored", "/messages#ignored?sessionId=none", "/messages?sessionId=%zz",
      "http://localhost/messages?sessionId=absolute",
    ]) {
      expect([...parse(target)]).toEqual([...new URL(target, "http://localhost").searchParams]);
    }
  });
});
