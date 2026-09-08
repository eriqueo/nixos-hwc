import { describe, expect, it } from "vitest";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { mailTriageTools, reflectLiveBuckets } from "../src/tools/mail-triage.js";

const thread = (id: string) => ({thread_id:id, subject:`Thread ${id}`, from_name:"Sender",
  from_address:"", date_relative:"today", tags:[], has_attachment:false,
  summary:"Read the request", suggested_action:"Reply", urgency_reason:"Due today"});

describe("authoritative inbox membership", () => {
  it("does not resurrect mail from a successful empty inbox", async () => {
    expect(await reflectLiveBuckets({urgent:[thread("a")], review:[], noise:[]}, async () => new Set()))
      .toEqual({urgent:[],review:[],noise:[]});
  });
  it("fails when live membership cannot be read", async () => {
    await expect(reflectLiveBuckets({urgent:[],review:[],noise:[]}, async () => {throw Error("offline")}))
      .rejects.toThrow("offline");
  });
  it("wires digest reads, caps at eight, keeps urgent first and deduplicates", async () => {
    const dir = await mkdtemp(join(tmpdir(),"mail-digest-"));
    try {
      const path = join(dir,"brief.json");
      await writeFile(path, JSON.stringify({mail_triage:{generated_at:"2026-09-07T12:00:00Z",buckets:{
        urgent:[thread("a")],review:[thread("a"),...Array.from({length:10},(_,i)=>thread(String(i)))],noise:[thread("f")]
      }}}));
      const tool = mailTriageTools(path, async q => q.startsWith("tag:inbox")
        ? new Set(["a","f",...Array.from({length:10},(_,i)=>String(i))]) : new Set())[0];
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
