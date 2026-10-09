/**
 * datax_* — drives the real tool handlers against a temp SR gauntlet state
 * dir, so the file contract with fetch-srs.mjs (effectivePhase,
 * effectiveNeedsReply, syncedAt) is pinned end to end.
 */

import { describe, it, expect } from "vitest";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { dataxTools, orderPhases } from "../src/tools/datax.js";

type Json = Record<string, unknown>;

async function stateDir(cache: Json | null, ledger: Json = {}): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "datax-"));
  if (cache) await writeFile(join(dir, "sr-cache.json"), JSON.stringify(cache));
  await writeFile(join(dir, "ledger.json"), JSON.stringify(ledger));
  return dir;
}

const sr = (id: string, effectivePhase: string, extra: Json = {}): Json => ({
  id,
  title: `SR ${id}`,
  name: "Customer",
  createdAt: "2026-09-01T00:00:00.000Z",
  updatedAt: "2026-09-02T00:00:00.000Z",
  effectivePhase,
  effectiveNeedsReply: false,
  ...extra,
});

function tool(dir: string, name: string) {
  const t = dataxTools(dir).find((d) => d.name === name);
  if (!t) throw new Error(`no tool ${name}`);
  return t;
}

describe("orderPhases", () => {
  it("puts open canonical phases first, custom lanes sorted, terminal last", () => {
    expect(orderPhases(["closed", "migration", "engaged", "custom-builds", "new", "archive"])).toEqual([
      "new", "engaged", "custom-builds", "migration", "closed", "archive",
    ]);
  });
});

describe("datax_support_requests", () => {
  it("groups by the gauntlet's phase, hides terminal phases, and overlays the ledger", async () => {
    const dir = await stateDir(
      {
        syncedAt: new Date().toISOString(),
        srs: {
          a: sr("a", "new", { effectiveNeedsReply: true }),
          b: sr("b", "engaged"),
          c: sr("c", "closed"),
        },
      },
      {
        a: { hash: "h", investigatedAt: "2026-09-03", run: "run-a" },
        b: { hash: "h", attempts: 1, failed: true, run: "run-b" },
      },
    );
    const res = await tool(dir, "datax_support_requests").handler({});
    expect(res.status).toBe("ok");
    const view = res.view as { data: { columns: Array<{ id: string; cards: Json[] }> }; meta: Json };
    expect((view.data as any).stages).toBe(view.data.columns);
    expect(view.data.columns.map((c) => c.id)).toEqual(["new", "engaged"]);
    const [a] = view.data.columns[0].cards;
    expect(a).toMatchObject({ id: "a", needsReply: true, investigatedAt: "2026-09-03", run: "run-a" });
    // A failed attempt has no investigatedAt, so no badge and no run link.
    expect(view.data.columns[1].cards[0]).toMatchObject({ id: "b", investigatedAt: null, run: null });
    expect(view.meta).toMatchObject({ totalTickets: 3, shownTickets: 2, needsReplyTickets: 1 });

    const all = await tool(dir, "datax_support_requests").handler({ includeClosed: true });
    const allView = all.view as { data: { columns: Array<{ id: string }> } };
    expect(allView.data.columns.map((c) => c.id)).toEqual(["new", "engaged", "closed"]);
  });

  it("fails loudly on a cache written before the phase stamp", async () => {
    const legacy = sr("a", "new");
    delete legacy.effectivePhase;
    const dir = await stateDir({ syncedAt: null, srs: { a: legacy } });
    const res = await tool(dir, "datax_support_requests").handler({});
    expect(res.status).toBe("error");
  });
});

describe("datax_api_health", () => {
  it("is ok when the gauntlet synced recently", async () => {
    const dir = await stateDir({ syncedAt: new Date().toISOString(), srs: { a: sr("a", "new") } });
    const res = await tool(dir, "datax_api_health").handler({});
    expect((res.view as { data: { overall: string } }).data.overall).toBe("ok");
  });

  it("is degraded when the last sync is stale", async () => {
    const hourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const dir = await stateDir({ syncedAt: hourAgo, srs: {} });
    const res = await tool(dir, "datax_api_health").handler({});
    expect((res.view as { data: { overall: string } }).data.overall).toBe("degraded");
  });

  it("is down when there is no cache", async () => {
    const dir = await stateDir(null);
    const res = await tool(dir, "datax_api_health").handler({});
    expect((res.view as { data: { overall: string } }).data.overall).toBe("down");
  });
});
