import { describe, expect, it, vi } from "vitest";
const run = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({execFile: run, spawn: vi.fn()}));
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mailTriageTools, reflectLiveBuckets } from "../src/tools/mail-triage.js";

const thread = (id: string) => ({
  thread_id: id, subject: `Thread ${id}`, sender: "Sender", tags: [],
});
const empty = () => ({ act: [], look: [], bulk: [], junk: [] });

describe("authoritative mail placement", () => {
  it("one production scan supplies membership and live attention states", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-scan-"));
    try {
      const path = join(dir, "brief.json");
      await writeFile(path, JSON.stringify({mail_triage:{buckets:{...empty(),act:[thread("a")]}}}));
      run.mockReset();
      run.mockImplementation((_bin, args, _options, callback) => callback(null,
        args.includes("--format=json") ? JSON.stringify([{thread:"a", tags:["inbox","attention/look"]}]) : "thread:a\n", ""));
      const result = await mailTriageTools(path)[0].handler({action:"digest"});
      expect(result.status).toBe("ok");
      expect(run).toHaveBeenCalledTimes(1);
      expect(run.mock.calls[0][1][3]).toBe("(tag:inbox OR tag:later OR tag:trash) AND (thread:a)");
      expect(result.view!.data).toMatchObject({summary:expect.stringContaining("0 act · 1 look")});
      expect(run.mock.calls[0][2]).toMatchObject({timeout:3500,maxBuffer:2*1024*1024});
    } finally { await rm(dir,{recursive:true,force:true}); }
  });

  it("reading does not remove a Now item", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-read-"));
    try {
      const path = join(dir,"brief.json");
      await writeFile(path,JSON.stringify({mail_triage:{buckets:{...empty(),act:[thread("a")]}}}));
      run.mockReset();
      run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));
      const tool=mailTriageTools(path,async()=>new Map([["a",new Set(["inbox","attention/act"])]]))[0];
      expect((await tool.handler({action:"mark-read",id:"a"})).status).toBe("ok");
      expect(run.mock.calls[0][1]).toEqual(["tag","-unread","--","thread:a"]);
      expect((await tool.handler({action:"digest"})).view!.data).toMatchObject({items:[expect.objectContaining({id:"a"})]});
    } finally {await rm(dir,{recursive:true,force:true});}
  });

  it.each(["not JSON", "{}", '[{"thread":"a","tags":[1]}]', '[{"thread":null,"tags":[]}]'])(
    "rejects malformed live snapshots: %s", async (output) => {
      run.mockReset();
      run.mockImplementation((_bin, _args, _options, callback) => callback(null, output, ""));
      await expect(reflectLiveBuckets({...empty(),act:[thread("a")]})).rejects.toThrow();
      expect(run).toHaveBeenCalledTimes(1);
    });

  it("preserves last-state precedence for conflicting live tags", async () => {
    expect(await reflectLiveBuckets({...empty(),act:[thread("a")]},
      async () => new Map([["a",new Set(["attention/act","attention/look","attention/bulk","attention/junk"])]])))
      .toEqual({...empty(),junk:[thread("a")]});
  });

  it("rejects oversized or invalid cached identities before running notmuch", async () => {
    run.mockReset();
    for (const ids of [Array.from({length:513},(_,i)=>i.toString(16)), ["a OR tag:inbox"]]) {
      await expect(reflectLiveBuckets({...empty(),act:ids.map(thread)})).rejects.toThrow("512 valid hexadecimal");
    }
    expect(run).not.toHaveBeenCalled();
  });

  it("empty classification requires no subprocess", async () => {
    run.mockReset();
    expect(await reflectLiveBuckets(empty())).toEqual(empty());
    expect(run).not.toHaveBeenCalled();
  });

  it("does not resurrect mail from a successful empty snapshot", async () => {
    expect(await reflectLiveBuckets({...empty(),act:[thread("a")]}, async () => new Map())).toEqual(empty());
  });

  it("fails when live placement cannot be read", async () => {
    await expect(reflectLiveBuckets({...empty(),act:[thread("a")]}, async () => {throw Error("offline")}))
      .rejects.toThrow("offline");
  });

  it("caps the Now digest at eight, keeps Act first, and deduplicates", async () => {
    const dir = await mkdtemp(join(tmpdir(),"mail-digest-"));
    try {
      const path = join(dir,"brief.json");
      await writeFile(path, JSON.stringify({mail_triage:{generated_at:"2026-09-07T12:00:00Z",buckets:{
        ...empty(),act:[thread("a")],look:[thread("a"),...Array.from({length:10},(_,i)=>thread(String(i)))],junk:[thread("f")]
      }}}));
      const tool = mailTriageTools(path, async () => new Map(
        ["a","f",...Array.from({length:10},(_,i)=>String(i))].map(id=>[id,new Set(["inbox"])])))[0];
      const result = await tool.handler({action:"digest"});
      expect(result.status).toBe("ok");
      const data = result.view!.data as any;
      expect(result.view!.kind).toBe("list");
      expect(data.items).toHaveLength(8);
      expect(data.items[0].id).toBe("a");
      expect(data.remaining).toBe(3);
      expect(data.items.some((i:any)=>i.id==="f")).toBe(false);
    } finally { await rm(dir,{recursive:true,force:true}); }
  });
});
