import { beforeEach, describe, expect, it, vi } from "vitest";
import { buildVtodo, editVtodo, fixedRecurrence, nextScheduledDate, parseVtodo } from "../src/executors/caldav.js";
import { tasksTools, weeklyRecurrence, mealTools } from "../src/tools/tasks.js";

describe("weekly task recurrence", () => {
  it("renders a timezone-aware Thursday reminder", () => {
    const recurrence = weeklyRecurrence({
      frequency: "weekly",
      weekday: "TH",
      startDate: "2026-09-24",
      time: "09:00",
      timezone: "America/Denver",
    });
    expect(recurrence).not.toBeNull();
    const ics = buildVtodo({
      uid: "review-mail@example",
      summary: "Review Later and Junk mail",
      due: "2026-09-24",
      ...recurrence!,
    });
    expect(ics).toContain("DTSTART;TZID=America/Denver:20260924T090000");
    expect(ics).toContain("DUE;TZID=America/Denver:20260924T090000");
    expect(ics).toContain("RRULE:FREQ=WEEKLY;BYDAY=TH");
  });

  it("rejects incomplete or unsafe schedules", () => {
    expect(weeklyRecurrence({ frequency: "weekly", weekday: "TH" })).toBeNull();
    expect(weeklyRecurrence({
      frequency: "weekly", weekday: "TH", startDate: "2026-09-24",
      time: "25:00", timezone: "America/Denver",
    })).toBeNull();
  });
});

const dav = vi.hoisted(() => ({davRequest:vi.fn(),listAllTodos:vi.fn(),listTaskLists:vi.fn(),fetchVersionedItem:vi.fn(),putVersionedItem:vi.fn(),putItem:vi.fn()}));
vi.mock("../src/executors/caldav.js", async original => ({...await original<typeof import("../src/executors/caldav.js")>(),...dav}));
describe("fixed task schedule through real handlers", () => {
 let raw:string;
 const update=(args:Record<string,unknown>)=>tasksTools(()=>"2026-10-14").find(t=>t.name==="hwc_tasks_update")!.handler(args);
 beforeEach(()=>{
  vi.clearAllMocks();
  raw=buildVtodo({uid:"chore@test",summary:"Laundry",...fixedRecurrence({frequency:"weekly",startDate:"2026-10-14"})!}).replace("END:VTODO","X-APPLE-TEST:keep\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nEND:VALARM\r\nEND:VTODO");
  dav.listAllTodos.mockImplementation(async()=>({tasks:[parseVtodo(raw,"/test/chore.ics","Family")!],lists:[]}));
  dav.listTaskLists.mockResolvedValue([{href:"/test/",name:"Family"}]);
  dav.fetchVersionedItem.mockImplementation(async()=>({raw,etag:'"v1"'}));
  dav.putVersionedItem.mockImplementation(async(_href,value)=>{raw=value;});
 });
 it("advances once, retains metadata, and rejects a stale second tap",async()=>{
  const result=await update({uid:"chore@test",action:"complete",expectedDue:"2026-10-14"});
  expect(result.status).toBe("ok");expect(result.data).toMatchObject({due:"2026-10-21",recurring:true});
  for(const line of ["DUE;VALUE=DATE:20261021","DTSTART;VALUE=DATE:20261021","STATUS:NEEDS-ACTION","X-APPLE-TEST:keep","BEGIN:VALARM"]) expect(raw).toContain(line);
  expect(dav.putVersionedItem.mock.calls[0][2]).toBe('"v1"');
  expect((await update({uid:"chore@test",action:"complete",expectedDue:"2026-10-14"})).status).toBe("error");
  expect(dav.putVersionedItem).toHaveBeenCalledTimes(1);
 });
 it("does not claim success on a concurrent conflict",async()=>{
  dav.putVersionedItem.mockRejectedValueOnce(new Error("conflict"));
  expect((await update({uid:"chore@test",action:"complete",expectedDue:"2026-10-14"})).status).toBe("error");
  expect(raw).toContain("DUE;VALUE=DATE:20261014");
 });
 it("finishes the final occurrence and removes a schedule",async()=>{
  raw=editVtodo(raw,{RRULE:":FREQ=WEEKLY;UNTIL=20261014"});
  expect((await update({uid:"chore@test",action:"complete",expectedDue:"2026-10-14"})).status).toBe("ok");
  expect(raw).toContain("STATUS:COMPLETED");
  await update({uid:"chore@test",action:"edit",recurrence:null});
  expect(raw).not.toContain("RRULE:");expect(raw).not.toContain("X-HWC-REPEAT:");expect(raw).toContain("X-APPLE-TEST:keep");
 });
 it("creates and converts a date-only task",async()=>{
  const recurrence={frequency:"monthly",startDate:"2026-10-31",until:"2027-12-31"};
  expect((await tasksTools().find(t=>t.name==="hwc_tasks_add")!.handler({summary:"Chore",list:"Family",recurrence})).status).toBe("ok");
  expect(dav.putItem.mock.calls[0][1]).toContain("DTSTART;VALUE=DATE:20261031");
  expect(dav.putItem.mock.calls[0][1]).toContain("X-HWC-REPEAT:fixed-v1");
  await update({uid:"chore@test",action:"edit",recurrence});
  expect(raw).toContain("RRULE:FREQ=MONTHLY;UNTIL=20271231");expect(raw).toContain("DUE;VALUE=DATE:20261031");
 });
 it("preserves a foreign timed schedule on ordinary edits",async()=>{
  raw=buildVtodo({uid:"chore@test",summary:"Timed",due:"2026-10-14",...weeklyRecurrence({frequency:"weekly",weekday:"WE",startDate:"2026-10-14",time:"09:00",timezone:"America/Denver"})!});
  await update({uid:"chore@test",action:"edit",summary:"Changed"});
  expect(raw).toContain("RRULE:FREQ=WEEKLY;BYDAY=WE");expect(raw).toContain("DTSTART;TZID=America/Denver:20261014T090000");
 });
});
it("keeps fixed dates, skips invalid month/leap dates, catches up, and honors until",()=>{
 expect(nextScheduledDate("2026-01-31","monthly","2026-01-31")).toBe("2026-03-31");
 expect(nextScheduledDate("2024-02-29","yearly","2024-02-29")).toBe("2028-02-29");
 expect(nextScheduledDate("2026-09-30","weekly","2026-10-14")).toBe("2026-10-21");
 expect(nextScheduledDate("2026-10-14","daily","2026-10-14","2026-10-14")).toBeNull();
 expect(fixedRecurrence({frequency:"daily",startDate:"2026-02-30"})).toBeNull();
});

describe("reviewed meal conditional protocol",()=>{
 const config={groceries:{href:"/eric/groceries/",name:"Groceries"},meals:{href:"/eric/meals/",name:"Meals"}};
 const raw="BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VTODO\r\nUID:meal-grocery-test\r\nX-HWC-MEAL-SCHEMA:1\r\nX-HWC-MEAL-OPERATION:op\r\nSUMMARY:Milk\r\nEND:VTODO\r\nEND:VCALENDAR\r\n";
 const call=(args:Record<string,unknown>)=>mealTools(config)[0].handler({schemaVersion:1,collection:"groceries",uid:"meal-grocery-test",...args});
 beforeEach(()=>{vi.clearAllMocks();dav.davRequest.mockImplementation(async(method)=>method==="PROPFIND"?{status:207,body:"<displayname>Groceries</displayname>"}:method==="GET"?{status:200,body:raw,etag:'"v1"'}:{status:201,body:""});});
 it("is absent unless both collections are configured",()=>expect(mealTools({})).toEqual([]));
 it("creates conditionally and returns exact readback identity",async()=>{
  expect((await call({action:"create",raw})).data).toMatchObject({code:"OK",item:{uid:"meal-grocery-test",etag:'"v1"'}});
  expect(dav.davRequest.mock.calls[1]).toMatchObject(["PUT","/eric/groceries/meal-grocery-test.ics",{headers:{"If-None-Match":"*"}}]);
 });
 it("refuses unversioned changes and manual item identities",async()=>{
  expect((await call({action:"delete"})).status).toBe("error");expect((await call({action:"create",uid:"manual",raw})).status).toBe("error");expect(dav.davRequest).not.toHaveBeenCalled();
 });
 it("preserves conflict without an unconditional retry",async()=>{
  dav.davRequest.mockImplementation(async(method)=>method==="PROPFIND"?{status:207,body:"<displayname>Groceries</displayname>"}:{status:412,body:""});
  expect((await call({action:"update",raw,expectedEtag:'"old"'})).data).toMatchObject({code:"REMOTE_CONFLICT",httpStatus:412});
  expect(dav.davRequest).toHaveBeenCalledTimes(2);expect(dav.davRequest.mock.calls[1][2].headers["If-Match"]).toBe('"old"');
 });
 it("refuses wrong collection name before a mutation",async()=>{
  dav.davRequest.mockResolvedValue({status:207,body:"<displayname>Other</displayname>"});
  expect((await call({action:"create",raw})).data).toMatchObject({code:"COLLECTION_UNAVAILABLE"});expect(dav.davRequest).toHaveBeenCalledTimes(1);
 });
});
