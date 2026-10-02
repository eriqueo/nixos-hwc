import { describe, expect, it, vi } from "vitest";
const run = vi.hoisted(() => vi.fn());
const spawnRun = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({execFile: run, spawn: spawnRun}));
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mailTools, mailTagActions, MAIL_STATES } from "../src/tools/mail.js";
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
const empty = () => Object.fromEntries(MAIL_STATES.map(state => [state, []]));

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
      expect(run.mock.calls[0][1][3]).toBe("(tag:state/do OR tag:state/dont-know OR tag:state/did OR tag:state/look OR tag:state/junk) AND (thread:a)");
      expect(result.view!.data).toMatchObject({summary:expect.stringContaining("0 DO")});
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
    const stdin = {end: vi.fn(), on: vi.fn()};
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
    expect(spawnRun).toHaveBeenCalledWith("/run/current-system/sw/bin/flock",
      ["-n", "-E", "75", expect.stringMatching(/\/mail-sync\/sync\.lock$/),
        "/run/current-system/sw/bin/mail-classifier-runtime", "correct", "--db",
        "/var/lib/hwc/mail-classifier/ledger.sqlite", "--notmuch", expect.any(String),
        "--state", "did"], expect.any(Object));
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


describe("current mail views and metadata preservation", () => {
  it.each([
    ["state:do", "tag:state/do"],
    ["state:dont-know", "tag:state/dont-know"],
    ["domain:family", "tag:domain/family"],
    ["fact:finance", "tag:trait/finance"],
  ])("resolves %s through the actual mail search handler", async (name, query) => {
    run.mockReset();
    run.mockImplementation((_bin, _args, _options, callback) => callback(null, "0", ""));
    const result = await mailTools()[0].handler({action: "search", query: name, count_only: true});
    expect(result.status).toBe("ok");
    expect(run.mock.calls.at(-1)![1]).toEqual(["count", query]);
  });

  it("clears optional facts without touching stars, Domain, State or history", async () => {
    const operations = mailTagActions()["clear-metadata"];
    expect(operations).toContain("-trait/finance");
    for (const protectedOperation of [
      "-flagged", "-starred", "-keep", "-state/do", "-state/dont-know", "-domain/hwc", "-work", "-finance",
    ]) expect(operations).not.toContain(protectedOperation);
    run.mockReset();
    run.mockImplementation((_bin, _args, _options, callback) => callback(null, "", ""));
    const result = await mailTools()[0].handler({action: "tag", query: "id:fixture@example.com", tag_action: "clear-metadata"});
    expect(result.status).toBe("ok");
    expect(run.mock.calls[0][1]).toEqual(["tag", ...operations, "--", "id:fixture@example.com"]);
  });
});

describe("DONT KNOW consumer contract", () => {
  it("rebuckets an old four-State cache into DONT KNOW without losing its thread", async () => {
    const legacy = {do: [thread("a")], did: [], look: [], junk: []};
    expect(await reflectLiveBuckets(legacy, async () => new Map([["a", new Set(["state/dont-know", "state/did"])]])))
      .toEqual({...empty(), "dont-know": [thread("a")]});
    expect(await reflectLiveBuckets(legacy, async () => new Map([["a", new Set(["state/do", "state/dont-know"])]])))
      .toEqual({...empty(), do: [thread("a")]});
  });

  it("shows DONT KNOW on the board and count while keeping it out of the action digest", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-unknown-"));
    try {
      const path = join(dir, "brief.json");
      await writeFile(path, JSON.stringify({mail_triage: {buckets: {do: [thread("a")], did: [], look: [], junk: []}}}));
      const tool = mailTriageTools(path, async () => new Map([["a", new Set(["state/dont-know"])]]))[0];
      const board = await tool.handler({action: "board"});
      expect(board.status).toBe("ok");
      expect(board.data).toMatchObject({stats: {"dont-know_count": 1, do_count: 0}});
      expect(board.view!.data).toMatchObject({columns: expect.arrayContaining([
        {id: "dont-know", title: "DONT KNOW", cards: [expect.objectContaining({id: "a", priority: "normal"})]},
      ])});
      const digest = await tool.handler({action: "digest"});
      expect(digest.view!.data).toMatchObject({items: [], summary: expect.stringContaining("1 DONT KNOW")});
      await writeFile(path, JSON.stringify({mail_triage: {stats: {"dont-know_count": 1}, buckets: {"dont-know": [thread("a")]}}}));
      expect((await morningBriefTool(path).handler({})).view!.data)
        .toMatchObject({body: expect.stringContaining("1 DONT KNOW")});
    } finally {await rm(dir, {recursive: true, force: true});}
  });

  it("resolves Bulk from the producer even with a stale overriding search registry", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-bulk-"));
    try {
      const file = join(dir, "searches");
      await writeFile(file, "# mail-searches-v1\nview:bulk=tag:inbox\nstate:dont-know=tag:state/do\n");
      const contract = JSON.parse(await import("node:fs/promises").then(fs => fs.readFile(process.env.HWC_MAIL_CLASSIFIER_CONTRACT_FILE!, "utf8")));
      vi.stubEnv("HWC_MAIL_SEARCHES_FILE", file);
      vi.resetModules();
      const module = await import("../src/tools/mail.js");
      run.mockReset();
      run.mockImplementation((_bin, _args, _options, callback) => callback(null, "0", ""));
      expect((await module.mailTools()[0].handler({action: "search", query: "view:bulk", count_only: true})).status).toBe("ok");
      expect(run.mock.calls.at(-1)![1]).toEqual(["count", contract.viewQueries.bulk]);
    } finally {vi.unstubAllEnvs(); vi.resetModules(); await rm(dir, {recursive: true, force: true});}
  });

  it("fails startup without a canonical contract and accepts the old version during expansion", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-contract-"));
    try {
      const contract = JSON.parse(await import("node:fs/promises").then(fs => fs.readFile(process.env.HWC_MAIL_CLASSIFIER_CONTRACT_FILE!, "utf8")));
      vi.stubEnv("HWC_MAIL_CLASSIFIER_CONTRACT_FILE", "");
      vi.resetModules();
      await expect(import("../src/tools/mail.js")).rejects.toThrow("is required");
      const file = join(dir, "v2.json");
      await writeFile(file, JSON.stringify({...contract, schemaVersion: 2, states: contract.states.filter((state: string) => state !== contract.fallbackState), fallbackState: contract.actionState}));
      vi.stubEnv("HWC_MAIL_CLASSIFIER_CONTRACT_FILE", file);
      vi.resetModules();
      expect((await import("../src/tools/mail.js")).MAIL_STATES).not.toContain("dont-know");
      await writeFile(file, JSON.stringify({...contract, stateDisplayNames: {}}));
      vi.resetModules();
      await expect(import("../src/tools/mail.js")).rejects.toThrow("invalid mail State/view");
    } finally {vi.unstubAllEnvs(); vi.resetModules(); await rm(dir, {recursive: true, force: true});}
  });
});


describe("generated mail search registry", () => {
  it("uses the deployed registry for historical search and additive custom facts", async () => {
    const dir = await mkdtemp(join(tmpdir(), "mail-searches-"));
    const file = join(dir, "searches");
    try {
      await writeFile(file, "# mail-searches-v1\nhistory:business=tag:work\ncustom-fact:ads=tag:ads AND NOT tag:trash\n");
      vi.stubEnv("HWC_MAIL_SEARCHES_FILE", file);
      vi.resetModules();
      const module = await import("../src/tools/mail.js");
      run.mockReset();
      run.mockImplementation((_bin, _args, _options, callback) => callback(null, "0", ""));
      expect((await module.mailTools()[0].handler({action: "search", query: "history:business", count_only: true})).status).toBe("ok");
      expect(run.mock.calls.at(-1)![1]).toEqual(["count", "tag:work"]);
      expect(module.mailTagActions()["clear-metadata"]).toContain("-ads");
      expect(module.mailTagActions()["clear-metadata"]).not.toContain("-work");
    } finally {
      vi.unstubAllEnvs();
      vi.resetModules();
      await rm(dir, {recursive: true, force: true});
    }
  });
});


describe("mail actions record local placement intent", () => {
  it.each([
    ["archive", "transition", "--outcome", "done"],
    ["trash", "transition", "--outcome", "trash"],
    ["delete", "transition", "--outcome", "trash"],
    ["untrash", "reopen", null, null],
    ["unspam", "reopen", null, null],
    ["spam", "correct", "--state", "junk"],
  ])("routes %s through the shared command", async (action, command, axis, value) => {
    run.mockReset(); spawnRun.mockReset();
    run.mockImplementation((_bin, _args, _options, callback) => callback(null,
      "From sender@example.com\nMessage-ID: <fixture@example.com>\n\nbody\n", ""));
    const stdin = {end: vi.fn(), on: vi.fn()};
    spawnRun.mockImplementation(() => {
      const child = {stdin, stderr: {on: vi.fn()}, on: vi.fn((event: string, callback: (code: number) => void) => {
        if (event === "close") queueMicrotask(() => callback(0));
        return child;
      })};
      return child;
    });
    expect((await mailTools()[0].handler({action: "tag", query: "thread:a", tag_action: action})).status).toBe("ok");
    expect(run.mock.calls.at(-1)![1]).toEqual(["show", "--format=mbox", "--entire-thread=true", "--", "thread:a"]);
    expect(run.mock.calls.some((call) => call[1][0] === "tag")).toBe(false);
    expect(spawnRun.mock.calls[0][0]).toBe("/run/current-system/sw/bin/flock");
    expect(spawnRun.mock.calls[0][1].slice(0, 4)).toEqual([
      "-n", "-E", "75", expect.stringMatching(/\/mail-sync\/sync\.lock$/)]);
    expect(spawnRun.mock.calls[0][1][5]).toBe(command);
    if (axis) expect(spawnRun.mock.calls[0][1]).toEqual(expect.arrayContaining([axis, value]));
    expect(stdin.end).toHaveBeenCalledWith(expect.stringContaining("Message-ID"));
  });

  it.each(["+trash", "-trash", "+inbox", "-inbox", "+archive", "+spam"])(
    "rejects raw placement %s before mutation", async (tag) => {
      run.mockReset(); spawnRun.mockReset();
      run.mockImplementation((_bin, _args, _options, callback) => callback(null, "", ""));
      expect((await mailTools()[0].handler({action: "tag", query: "thread:a", tags: [tag]})).status).toBe("error");
      expect(run).not.toHaveBeenCalled(); expect(spawnRun).not.toHaveBeenCalled();
    });

  it("reports selection failure without attempting a disposition", async () => {
    run.mockReset(); spawnRun.mockReset();
    run.mockImplementation((_bin, _args, _options, callback) => callback({code: 1}, "", "selection failed"));
    expect((await mailTools()[0].handler({action: "tag", query: "thread:a", tag_action: "archive"})).status).toBe("error");
    expect(spawnRun).not.toHaveBeenCalled();
  });
});


describe("disposition command failure", () => {
  it.each([7, 75])("returns an error without retrying failed or busy command %s", async (exitCode) => {
    run.mockReset(); spawnRun.mockReset();
    run.mockImplementation((_bin, _args, _options, callback) => callback(null,
      "From sender@example.com\nMessage-ID: <fixture@example.com>\n\nbody\n", ""));
    spawnRun.mockImplementation(() => {
      const child = {stdin: {end: vi.fn(), on: vi.fn()}, stderr: {on: vi.fn()},
        on: vi.fn((event: string, callback: (code: number) => void) => {
          if (event === "close") queueMicrotask(() => callback(exitCode)); return child;
        })};
      return child;
    });
    expect((await mailTools()[0].handler({action: "tag", query: "thread:a", tag_action: "trash"})).status).toBe("error");
    expect(spawnRun).toHaveBeenCalledTimes(1);
    expect(spawnRun.mock.calls[0][2]).toMatchObject({timeout: 30_000});
    expect(run.mock.calls.some((call) => call[1][0] === "tag")).toBe(false);
  });
});
