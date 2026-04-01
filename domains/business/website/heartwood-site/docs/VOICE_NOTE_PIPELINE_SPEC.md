# Voice Note → Job Costing Pipeline

## The Problem (in Eric's words)

Recording hours and cost codes on the job site is high friction. The data is valuable for calibrating the estimator, but the input method kills compliance. Past attempts at disciplined tracking have failed because the tools require too many steps: open app → find job → find cost code → enter hours → save. By the time you're done working, the last thing you want is data entry.

## The Insight

Eric already describes his day naturally — to clients (daily text), to himself (mental recap), while driving home. That natural description contains all the data needed for job costing. The system should extract it, not require manual entry.

## The Flow

```
Eric talks (30-60 sec while driving)
  → Granola / voice memo transcribes to text
    → iOS Shortcut sends text to n8n webhook
      → Claude extracts: job, hours by trade, materials, conditions, notes
        → JT: create time entries + daily log
        → Postgres: structured job costing record
        → Slack: confirmation with extracted data
```

## Step 1: iOS Shortcut

Eric already has a Granola shortcut. The addition is an automation that:

1. Triggers a reminder notification at end of each work day (e.g., 4:30 PM on weekdays, or tied to leaving a geofence around active job site)
2. Opens Granola for a voice recording
3. When the recording is complete, the transcribed text is sent via HTTP POST to an n8n webhook

The iOS Shortcut actions:
```
1. Get clipboard / share sheet text (the Granola transcript)
2. POST to https://hwc.ocelot-wahoo.ts.net/webhook/daily-log
   Headers: x-api-key: {your key}
   Body: { "transcript": "{transcript text}", "date": "{current date}", "source": "granola" }
3. Show notification: "Daily log submitted ✓"
```

If Granola can't POST directly, the shortcut can receive the transcript via share sheet and handle the POST.

## Step 2: n8n Workflow #12 — Daily Voice Log Processor

### Trigger
POST `/webhook/daily-log`

### Payload from iOS
```json
{
  "transcript": "Margulies kids bath day 3. Did about 4 hours of shower tile install today, spent maybe an hour and a half doing niche work on both niches. Used about half a bag of Schluter thinset and finished the second row of Sartoria t-brick. Subfloor in the corner by the toilet looked a little soft, I'm going to keep an eye on it. Also picked up more copper fittings from Kenyon, about 30 bucks. Tomorrow I'll finish the shower tile and start the floor.",
  "date": "2026-03-20",
  "source": "granola"
}
```

### Node 1: Validate
- Check transcript exists and is non-empty
- Check date is valid

### Node 2: Claude Extraction
Call the Anthropic API with a structured extraction prompt.

**System prompt:**
```
You are a construction job costing assistant for Heartwood Craft, a remodeling contractor in Bozeman, Montana.

You will receive a voice memo transcript from the contractor describing their work day. Extract structured data from the natural language.

ACTIVE JOBS (match the transcript to one of these):
{dynamically injected from JT — list of open jobs with IDs}

TRADE CATEGORIES (map work descriptions to these):
- Demo (demolition, removal, tear-out)
- Framing (blocking, furring, framing, structural)
- Plumbing (pipes, valves, drains, fixtures, toilet, faucet)
- Electrical (wiring, outlets, switches, lighting, fan)
- Tile (tile install, backer board, grout, thinset, niche tile, waterproofing)
- Drywall (hanging, mudding, taping, sanding)
- Painting (prep, prime, paint, caulking, touch-up)
- Finish Carpentry (trim, vanity, accessories, hardware, doors)
- Admin (planning, measuring, ordering, pickup, client meeting, cleanup)

COST CODES (for JT mapping):
- Demo → 0200 Demolition (22Nm3uGRAMmJ)
- Framing → 0600 Framing (22Nm3uGRAMmN)
- Plumbing → 1100 Plumbing (22Nm3uGRAMmT)
- Electrical → 1000 Electrical (22Nm3uGRAMmS)
- Tile → 1800 Tiling (22Nm3uGRAMma)
- Drywall → 1400 Drywall (22Nm3uGRAMmW)
- Painting → 2300 Painting (22Nm3uGRAMmf)
- Finish Carpentry → 1900 Cabinetry (22Nm3uGRAMmb)
- Admin → 0100 Planning (22Nm3uGRAMmH)

Respond ONLY with valid JSON. No preamble, no markdown.

Schema:
{
  "job_match": {
    "job_id": "JT job ID or null if unclear",
    "job_name": "matched job name",
    "confidence": "high | medium | low"
  },
  "date": "YYYY-MM-DD",
  "time_entries": [
    {
      "trade": "Tile",
      "cost_code_id": "22Nm3uGRAMma",
      "hours": 4,
      "description": "Shower tile installation — second row of Sartoria t-brick"
    },
    {
      "trade": "Tile",
      "cost_code_id": "22Nm3uGRAMma",
      "hours": 1.5,
      "description": "Niche tile work — both niches"
    }
  ],
  "total_hours": 5.5,
  "materials_purchased": [
    {
      "item": "Copper fittings",
      "cost": 30,
      "supplier": "Kenyon Noble"
    }
  ],
  "conditions_noted": [
    "Subfloor soft in corner by toilet — monitoring"
  ],
  "tomorrow_plan": "Finish shower tile, start floor tile",
  "daily_log_summary": "Day 3: 4 hrs shower tile (Sartoria t-brick row 2), 1.5 hrs niche work (both niches). Used half bag Schluter thinset. Picked up copper fittings from Kenyon ($30). Soft subfloor noted near toilet — monitoring. Tomorrow: finish shower tile, start floor."
}
```

**User prompt:**
```
Transcript from {date}:
"{transcript}"
```

### Node 3: Parse Claude Response
- JSON.parse the response
- Validate required fields exist
- If job_match.confidence is "low", flag for manual review (don't auto-push)

### Node 4: Branch — Confidence Check
- **High/Medium confidence:** proceed to push
- **Low confidence:** send Slack message asking Eric to confirm the job, with buttons or a reply mechanism

### Node 5a: Push Time Entries to JT
For each entry in `time_entries`, create a JT time entry:

```
POST to JT API: createTimeEntry
- jobId: job_match.job_id
- userId: 22Nm3uFeRB7s (Eric)
- date: extracted date
- hours: entry.hours
- costCodeId: entry.cost_code_id
- description: entry.description
```

### Node 5b: Push Daily Log to JT
Create a JT daily log entry:

```
POST to JT API: createDailyLog
- jobId: job_match.job_id
- date: extracted date
- notes: daily_log_summary
```

### Node 5c: Archive to Postgres
```sql
INSERT INTO daily_logs (
  job_id, job_name, date, total_hours,
  time_entries, materials, conditions,
  tomorrow_plan, raw_transcript, source
) VALUES (
  $job_id, $job_name, $date, $total_hours,
  $time_entries::jsonb, $materials::jsonb, $conditions::jsonb,
  $tomorrow_plan, $raw_transcript, 'granola'
);
```

### Node 5d: Notify Slack
```
📋 *Daily Log Processed*

*Job:* Margulies Kids Bathroom (#280)
*Date:* March 20, 2026
*Total hours:* 5.5

⏱ *Time entries:*
• Tile — 4 hrs (shower tile install, Sartoria t-brick row 2)
• Tile — 1.5 hrs (niche work, both niches)

🛒 *Materials purchased:*
• Copper fittings — $30 (Kenyon Noble)

⚠️ *Conditions noted:*
• Subfloor soft in corner by toilet — monitoring

📅 *Tomorrow:* Finish shower tile, start floor

_Extracted from Granola voice note_
```

### Node 6: Return Success
```json
{
  "success": true,
  "job": "Margulies Kids Bathroom (#280)",
  "hours_logged": 5.5,
  "entries": 2,
  "materials": 1
}
```

## Step 3: Postgres Schema

```sql
CREATE TABLE daily_logs (
  id SERIAL PRIMARY KEY,
  job_id VARCHAR(50),
  job_name VARCHAR(255),
  date DATE NOT NULL,
  total_hours DECIMAL(4,1),
  time_entries JSONB,        -- array of {trade, hours, description, cost_code_id}
  materials JSONB,            -- array of {item, cost, supplier}
  conditions JSONB,           -- array of strings
  tomorrow_plan TEXT,
  daily_log_summary TEXT,
  raw_transcript TEXT,
  source VARCHAR(50) DEFAULT 'granola',
  jt_pushed BOOLEAN DEFAULT FALSE,
  jt_time_entry_ids JSONB,   -- array of created JT time entry IDs
  jt_daily_log_id VARCHAR(50),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_daily_logs_job ON daily_logs(job_id);
CREATE INDEX idx_daily_logs_date ON daily_logs(date);
```

## Step 4: BeaverDB Visualization

Once data is in Postgres, BeaverDB can show:

**Hours by trade per job:**
```sql
SELECT job_name,
  entry->>'trade' as trade,
  SUM((entry->>'hours')::decimal) as total_hours
FROM daily_logs,
  jsonb_array_elements(time_entries) as entry
GROUP BY job_name, entry->>'trade'
ORDER BY job_name, total_hours DESC;
```

**Estimated vs actual hours (the calibration query):**
```sql
-- Join with estimates table to compare
SELECT
  dl.job_name,
  entry->>'trade' as trade,
  SUM((entry->>'hours')::decimal) as actual_hours,
  e.payload->>'predicted_hours' as estimated_hours  -- from estimate archive
FROM daily_logs dl
JOIN estimates e ON dl.job_id = e.job_id
CROSS JOIN jsonb_array_elements(dl.time_entries) as entry
GROUP BY dl.job_name, entry->>'trade', e.payload->>'predicted_hours';
```

**Material spend tracking:**
```sql
SELECT job_name, date,
  mat->>'item' as material,
  (mat->>'cost')::decimal as cost,
  mat->>'supplier' as supplier
FROM daily_logs,
  jsonb_array_elements(materials) as mat
WHERE materials IS NOT NULL
ORDER BY date DESC;
```

## How This Fits Into the Bigger System

```
Voice note (field input)
  → n8n extracts structured data
    → JT time entries (hours by trade per job)
    → JT daily log (narrative for client communication)
    → Postgres daily_logs table (structured archive)
      → BeaverDB dashboard (visualization)
      → Job costing queries (actual vs estimated)
        → Catalog calibration (update production rates)
          → Better estimates on future jobs
```

The voice note also produces the daily client update text:
- The `daily_log_summary` field is a clean, client-friendly version
- Eric can copy it directly for the daily progress text to the client
- One input → multiple outputs (job costing + client comms + JT records)

## The Claude Extraction Prompt — Key Design Decisions

1. **Active jobs list is injected dynamically.** The n8n workflow fetches open JT jobs before calling Claude, so the prompt always has current job names to match against. Eric usually only has 1-2 active jobs, so matching is straightforward.

2. **Trade categories are simplified to 9.** Not the 23 JT cost codes — just the 9 work phases Eric actually thinks in. The mapping to JT cost code IDs is hardcoded in the prompt so Claude returns the right ID directly.

3. **Hours are rounded to nearest 0.5.** The prompt should specify this. Eric won't know if he spent 3.73 hours on tile — but he knows it was "about 3 and a half hours."

4. **Materials are captured opportunistically.** If Eric mentions picking something up or using supplies, great. If not, that's fine — material costs come from QB receipts primarily.

5. **Conditions and tomorrow's plan are bonus data.** They make the daily log richer and help Eric remember what happened when he's doing job costing review at the end of the project.

6. **Low-confidence job matching doesn't auto-push.** If the transcript doesn't clearly identify which job, the system asks via Slack instead of guessing wrong.

## Daily Notification Setup

iOS Automation (in Shortcuts app):
- **Trigger:** Time of Day → 4:30 PM, Weekdays only
- **Condition:** (optional) Check if Eric's location is near an active job site
- **Action:** Show notification → "Time to log your day. Tap to record."
- **Tap action:** Open Granola → record → on completion, run the webhook shortcut

Alternative: a simpler approach is just a recurring reminder in the Reminders app at 4:30 PM that says "Record daily voice log" — no automation needed, just the habit of doing it and then sharing the transcript to the webhook shortcut.

## What This Solves

| Old friction | New approach |
|---|---|
| Open JT, find job, find cost code, enter hours | Talk for 30 seconds while driving |
| Remember what you did 3 days ago | Record same-day while it's fresh |
| Pick from 23 cost codes | Say "tile work" and AI maps it |
| Manual daily log entry in JT | Auto-generated from your voice |
| Client daily text is separate from logging | Same input produces both |
| Material tracking requires QB receipt entry | Mentioned in voice → captured |
| Job costing review at end of project | Data accumulates automatically |

## Implementation Order

1. Create the Postgres `daily_logs` table
2. Build n8n workflow #12 with the Claude extraction node
3. Test with manual curl (paste a sample transcript)
4. Build the iOS Shortcut (Granola → webhook POST)
5. Set up the 4:30 PM daily reminder
6. Run it for 1 week on a real job
7. Review the extracted data — calibrate the Claude prompt if needed
8. Build BeaverDB views for the job costing queries
9. After 1 completed job: compare Postgres actuals to estimator predicted hours
