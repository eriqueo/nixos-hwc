import {expect,it,vi} from "vitest";
const run=vi.hoisted(()=>vi.fn());
vi.mock("node:child_process",()=>({execFile:run,spawn:vi.fn()}));
import {calendarTools} from "../src/tools/calendar.js";
it("week read uses seven dated days and preserves event data",async()=>{
 vi.useFakeTimers();vi.setSystemTime(new Date("2026-09-07T16:00:00Z"));
 run.mockImplementation((_bin,args,_options,callback)=>{
   callback(null,args.includes("list") ? "Monday, 2026-09-07 Today\n09:00|10:00|Estimate|Office\n" : "khal 1","");
 });
 try {
   const result=await calendarTools()[0].handler({action:"list",range:"week"});
   expect(result.status).toBe("ok");
   expect(result.view!.data).toMatchObject({start_date:"2026-09-07",items:[{label:"Estimate",time:"09:00",end_time:"10:00",date:"2026-09-07"}]});
   const list=run.mock.calls.find(c=>c[1].includes("list"));
   expect(list![1].slice(-2)).toEqual(["2026-09-07","2026-09-13"]);
   expect(list![2].timeout).toBe(3500);
 } finally {vi.useRealTimers()}
});
it("failed khal command is not an empty successful calendar",async()=>{
 run.mockImplementation((_bin,_args,_options,callback)=>callback(Error("failed"),"","bad config"));
 expect((await calendarTools()[0].handler({action:"list",range:"week"})).status).toBe("error");
});
