import { describe, expect, it, vi } from "vitest";
const run = vi.hoisted(() => vi.fn());
const spawnRun = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({execFile: run, spawn: spawnRun}));
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mailTriageTools, reflectLiveBuckets } from "../src/tools/mail-triage.js";
import { morningBriefTool } from "../src/tools/morning-brief.js";

const thread = (id: string) => ({
  thread_id: id, subject: `Thread ${id}`, sender: "Sender", tags: [],
});

describe("morning briefing mail routing rules", () => {
  it("shows active rules in the Workbench briefing detail", async () => {
    const dir = await mkdtemp(join(tmpdir(), "morning-brief-"));
    try {
      const path = join(dir, "briefing.json");
      await writeFile(path, JSON.stringify({
        generated_at: new Date().toISOString(),
        sections: {mail: {healthy: true}},
        alerts: [],
        mail_triage: {
          stats: {do_count: 1, did_count: 0, look_count: 0, junk_count: 0},
          buckets: {do: [], did: [], look: [], junk: []},
          routing_rules: [{
            sender: "office@example.com",
            subject_contains: "[P1 CRITICAL]",
            state: "do",
            domain: "hwc",
          }],
        },
      }));

      const result = await morningBriefTool(path).handler({});
      expect(result.status).toBe("ok");
      expect(result.view?.data).toMatchObject({
        body: expect.stringContaining("Routing rules: **1 active**"),
      });
      expect((result.view?.data as {body:string}).body)
        .toContain("office@example.com + “[P1 CRITICAL]” → DO · HWC");
    } finally {
      await rm(dir, {recursive: true, force: true});
    }
  });
});
const empty = () => ({ do: [], did: [], look: [], junk: [] });

describe("authoritative mail placement", () => {
  it("one production scan supplies membership and live workflow states", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-scan-"));
    try {
      const path = join(dir, "brief.json");
      await writeFile(path, JSON.stringify({mail_triage:{buckets:{...empty(),do:[thread("a")]}}}));
      run.mockReset();
      run.mockImplementation((_bin, args, _options, callback) => callback(null,
        args.includes("--format=json") ? JSON.stringify([{thread:"a", tags:["archive","state/look"]}]) : "thread:a\n", ""));
      const result = await mailTriageTools(path)[0].handler({action:"digest"});
      expect(result.status).toBe("ok");
      expect(run).toHaveBeenCalledTimes(1);
      expect(run.mock.calls[0][1][3]).toBe("(tag:state/do OR tag:state/did OR tag:state/look OR tag:state/junk) AND (thread:a)");
      expect(result.view!.data).toMatchObject({summary:expect.stringContaining("0 do")});
      expect(run.mock.calls[0][2]).toMatchObject({timeout:3500,maxBuffer:2*1024*1024});
    } finally { await rm(dir,{recursive:true,force:true}); }
  });

  it("reading does not remove a Now item", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-read-"));
    try {
      const path = join(dir,"brief.json");
      await writeFile(path,JSON.stringify({mail_triage:{buckets:{...empty(),do:[thread("a")]}}}));
      run.mockReset();
      run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));
      const tool=mailTriageTools(path,async()=>new Map([["a",new Set(["inbox","state/do"])]]))[0];
      expect((await tool.handler({action:"mark-read",id:"a"})).status).toBe("ok");
      expect(run.mock.calls[0][1]).toEqual(["tag","-unread","--","thread:a"]);
      expect((await tool.handler({action:"digest"})).view!.data).toMatchObject({items:[expect.objectContaining({id:"a"})]});
    } finally {await rm(dir,{recursive:true,force:true});}
  });

  it("routes a state move through the classifier ledger", async () => {
    run.mockReset();
    spawnRun.mockReset();
    run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"From sender@example.com\nMessage-ID: <a@example.com>\n\nbody\n",""));
    const stdin = {end: vi.fn()};
    spawnRun.mockImplementation(() => {
      const child = {
        stdin,
        stderr: {on: vi.fn()},
        on: vi.fn((event:string, callback:(code:number)=>void) => {
          if (event === "close") queueMicrotask(() => callback(0));
          return child;
        }),
      };
      return child;
    });
    const result = await mailTriageTools("unused")[0].handler({action:"state-did",id:"a"});
    expect(result.status).toBe("ok");
    expect(spawnRun).toHaveBeenCalledWith("/run/current-system/sw/bin/mail-classifier-runtime",
      expect.arrayContaining(["correct","--state","did"]), expect.any(Object));
    expect(stdin.end).toHaveBeenCalledWith(expect.stringContaining("Message-ID"));
  });

  it.each(["not JSON", "{}", '[{"thread":"a","tags":[1]}]', '[{"thread":null,"tags":[]}]'])(
    "rejects malformed live snapshots: %s", async (output) => {
      run.mockReset();
      run.mockImplementation((_bin, _args, _options, callback) => callback(null, output, ""));
      await expect(reflectLiveBuckets({...empty(),do:[thread("a")]})).rejects.toThrow();
      expect(run).toHaveBeenCalledTimes(1);
    });

  it("uses conservative DO precedence for conflicting live tags", async () => {
    expect(await reflectLiveBuckets({...empty(),do:[thread("a")]},
      async () => new Map([["a",new Set(["state/do","state/did","state/look","state/junk"])]])))
      .toEqual({...empty(),do:[thread("a")]});
  });

  it("rejects oversized or invalid cached identities before running notmuch", async () => {
    run.mockReset();
    for (const ids of [Array.from({length:513},(_,i)=>i.toString(16)), ["a OR tag:inbox"]]) {
      await expect(reflectLiveBuckets({...empty(),do:ids.map(thread)})).rejects.toThrow("512 valid hexadecimal");
    }
    expect(run).not.toHaveBeenCalled();
  });

  it("empty classification requires no subprocess", async () => {
    run.mockReset();
    expect(await reflectLiveBuckets(empty())).toEqual(empty());
    expect(run).not.toHaveBeenCalled();
  });

  it("does not resurrect mail from a successful empty snapshot", async () => {
    expect(await reflectLiveBuckets({...empty(),do:[thread("a")]}, async () => new Map())).toEqual(empty());
  });

  it("fails when live placement cannot be read", async () => {
    await expect(reflectLiveBuckets({...empty(),do:[thread("a")]}, async () => {throw Error("offline")}))
      .rejects.toThrow("offline");
  });

  it("caps the DO digest at eight and excludes other states", async () => {
    const dir = await mkdtemp(join(tmpdir(),"mail-digest-"));
    try {
      const path = join(dir,"brief.json");
      await writeFile(path, JSON.stringify({mail_triage:{generated_at:"2026-09-07T12:00:00Z",routing_rules:[{},{}],buckets:{
        ...empty(),do:[thread("a"),...Array.from({length:10},(_,i)=>thread(String(i)))],look:[thread("e")],junk:[thread("f")]
      }}}));
      const tool = mailTriageTools(path, async () => new Map(
        ["a","e","f",...Array.from({length:10},(_,i)=>String(i))].map(id=>[id,new Set([id === "f" ? "state/junk" : id === "e" ? "state/look" : "state/do"])])))[0];
      const result = await tool.handler({action:"digest"});
      expect(result.status).toBe("ok");
      const data = result.view!.data as any;
      expect(result.view!.kind).toBe("list");
      expect(data.items).toHaveLength(8);
      expect(data.items[0].id).toBe("a");
      expect(data.remaining).toBe(3);
      expect(data.summary).toContain("2 routing rules");
      expect(result.data).toMatchObject({routing_rule_count:2});
      expect(data.items.some((i:any)=>i.id==="f")).toBe(false);
    } finally { await rm(dir,{recursive:true,force:true}); }
  });
});
