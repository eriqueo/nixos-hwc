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
import {bindCommand,cachedBinary,executeFile,safeExec} from "../src/executors/shell.js";
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

describe("timed multi-day creation",()=>{
 beforeEach(()=>{
  run.mockReset();
  run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));
 });
 it("passes both dates and times to khal",async()=>{
  const result=await calendar({action:"create",summary:"Family trip",calendar:"Family",date:"2026-11-01",startTime:"18:00",endDate:"2026-11-03",endTime:"09:00"});
  expect(result.status).toBe("ok");
  expect(run.mock.calls.find(c=>c[1].includes("new"))![1]).toEqual(["new","-a","Family","2026-11-01","18:00","2026-11-03","09:00","Family trip"]);
 });
 it("refuses a reversed range before calling khal",async()=>{
  const result=await calendar({action:"create",summary:"Family trip",date:"2026-11-03",startTime:"18:00",endDate:"2026-11-01",endTime:"09:00"});
  expect(result.status).toBe("error");
  expect(run.mock.calls.some(c=>c[1].includes("new"))).toBe(false);
 });
 it("waits for the Radicale calendar pair after creating an event",async()=>{
  const result=await calendar({action:"create",summary:"Family trip",date:"2026-11-01",startTime:"18:00"});
  expect(run.mock.calls.find(c=>c[1][0]==="sync")?.[1]).toEqual(["sync","calendar_radicale"]);
  expect(result.data).toMatchObject({syncTriggered:true,syncComplete:true});
 });
 it("reports a failed sync without treating the saved event as a failed create",async()=>{
  run.mockImplementation((_bin,args,_options,callback)=>args[0]==="sync" ? callback(Error("failed"),"","sync failed") : callback(null,"",""));
  const result=await calendar({action:"create",summary:"Family trip",date:"2026-11-01"});
  expect(result.status).toBe("ok");
  expect(result.data).toMatchObject({syncComplete:false});
  expect(result.message).toContain("local change saved");
 });
});

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

 it("recreates an edited event with the configured binary, on its own calendar and local time",async()=>{
  // khal names a discovered calendar by the collection's displayname file.
  await writeFile(join(store,"displayname"),"Work jobs\n");
  const result=await calendarTools({khalBin:"/fixture/edit-khal",khalConfig:"/fixture/edit.conf"})[0].handler({action:"edit",query:"client call",newSummary:"Client call",confirm:true});
  expect(result.status).toBe("ok");
  const created=run.mock.calls.find(c=>c[1].includes("new"));
  expect(created![0]).toBe("/fixture/edit-khal");
  expect(created![1]).toEqual(["-c","/fixture/edit.conf","new","-a","Work jobs","2026-10-02","09:00","10:00","Client call","::","Kitchen remodel scope"]);
  expect(existsSync(files.call)).toBe(false);
 });

 it("falls back to the collection directory name when there is no displayname",async()=>{
  await calendar({action:"edit",query:"client call",newSummary:"Client call",confirm:true});
  const created=run.mock.calls.find(c=>c[1].includes("new"));
  expect(created![1].slice(0,3)).toEqual(["new","-a","hwc"]);
 });

 it("keeps the original event when khal cannot create the replacement",async()=>{
  run.mockImplementation((_bin,args,_options,callback)=>
   args.includes("new") ? callback(Error("failed"),"","Unknown calendar") : callback(null,"",""));
  const result=await calendar({action:"edit",query:"client call",newSummary:"Client call",confirm:true});
  expect(result.status).toBe("error");
  expect(existsSync(files.call)).toBe(true);
 });

 it("refuses to flatten a recurring series into one event",async()=>{
  const result=await calendar({action:"edit",query:"crew standup",newSummary:"Standup",confirm:true});
  expect(result.status).toBe("error");
  expect(existsSync(files.standup)).toBe(true);
  expect(run.mock.calls.some(c=>c[1].includes("new"))).toBe(false);
 });
});

describe("repeat calendar creation",()=>{
 beforeEach(()=>{run.mockReset();run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));});
 it("passes repeat and until with a timed multi-day range",async()=>{
  expect((await calendar({action:"create",summary:"Family trip",date:"2026-11-01",startTime:"18:00",endDate:"2026-11-03",endTime:"09:00",repeat:"monthly",until:"2027-11-01"})).status).toBe("ok");
  expect(run.mock.calls.find(c=>c[1].includes("new"))![1]).toEqual(["new","--repeat","monthly","--until","2027-11-01 23:59","2026-11-01","18:00","2026-11-03","09:00","Family trip"]);
 });
 it.each([{repeat:"hourly"},{repeat:"weekly",until:"2026-02-30"},{until:"2027-01-01"},{repeat:"weekly",until:"2026-01-01"}])("rejects invalid repetition %j before writing",async fields=>{
  expect((await calendar({action:"create",summary:"Chore",date:"2026-10-14",...fields})).status).toBe("error");
  expect(run.mock.calls.some(c=>c[1].includes("new"))).toBe(false);
 });
});


describe("mail/calendar command boundary", () => {
 beforeEach(() => { run.mockReset(); });

 it("passes literal arguments to a real process and preserves nonzero exit/output", async () => {
  const actual = await vi.importActual<typeof import("node:child_process")>("node:child_process");
  run.mockImplementation(actual.execFile);
  const literal = "Smith & Sons; $(echo unsafe) | {quote} `literal`";
  const result = await executeFile(process.execPath, ["-e",
   "process.stdout.write(process.argv[1]); process.stderr.write('diagnostic'); process.exitCode=7", literal]);
  expect(result).toEqual({exitCode:7,stdout:literal,stderr:"diagnostic"});
  expect(run).toHaveBeenCalledTimes(1);
 });

 it("reports a real timeout and output overflow as failures without retries", async () => {
  const actual = await vi.importActual<typeof import("node:child_process")>("node:child_process");
  run.mockImplementation(actual.execFile);
  const timeout = await executeFile(process.execPath, ["-e", "setInterval(()=>{},1000)"], {timeout:100});
  expect(timeout.exitCode).not.toBe(0);
  const overflow = await executeFile(process.execPath, ["-e", "process.stdout.write('x'.repeat(4096))"], {maxBuffer:32});
  expect(overflow.exitCode).not.toBe(0);
  expect(run).toHaveBeenCalledTimes(2);
 });

 it.each([new Error("failed"), Object.assign(new Error("missing"),{code:"ENOENT"}),
  Object.assign(new Error("killed"),{code:null})])("does not report success for an error without a numeric exit", async error => {
  run.mockImplementation((_bin,_args,_options,callback)=>callback(error,undefined,undefined));
  expect(await executeFile("fixture",[])).toEqual({exitCode:1,stdout:"",stderr:""});
  expect(run).toHaveBeenCalledTimes(1);
 });

 it("keeps the restrictive infrastructure policy separate from literal argv", async () => {
  await expect(safeExec("fixture",["a;b"])).rejects.toThrow("Unsafe argument");
  expect(run).not.toHaveBeenCalled();
 });

 it("falls back only on ENOENT and caches the selected executable", async () => {
  run.mockImplementation((bin,_args,_options,callback)=>callback(
   Object.assign(new Error("probe"),{code:bin==="missing" ? "ENOENT" : 2}),"",""));
  const binary=cachedBinary(["missing","present","unused"]);
  expect(await binary()).toBe("present");
  expect(await binary()).toBe("present");
  expect(run.mock.calls.map(call=>call[0])).toEqual(["missing","present"]);
  expect(run.mock.calls.every(call=>call[1][0]==="--version" && call[2].timeout===3000)).toBe(true);
 });

 it("does not cache failed discovery and keeps resolver instances separate", async () => {
  run.mockImplementation((_bin,_args,_options,callback)=>callback(Object.assign(new Error("missing"),{code:"ENOENT"})));
  const binary=cachedBinary(["later"]);
  await expect(binary()).rejects.toThrow("Binary not found");
  run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));
  expect(await binary()).toBe("later");
  expect(await cachedBinary(["other"])()).toBe("other");
  expect(run.mock.calls.map(call=>call[0])).toEqual(["later","later","other"]);
 });

 it("shares in-flight discovery but runs each requested action once", async () => {
  let release!: () => void;
  run.mockImplementation((_bin,args,_options,callback)=>{
   if (args[0]==="--version") release=()=>callback(null,"version","");
   else callback(null,"result","");
  });
  const command=bindCommand(cachedBinary(["fixture"]),{});
  const first=command(["first"]), second=command(["second"]);
  expect(run).toHaveBeenCalledTimes(1);
  release();
  await Promise.all([first,second]);
  expect(run.mock.calls.map(call=>call[1])).toEqual([["--version"],["first"],["second"]]);
 });

 it("releases every discovery waiter on failure and permits a later discovery", async () => {
  let release!: () => void;
  run.mockImplementation((_bin,_args,_options,callback)=>{
   release=()=>callback(Object.assign(new Error("missing"),{code:"ENOENT"}));
  });
  const binary=cachedBinary(["fixture"]);
  const failed=Promise.allSettled([binary(),binary()]);
  expect(run).toHaveBeenCalledTimes(1);
  release();
  expect((await failed).map(result=>result.status)).toEqual(["rejected","rejected"]);
  run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"version",""));
  expect(await binary()).toBe("fixture");
  expect(run).toHaveBeenCalledTimes(2);
 });

 it("binds prefixes and default limits while honoring per-call overrides", async () => {
  run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"output",""));
  const command=bindCommand(async()=>"fixture",{maxBuffer:1234},["-c","fixture.conf"]);
  await command(["list"],{timeout:3500});
  await command(["new","literal & title"],{maxBuffer:4321});
  expect(run.mock.calls.map(call=>call.slice(0,3))).toEqual([
   ["fixture",["-c","fixture.conf","list"],{timeout:3500,maxBuffer:1234}],
   ["fixture",["-c","fixture.conf","new","literal & title"],{timeout:15000,maxBuffer:4321}],
  ]);
 });

 it("keeps configured calendar instances independent and runs a failed create once", async () => {
  run.mockImplementation((_bin,args,_options,callback)=>callback(args.includes("new") ? Object.assign(new Error("failed"),{code:7}) : null,"",""));
  const first=calendarTools({khalBin:"/fixture/first",khalConfig:"/fixture/first.conf"})[0];
  const second=calendarTools({khalBin:"/fixture/second",khalConfig:"/fixture/second.conf"})[0];
  await first.handler({action:"list",range:"custom",start:"2026-11-01"});
  await second.handler({action:"list",range:"custom",start:"2026-11-01"});
  const result=await first.handler({action:"create",summary:"Smith & Sons",date:"2026-11-01"});
  expect(result.status).toBe("error");
  const calls=run.mock.calls.filter(call=>call[1][0]!=="--version");
  expect(calls.map(call=>[call[0],call[1].slice(0,2)])).toEqual([
   ["/fixture/first",["-c","/fixture/first.conf"]],
   ["/fixture/second",["-c","/fixture/second.conf"]],
   ["/fixture/first",["-c","/fixture/first.conf"]],
  ]);
  expect(calls[2][1]).toContain("Smith & Sons");
  expect(calls[2][2]).toEqual({timeout:10000,maxBuffer:2*1024*1024});
  expect(run.mock.calls.filter(call=>call[1].includes("new"))).toHaveLength(1);
 });

 it("binds configured command paths at gateway construction", async () => {
  const {allTools}=await import("../src/tools/index.js");
  const {loadConfig}=await import("../src/config.js");
  vi.stubEnv("HWC_KHAL_BIN","/fixture/gateway-khal");
  vi.stubEnv("HWC_KHALT_CONFIG","/fixture/gateway.conf");
  vi.stubEnv("HWC_SYSTEMCTL_BIN","/fixture/systemctl");
  run.mockImplementation((_bin,_args,_options,callback)=>callback(null,"",""));
  try {
   const tools=allTools(loadConfig());
   await tools.find(tool=>tool.name==="hwc_calendar")!.handler({action:"list",range:"custom",start:"2026-11-01"});
   expect(run.mock.calls.find(call=>call[1].includes("list"))?.slice(0,3)).toEqual([
    "/fixture/gateway-khal",["-c","/fixture/gateway.conf","list","--format","{start-time}|{end-time}|{title}|{location}","2026-11-01","2026-11-01"],
    {timeout:3500,maxBuffer:2*1024*1024},
   ]);
   await tools.find(tool=>tool.name==="hwc_mail")!.handler({action:"sync",wait:true});
   expect(run.mock.calls.at(-1)?.slice(0,3)).toEqual([
    "/fixture/systemctl",["--user","start","--wait","mbsync.service"],{timeout:120000,maxBuffer:1024*1024},
   ]);
  } finally {vi.unstubAllEnvs();}
 });
});
