import {expect,it,vi} from "vitest";
import {siteAnalyticsTools} from "../src/tools/site-analytics.js";
import {allTools} from "../src/tools/index.js";
import {loadConfig} from "../src/config.js";
const id="00000000-0000-0000-0000-000000000001";
it("registers analytics through the real aggregator",()=>{
  expect(allTools(loadConfig()).map(t=>t.name)).toContain("hwc_site_analytics");
});
it("only queries the configured website with a read-only bounded aggregate",async()=>{
 const query=vi.fn(async()=>({exitCode:0,stderr:"",stdout:JSON.stringify({visits:12,pageviews:20,previous_visits:8,pages:[{url_path:"/",views:10}]})}));
 const result=await siteAnalyticsTools(id,"umami",query)[0].handler({});
 expect(result.status).toBe("ok");
 expect(result.view!.data).toMatchObject({greeting:"12 visits · 20 page views"});
 expect(query).toHaveBeenCalledWith(expect.stringContaining(`e.website_id='${id}'`),"umami",{timeout:4000});
 expect(query.mock.calls[0][0]).toContain("BEGIN READ ONLY");
 expect(query.mock.calls[0][0]).toContain("LIMIT 5");
});
it("rejects missing or untrusted identity before SQL",async()=>{
 const query=vi.fn();
 expect((await siteAnalyticsTools("' OR true;--","umami",query)[0].handler({})).status).toBe("error");
 expect(query).not.toHaveBeenCalled();
});
it("failed analytics remains a failure",async()=>{
 const query=async()=>({exitCode:1,stderr:"unavailable",stdout:""});
 expect((await siteAnalyticsTools(id,"umami",query)[0].handler({})).status).toBe("error");
});

it("parses PostgreSQL multiline aggregate output and command tags",async()=>{
 const query=async()=>({exitCode:0,stderr:"",stdout:'BEGIN\nSET\n{"visits":86,"pageviews":109,"previous_visits":79,"pages":[{"url_path":"/","views":21},\n {"url_path":"/contact/","views":7}]}\nCOMMIT\n'});
 const result=await siteAnalyticsTools(id,"umami",query)[0].handler({});
 expect(result.status).toBe("ok");
 expect(result.view!.data).toMatchObject({greeting:"86 visits · 109 page views"});
});
