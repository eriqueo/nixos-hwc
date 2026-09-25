import {afterAll,beforeEach,describe,expect,it,vi} from "vitest";
const run=vi.hoisted(()=>vi.fn());
// delete/edit read the Radicale store under $HOME, and `khal new` takes local
// wall-clock times, so both are pinned before the tool module loads.
const home=vi.hoisted(()=>{
 const dir=`${process.env.TMPDIR||"/tmp"}/hwc-calendar-test-${process.pid}`;
 process.env.HOME=dir;process.env.TZ="America/Denver";
 return dir;
});
vi.mock("node:child_process",()=>({execFile:run,spawn:vi.fn()}));
import {existsSync} from "node:fs";
import {mkdir,rm,writeFile} from "node:fs/promises";
import {join} from "node:path";
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

// Apple and Radicale put a VTIMEZONE block ahead of the VEVENT, and its
// STANDARD/DAYLIGHT sub-blocks carry their own DTSTART (172 of 196 live files).
const ics=(...event:string[])=>[
 "BEGIN:VCALENDAR","VERSION:2.0",
 "BEGIN:VTIMEZONE","TZID:America/New_York",
 "BEGIN:DAYLIGHT","DTSTART:20070311T020000","RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU","TZOFFSETFROM:-0500","TZOFFSETTO:-0400","END:DAYLIGHT",
 "BEGIN:STANDARD","DTSTART:20071104T020000","RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU","TZOFFSETFROM:-0400","TZOFFSETTO:-0500","END:STANDARD",
 "END:VTIMEZONE",
 "BEGIN:VEVENT",...event,"END:VEVENT",
 "END:VCALENDAR",""].join("\n");
const store=join(home,".local/share/vdirsyncer/calendars-radicale/hwc");
const files={
 call:join(store,"call.ics"),
 standup:join(store,"standup.ics"),
 closed:join(store,"closed.ics"),
};
const calendar=(args:Record<string,unknown>)=>calendarTools()[0].handler(args);

describe("delete and edit read the event itself",()=>{
 beforeEach(async()=>{
  await rm(home,{recursive:true,force:true});
  await mkdir(store,{recursive:true});
  await writeFile(files.call,ics(
   "UID:call@test","DTSTART;TZID=America/New_York:20261002T110000","DTEND;TZID=America/New_York:20261002T120000",
   "SUMMARY:Client call\\, Smith",
   "BEGIN:VALARM","ACTION:DISPLAY","DESCRIPTION:Reminder","TRIGGER:-PT15M","END:VALARM",
   "DESCRIPTION:Kitchen remodel "," scope"));
  await writeFile(files.standup,ics(
   "UID:standup@test","DTSTART:20260915T150000Z","DTEND:20260915T153000Z","RRULE:FREQ=WEEKLY;BYDAY=TU","SUMMARY:Crew standup"));
  await writeFile(files.closed,ics(
   "UID:closed@test","DTSTART;VALUE=DATE:20261012","DTEND;VALUE=DATE:20261013","SUMMARY:Shop closed"));
  run.mockReset();
  run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));
 });
 afterAll(()=>rm(home,{recursive:true,force:true}));

 it("reports the VEVENT start in khal's zone, not the VTIMEZONE's",async()=>{
  const call=await calendar({action:"delete",query:"client call",filter_date:"2026-10-02"});
  expect(call.data).toMatchObject({matchCount:1,matches:[{summary:"Client call, Smith",dtstart:"20261002T110000",start:"2026-10-02 09:00",recurring:false}]});
  const standup=await calendar({action:"delete",query:"crew standup"});
  expect(standup.data).toMatchObject({matches:[{start:"2026-09-15 09:00",recurring:true}]});
  const closed=await calendar({action:"delete",query:"shop closed",filter_date:"2026-10-12"});
  expect(closed.data).toMatchObject({matches:[{start:"2026-10-12",recurring:false}]});
 });

 it("previews an edit from the event's own fields",async()=>{
  const preview=await calendar({action:"edit",query:"client call",newSummary:"Client call"});
  expect(preview.status).toBe("ok");
  expect(preview.data).toMatchObject({changes:{
   summary:{from:"Client call, Smith",to:"Client call"},
   date:{from:"2026-10-02",to:"2026-10-02"},
   startTime:{from:"09:00"},endTime:{from:"10:00"},
   description:{from:"Kitchen remodel scope"},
  }});
 });

 it("recreates an edited event at the same local time",async()=>{
  const result=await calendar({action:"edit",query:"client call",newSummary:"Client call",confirm:true});
  expect(result.status).toBe("ok");
  const created=run.mock.calls.find(c=>c[1].includes("new"));
  expect(created![1]).toEqual(["new","2026-10-02","09:00","10:00","Client call","::","Kitchen remodel scope"]);
 });

 it("refuses to flatten a recurring series into one event",async()=>{
  const result=await calendar({action:"edit",query:"crew standup",newSummary:"Standup",confirm:true});
  expect(result.status).toBe("error");
  expect(existsSync(files.standup)).toBe(true);
  expect(run.mock.calls.some(c=>c[1].includes("new"))).toBe(false);
 });
});
