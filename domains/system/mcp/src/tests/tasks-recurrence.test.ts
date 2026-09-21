import { describe, expect, it } from "vitest";
import { buildVtodo } from "../src/executors/caldav.js";
import { weeklyRecurrence } from "../src/tools/tasks.js";

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
