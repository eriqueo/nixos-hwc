import { describe, expect, it, vi } from "vitest";
const run = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({execFile: run, spawn: vi.fn()}));
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mailTriageTools, reflectLiveBuckets } from "../src/tools/mail-triage.js";

const thread = (id: string) => ({thread_id:id, subject:`Thread ${id}`, from_name:"Sender",
  from_address:"", date_relative:"today", tags:[], has_attachment:false,
  summary:"Read the request", suggested_action:"Reply", urgency_reason:"Due today"});

describe("authoritative inbox membership", () => {
  it("one production scan supplies inbox membership and live buckets", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-scan-"));
    try {
      const path = join(dir, "brief.json");
      await writeFile(path, JSON.stringify({mail_triage:{buckets:{urgent:[thread("a")],review:[],noise:[]}}}));
      run.mockReset();
      run.mockImplementation((_bin, args, _options, callback) => callback(null,
        args.includes("--format=json") ? JSON.stringify([{thread:"a", tags:["inbox","unread","triage/review"]}]) : "thread:a\n", ""));
      const result = await mailTriageTools(path)[0].handler({action:"digest"});
      expect(result.status).toBe("ok");
      expect(run).toHaveBeenCalledTimes(1);
      expect(run.mock.calls[0][1][3]).toBe("tag:inbox AND NOT tag:trash AND (thread:a)");
      expect(result.view!.data).toMatchObject({summary:expect.stringContaining("0 urgent · 1 to review")});
      expect(run.mock.calls[0][2]).toMatchObject({timeout:3500,maxBuffer:2*1024*1024});
    } finally { await rm(dir,{recursive:true,force:true}); }
  });
  it("mark read targets one thread and the digest excludes read mail", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-read-"));
    try {
      const path = join(dir,"brief.json");
      await writeFile(path,JSON.stringify({mail_triage:{buckets:{urgent:[thread("a")],review:[],noise:[]}}}));
      run.mockReset();
      run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));
      const tool=mailTriageTools(path,async()=>new Map([["a",new Set(["inbox","triage/urgent"])]]))[0];
      expect((await tool.handler({action:"mark-read",id:"a"})).status).toBe("ok");
      expect(run.mock.calls[0][1]).toEqual(["tag","-unread","--","thread:a"]);
      expect((await tool.handler({action:"digest"})).view!.data).toMatchObject({items:[]});
      expect((await tool.handler({action:"board"})).view!.data).toMatchObject({columns:expect.arrayContaining([expect.objectContaining({cards:expect.arrayContaining([expect.objectContaining({id:"a"})])})])});
    } finally {await rm(dir,{recursive:true,force:true});}
  });
  it.each(["not JSON", "{}", '[{"thread":"a","tags":[1]}]', '[{"thread":null,"tags":[]}]'])(
    "rejects malformed live snapshots instead of resurrecting cached mail: %s", async (output) => {
      run.mockReset();
      run.mockImplementation((_bin, _args, _options, callback) => callback(null, output, ""));
      await expect(reflectLiveBuckets({urgent:[thread("a")], review:[], noise:[]})).rejects.toThrow();
      expect(run).toHaveBeenCalledTimes(1);
    });
  it("preserves last-bucket precedence for threads with conflicting live tags", async () => {
    expect(await reflectLiveBuckets({urgent:[thread("a")], review:[], noise:[]},
      async () => new Map([["a",new Set(["triage/urgent","triage/review","triage/noise"])]])))
      .toEqual({urgent:[],review:[],noise:[thread("a")]});
  });
  it("rejects oversized or invalid cached identities before running notmuch", async () => {
    run.mockReset();
    for (const ids of [Array.from({length:513},(_,i)=>i.toString(16)), ["a OR tag:inbox"]]) {
      await expect(reflectLiveBuckets({urgent:ids.map(thread),review:[],noise:[]})).rejects.toThrow("512 valid hexadecimal");
    }
    expect(run).not.toHaveBeenCalled();
  });
  it("empty triage requires no subprocess", async () => {
    run.mockReset();
    expect(await reflectLiveBuckets({urgent:[],review:[],noise:[]})).toEqual({urgent:[],review:[],noise:[]});
    expect(run).not.toHaveBeenCalled();
  });
  it("does not resurrect mail from a successful empty inbox", async () => {
    expect(await reflectLiveBuckets({urgent:[thread("a")], review:[], noise:[]}, async () => new Map()))
      .toEqual({urgent:[],review:[],noise:[]});
  });
  it("fails when live membership cannot be read", async () => {
    await expect(reflectLiveBuckets({urgent:[thread("a")],review:[],noise:[]}, async () => {throw Error("offline")}))
      .rejects.toThrow("offline");
  });
  it("wires digest reads, caps at eight, keeps urgent first and deduplicates", async () => {
    const dir = await mkdtemp(join(tmpdir(),"mail-digest-"));
    try {
      const path = join(dir,"brief.json");
      await writeFile(path, JSON.stringify({mail_triage:{generated_at:"2026-09-07T12:00:00Z",buckets:{
        urgent:[thread("a")],review:[thread("a"),...Array.from({length:10},(_,i)=>thread(String(i)))],noise:[thread("f")]
      }}}));
      const tool = mailTriageTools(path, async () => new Map(
        ["a","f",...Array.from({length:10},(_,i)=>String(i))].map(id=>[id,new Set(["inbox","unread"])])))[0];
      const result = await tool.handler({action:"digest"});
      expect(result.status).toBe("ok");
      const data = result.view!.data as any;
      expect(result.view!.kind).toBe("list");
      expect(data.items).toHaveLength(8);
      expect(data.items[0].id).toBe("a");
      expect(data.remaining).toBe(3);
      expect(data.items.some((i:any)=>i.id==="f")).toBe(false);
      expect(data.items[0].suggested_action).toBe("Reply");
    } finally { await rm(dir,{recursive:true,force:true}); }
  });
});
