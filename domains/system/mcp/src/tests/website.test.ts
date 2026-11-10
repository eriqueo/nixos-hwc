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

// Configuration and website tools share a checkout identity through allTools.
import {afterEach} from "vitest";
import * as shell from "../src/executors/shell.js";
import {nixEval, flakeMetadata, invalidateNixCache} from "../src/executors/nix.js";
afterEach(() => { invalidateNixCache(); vi.restoreAllMocks(); vi.unstubAllEnvs(); });

it("does not share evaluated options or flake metadata between checkouts", async () => {
 const exec=vi.spyOn(shell,"safeExec").mockImplementation(async (_bin,args) => ({
  exitCode:0,stderr:"",stdout:JSON.stringify({source:args.find(a=>a.startsWith("path:"))}),
 }));
 const a=await nixEval("/checkout/a","hwc-work","example",60);
 const b=await nixEval("/checkout/b","hwc-work","example",60);
 expect(a).not.toEqual(b);
 expect(await nixEval("/checkout/a","hwc-work","example",60)).toEqual(a);
 const ma=await flakeMetadata("/checkout/a",60);
 const mb=await flakeMetadata("/checkout/b",60);
 expect(ma).not.toEqual(mb);
 expect(exec).toHaveBeenCalledTimes(4);
});

it("registered inspection uses fleet metadata and evaluated host/routes instead of Nix literals", async () => {
 const root=await mkdtemp(join(tmpdir(),"config-"));
 try {
  await mkdir(join(root,"machines/work"),{recursive:true});
  await writeFile(join(root,"machines/work/config.nix"),'{ imports = [ ../../domains/example/index.nix ]; networking.hostName = "misleading"; system.stateVersion = "old"; }');
  vi.stubEnv("HWC_NIXOS_CONFIG_PATH",root);
  vi.stubEnv("HWC_MCP_FLEET",JSON.stringify({"hwc-work":{channel:"stable",roles:["base","mail"]}}));
  const routes=[{name:"custom",mode:"vhost",port:19191,upstream:"127.0.0.1:19191",needsUrlBase:false}];
  const values:Record<string,unknown>={"networking.hostName":"hwc-work","system.stateVersion":"26.05","system.nixos.release":"26.05","hwc.networking.shared.routes":routes};
  const exec=vi.spyOn(shell,"safeExec").mockImplementation(async (_bin,args) => {
   const attr=args[1].split(".config.")[1];
   if(!(attr in values)) throw new Error(`Unexpected query ${args[1]}`);
   return {exitCode:0,stderr:"",stdout:JSON.stringify(values[attr])};
  });
  const tool=allTools(loadConfig()).find(t=>t.name==="hwc_config")!;
  expect((tool.inputSchema.properties as any).host.enum).toEqual(["hwc-work"]);
  const profile=await tool.handler({action:"host_profile",host:"hwc-work"});
  expect(profile.status).toBe("ok");
  expect(profile.data).toMatchObject({hostname:"hwc-work",stateVersion:"26.05",channel:"stable (nixos-26.05)",roles:["base","mail"],profiles:["profiles/base","profiles/mail"]});
  const ports=await tool.handler({action:"port_map",host:"hwc-work",filter:"19191"});
  expect(ports.data).toEqual({routes,total:1});
  const calls=exec.mock.calls.length;
  expect((await tool.handler({action:"get_option",host:"not-a-host",option_path:"example"})).error_type).toBe("VALIDATION_ERROR");
  expect(exec).toHaveBeenCalledTimes(calls);
  invalidateNixCache();
  exec.mockResolvedValue({exitCode:1,stdout:"",stderr:"configuration invalid"});
  expect((await tool.handler({action:"port_map",host:"hwc-work"})).status).toBe("error");
 } finally { await rm(root,{recursive:true,force:true}); }
});
