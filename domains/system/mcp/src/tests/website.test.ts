import {it, expect, vi} from "vitest";
import {mkdtemp, mkdir, readFile, writeFile, rm} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {allTools} from "../src/tools/index.js";
import {loadConfig} from "../src/config.js";
it("configured website root controls actual registered content and trash operations", async () => {
 const root=await mkdtemp(join(tmpdir(),"website-"));
 try {
  for(const d of ["pages","blog","_data"]) await mkdir(join(root,"src",d),{recursive:true});
  await writeFile(join(root,"src/pages/about.md"),"---\ntitle: About\n---\nOriginal");
  vi.stubEnv("HWC_WEBSITE_SITE_DIR", root);
  vi.stubEnv("HWC_NIXOS_CONFIG_PATH", join(root,"not-the-website"));
  const tool=allTools(loadConfig()).find(t=>t.name==="hwc_website")!;
  expect((await tool.handler({action:"list",type:"pages"})).status).toBe("ok");
  expect((await tool.handler({action:"read",type:"pages",slug:"about"})).status).toBe("ok");
  expect((await tool.handler({action:"write",type:"pages",slug:"about",frontmatter:{title:"About"},body:"Updated"})).status).toBe("ok");
  expect(await readFile(join(root,"src/pages/about.md"),"utf8")).toContain("Updated");
  const result=await tool.handler({action:"delete",type:"pages",slug:"about"});
  expect(result.status).toBe("ok");
  expect((result.data as {trashedTo:string}).trashedTo).toMatch(`${root}/.trash/`);
  expect((await tool.handler({action:"read",type:"pages",slug:"../../outside"})).status).toBe("error");
 } finally {vi.unstubAllEnvs();await rm(root,{recursive:true,force:true});}
});
