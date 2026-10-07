/**
 * hwc_refinery action=triage — the merged Refinery board (refinery items +
 * nightly PRs) and its id-prefix routing. The workbench host sends only
 * {action, id}, so the ref:/pr: prefix is what sends a write to its owner.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
const run = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({ execFile: run, spawn: vi.fn() }));
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ToolDef, ToolResult } from "../src/types.js";

let root = "";
let items = "";
let reviews = "";
let tool: ToolDef;
const fetchMock = vi.fn();

type Card = { id: string; kind: string; verbs: string[]; url?: string; tag?: string };
type Column = { id: string; title: string; cards: Card[] };

const item = (id: string, fields: Record<string, unknown>) =>
  "# item\n\n```json\n" + JSON.stringify({ id, payload: { title: `Item ${id}` }, history: [], ...fields }) + "\n```\n";

const review = (id: string, fields: Record<string, unknown>) => ({
  id, goal: "g", cardSlug: id, title: `PR ${id}`, repo: "eriqueo/x", branch: `b-${id}`, base: "main",
  prUrl: `https://github.com/eriqueo/x/pull/${id.length}`, prNumber: id.length, reviewedAt: "2026-10-01T00:00:00Z",
  verdict: "merge-ready", mergeable: true, diffstat: { files: 1, insertions: 2, deletions: 3 },
  commits: [], whatWasDone: "w", whatItMeans: "m", recommendation: "Merge it", risks: [],
  status: "needs-you", reportRelPath: null, ...fields,
});

async function triage(): Promise<Column[]> {
  const result = await tool.handler({ action: "triage" });
  expect(result.status).toBe("ok");
  return (result.view!.data as { columns: Column[] }).columns;
}

beforeAll(async () => {
  root = await mkdtemp(join(tmpdir(), "refinery-triage-"));
  items = join(root, "items");
  reviews = join(root, "reviews");
  await mkdir(items);
  await mkdir(reviews);
  process.env.REFINERY_ITEMS_DIR = items;
  process.env.REFINERY_REVIEWS_DIR = reviews;
  process.env.REFINERY_BOARD_URL = "http://board.test";
  vi.stubGlobal("fetch", fetchMock);
  // Env is read at module load, so import after setting it.
  const { refineryTools } = await import("../src/tools/refinery.js");
  tool = refineryTools()[0];

  await writeFile(join(items, "f.md"), item("f", { pipeline: "build", step: "native", state: "failed", parkedReason: "gate broke" }));
  await writeFile(join(items, "p.md"), item("p", { pipeline: "build", state: "parked" }));
  await writeFile(join(items, "r.md"), item("r", { pipeline: "build", state: "running" }));
  await writeFile(join(items, "i.md"), item("i", { pipeline: "untriaged", stage: "captured", state: "parked" }));
  // Twelve archived items with shuffled timestamps for the Done cap.
  for (const n of [7, 2, 11, 0, 9, 4, 1, 10, 3, 8, 5, 6]) {
    await writeFile(join(items, `a${n}.md`), item(`a${n}`, {
      pipeline: "build", state: "passed", archived: true,
      archivedAt: `2026-09-${String(10 + n).padStart(2, "0")}T00:00:00Z`,
    }));
  }
  const write = (r: ReturnType<typeof review>) => writeFile(join(reviews, `${r.id}.json`), JSON.stringify(r));
  await write(review("ready", {}));
  await write(review("work", { verdict: "needs-work" }));
  await write(review("rej", { verdict: "reject" }));
  await write(review("merged", { status: "merged", reviewedAt: "2026-09-30T00:00:00Z" }));
});

afterAll(async () => {
  vi.unstubAllGlobals();
  await rm(root, { recursive: true, force: true });
});

beforeEach(() => {
  fetchMock.mockReset();
  fetchMock.mockResolvedValue({ status: 303, ok: false });
  run.mockReset();
  run.mockImplementation((_bin: string, _args: string[], _opts: unknown, cb: (e: null, out: string, err: string) => void) => cb(null, "", ""));
});

describe("hwc_refinery triage board", () => {
  it("maps refinery buckets and nightly lanes onto the four stages with prefixed ids", async () => {
    const columns = await triage();
    expect(columns.map((c) => c.id)).toEqual(["needs-you", "running", "hopper", "done"]);
    const ids = (stage: string) => columns.find((c) => c.id === stage)!.cards.map((c) => c.id);
    expect(ids("needs-you")).toEqual(["ref:f", "ref:p", "pr:ready", "pr:work", "pr:rej"]);
    expect(ids("running")).toEqual(["ref:r"]);
    expect(ids("hopper")).toEqual(["ref:i"]);
    expect(ids("done")).toContain("pr:merged");
  });

  it("caps Done at the newest ten by timestamp, with the true count in the title", async () => {
    const done = (await triage()).find((c) => c.id === "done")!;
    expect(done.title).toBe("Done (13)");
    expect(done.cards.map((c) => c.id)).toEqual([
      "pr:merged", "ref:a11", "ref:a10", "ref:a9", "ref:a8", "ref:a7", "ref:a6", "ref:a5", "ref:a4", "ref:a3",
    ]);
  });

  it("derives verbs from state: merge only on a merge-ready PR", async () => {
    const cards = (await triage()).flatMap((c) => c.cards);
    const verbs = (id: string) => cards.find((c) => c.id === id)!.verbs;
    expect(verbs("pr:ready")).toEqual(["merge"]);
    expect(verbs("pr:work")).toEqual(["requeue"]);
    expect(verbs("pr:rej")).toEqual(["requeue"]);
    expect(verbs("pr:merged")).toEqual([]);
    expect(verbs("ref:f")).toEqual(["run", "park", "delete"]);
    expect(verbs("ref:p")).toEqual(["resume", "delete"]);
    expect(verbs("ref:r")).toEqual(["park"]);
    expect(verbs("ref:i")).toEqual(["delete"]);
  });

  it("gives PR cards a url and kind, refinery cards theirs", async () => {
    const cards = (await triage()).flatMap((c) => c.cards);
    const ready = cards.find((c) => c.id === "pr:ready")!;
    expect(ready).toMatchObject({ kind: "pr", url: "https://github.com/eriqueo/x/pull/5", tag: "PR #5" });
    expect(cards.find((c) => c.id === "ref:f")).toMatchObject({ kind: "refinery", tag: "item" });
  });
});

describe("hwc_refinery prefix routing", () => {
  it.each([
    ["run", { id: "f" }, "/run"],
    ["park", { id: "f", status: "parked" }, "/status"],
    ["resume", { id: "p", status: "pending" }, "/status"],
    ["delete", { id: "f" }, "/delete"],
  ])("routes ref: %s to the board with the bare id", async (action, fields, path) => {
    const id = (fields as { id: string }).id;
    const result = await tool.handler({ action, id: `ref:${id}` });
    expect(result.status).toBe("ok");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(`http://board.test${path}`);
    expect(Object.fromEntries(new URLSearchParams(init.body))).toEqual(fields);
  });

  it("routes pr: merge to gh with the stripped review id", async () => {
    const result = await tool.handler({ action: "merge", id: "pr:ready" });
    expect(result.status).toBe("ok");
    expect(run.mock.calls[0][1]).toEqual(["pr", "merge", "5", "--squash", "-R", "eriqueo/x"]);
    expect(fetchMock).not.toHaveBeenCalled();
    await writeFile(join(reviews, "ready.json"), JSON.stringify(review("ready", {})));
  });

  it("routes pr: requeue to the nightly tool", async () => {
    const result: ToolResult = await tool.handler({ action: "requeue", id: "pr:work" });
    // The fixture has no source card in the vault, so nightly answers NOT_FOUND —
    // proof the verb reached hwc_nightly_review rather than the refinery board.
    expect(result).toMatchObject({ status: "error", error_type: "NOT_FOUND" });
    expect(result.message).toContain("Source card not found");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("routes detail on both prefixes to the owning tool", async () => {
    const pr = await tool.handler({ action: "detail", id: "pr:work" });
    expect(pr.message).toContain("Review work");
    const ref = await tool.handler({ action: "detail", id: "ref:f" });
    expect(ref.message).toMatch(/^f: failed/);
  });

  it("rejects a nightly verb on a bare or ref: id, and a refinery verb on a pr: id", async () => {
    for (const args of [{ action: "merge", id: "ready" }, { action: "requeue", id: "ref:f" }, { action: "run", id: "pr:ready" }]) {
      const result = await tool.handler(args);
      expect(result).toMatchObject({ status: "error", error_type: "VALIDATION_ERROR" });
    }
    expect(fetchMock).not.toHaveBeenCalled();
    expect(run).not.toHaveBeenCalled();
  });

  it("keeps bare ids working for the refinery's own board", async () => {
    expect((await tool.handler({ action: "run", id: "f" })).status).toBe("ok");
    expect(fetchMock.mock.calls[0][0]).toBe("http://board.test/run");
  });
});
