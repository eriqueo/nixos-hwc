#!/usr/bin/env python3
"""
email-to-khal: Import calendar events from emails into khal.

Workflow:
  ICS attachment found  → preview details → confirm → import
  No ICS attachment     → parse body for date/time/details → open $EDITOR → import

Designed for aerc's :pipe command. Reads email from stdin,
interacts with user via /dev/tty.
"""

import sys
import re
import tempfile
import subprocess
import os
import uuid
from datetime import datetime, timedelta, timezone
from email.parser import BytesParser
from email.header import decode_header

TIMEZONE_ICAL = {
    "eastern": "US/Eastern", "et": "US/Eastern",
    "est": "US/Eastern",     "edt": "US/Eastern",
    "central": "US/Central", "ct": "US/Central",
    "cst": "US/Central",     "cdt": "US/Central",
    "mountain": "US/Mountain", "mt": "US/Mountain",
    "mst": "US/Mountain",     "mdt": "US/Mountain",
    "pacific": "US/Pacific", "pt": "US/Pacific",
    "pst": "US/Pacific",     "pdt": "US/Pacific",
    "utc": "UTC",            "gmt": "UTC",
}


# ── helpers ──────────────────────────────────────────────────────────

def tty_input(prompt: str) -> str:
    """Read a line from /dev/tty (works even when stdin is a pipe)."""
    with open("/dev/tty", "r") as tty:
        sys.stdout.write(prompt)
        sys.stdout.flush()
        return tty.readline().strip()


def extract_body(msg) -> str:
    parts = []
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                payload = part.get_payload(decode=True)
                if payload:
                    parts.append(payload.decode("utf-8", errors="ignore"))
    else:
        payload = msg.get_payload(decode=True)
        if payload:
            parts.append(payload.decode("utf-8", errors="ignore"))
    return "\n".join(parts)


def extract_html_text(msg) -> str:
    """Strip HTML tags to get readable text (for date parsing from HTML emails)."""
    for part in msg.walk():
        if part.get_content_type() == "text/html":
            payload = part.get_payload(decode=True)
            if payload:
                html = payload.decode("utf-8", errors="ignore")
                # Strip tags, keep text content
                text = re.sub(r"<style[^>]*>.*?</style>", "", html, flags=re.DOTALL | re.IGNORECASE)
                text = re.sub(r"<script[^>]*>.*?</script>", "", text, flags=re.DOTALL | re.IGNORECASE)
                text = re.sub(r"<[^>]+>", " ", text)
                text = re.sub(r"&nbsp;", " ", text)
                text = re.sub(r"&amp;", "&", text)
                text = re.sub(r"&[a-z]+;", " ", text)
                text = re.sub(r"\s+", " ", text)
                return text
    return ""


def extract_html_links(msg) -> list[str]:
    """Pull href URLs from HTML parts (catches links hidden behind 'Click Here')."""
    urls = []
    for part in msg.walk():
        if part.get_content_type() == "text/html":
            payload = part.get_payload(decode=True)
            if payload:
                html = payload.decode("utf-8", errors="ignore")
                urls.extend(re.findall(r'href=["\']?(https?://[^"\'>\s]+)', html, re.IGNORECASE))
    return urls


def extract_ics_parts(msg) -> list[bytes]:
    results = []
    for part in msg.walk():
        if part.get_content_type() == "text/calendar":
            payload = part.get_payload(decode=True)
            if payload:
                results.append(payload)
    return results


# ── date / field parsing ─────────────────────────────────────────────

def parse_structured_fields(body: str, msg=None) -> dict:
    """Extract structured key: value fields from email body."""
    fields = {}

    m = re.search(r"(?:^|\n)\s*Date:\s*(.+)", body, re.IGNORECASE)
    if m:
        fields["date_raw"] = m.group(1).strip()

    m = re.search(r"(?:^|\n)\s*Time:\s*(.+)", body, re.IGNORECASE)
    if m:
        fields["time_raw"] = m.group(1).strip()

    # Link: try plaintext first, then fall back to HTML hrefs
    m = re.search(
        r"(?:^|\n)\s*(?:Link|URL|Join|Meeting\s*Link)[^:]*:\s*(https?://\S+)",
        body, re.IGNORECASE,
    )
    if m:
        fields["link"] = m.group(1).strip()
    elif msg:
        # Extract URLs from HTML parts (catches "Click Here" hyperlinks)
        html_urls = extract_html_links(msg)
        # Filter for meeting-like URLs, skip unsubscribe/tracking links
        meeting_urls = [
            u for u in html_urls
            if re.search(r"zoom|meet|teams|webinar|gotomeeting|whereby", u, re.IGNORECASE)
        ]
        if meeting_urls:
            fields["link"] = meeting_urls[0]
        elif html_urls:
            # Skip common junk URLs
            useful = [
                u for u in html_urls
                if not re.search(r"unsubscribe|manage.*subscription|tracking|click\.|list-manage", u, re.IGNORECASE)
            ]
            if useful:
                fields["link"] = useful[0]

    m = re.search(r"(?:^|\n)\s*Password:\s*(\S+)", body, re.IGNORECASE)
    if m:
        fields["password"] = m.group(1).strip()

    m = re.search(
        r"(?:^|\n)\s*(?:Location|Where|Venue):\s*(.+)", body, re.IGNORECASE
    )
    if m:
        fields["location"] = m.group(1).strip()

    # Duration: "90-minute", "1 hour", "2h", "30 min"
    m = re.search(r"(\d+)\s*[-\s]?\s*(minute|min|hour|hr|h)\b", body, re.IGNORECASE)
    if m:
        val = int(m.group(1))
        unit = m.group(2).lower()
        fields["duration_min"] = val * 60 if unit in ("hour", "hr", "h") else val

    return fields


def detect_timezone(text: str) -> str | None:
    """Return IANA timezone name if a known abbreviation appears in text."""
    for abbr, iana in TIMEZONE_ICAL.items():
        if re.search(rf"\b{re.escape(abbr)}\b", text, re.IGNORECASE):
            return iana
    return None


def parse_datetime(fields: dict, body: str):
    """
    Returns (datetime | None, iana_tz | None).
    Tries structured Date:/Time: fields first, then scans the body.
    """
    import dateparser

    date_raw = fields.get("date_raw", "")
    time_raw = fields.get("time_raw", "")

    # Detect timezone from time field or body
    tz = detect_timezone(time_raw) or detect_timezone(body)

    # Strip timezone words from time string so dateparser doesn't choke
    clean_time = time_raw
    for abbr in TIMEZONE_ICAL:
        clean_time = re.sub(rf"\b{re.escape(abbr)}\b", "", clean_time, flags=re.IGNORECASE)
    clean_time = clean_time.strip()

    # Try structured fields
    if date_raw:
        combined = f"{date_raw} {clean_time}".strip()
        dt = dateparser.parse(combined, settings={
            "PREFER_DATES_FROM": "future",
            "RETURN_AS_TIMEZONE_AWARE": False,
        })
        if dt:
            return dt, tz

    # Fallback: scan body for date/time phrases
    # Time part: "4 PM", "4:00 PM", "16:00"
    _time = r"\d{1,2}(?::\d{2})?\s*(?:am|pm|AM|PM)"
    phrases = [
        # "Tomorrow at 4 PM", "Tomorrow, Tuesday March 24 at 4 PM"
        rf"(tomorrow|today|tonight).*?({_time})",
        # "Tuesday March 24 at 4 PM", "March 24 at 4 PM", "March 24, 2026 at 4 PM"
        rf"((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\w*,?\s+)?(\w+\s+\d{{1,2}}(?:st|nd|rd|th)?,?\s*\d{{0,4}})\s*(?:at\s+)?({_time})",
        # "4 PM EDT" near a date-like context
        rf"({_time})\s*(?:EDT|EST|CDT|CST|MDT|MST|PDT|PST|ET|CT|MT|PT)",
        # Numeric dates
        r"(\d{1,2}/\d{1,2}(?:/\d{2,4})?)\s+(\d{1,2}:\d{2})",
        r"(\d{4}-\d{2}-\d{2})\s*[T ]?(\d{2}:\d{2})",
    ]
    now = datetime.now()
    for pat in phrases:
        for m in re.finditer(pat, body, re.IGNORECASE):
            text = " ".join(g for g in m.groups() if g)
            dt = dateparser.parse(text, settings={
                "PREFER_DATES_FROM": "future",
                "RETURN_AS_TIMEZONE_AWARE": False,
            })
            if dt and now - timedelta(hours=12) < dt < now + timedelta(days=365):
                return dt, tz

    return None, tz


# ── ICS generation ───────────────────────────────────────────────────

def ics_escape(s: str) -> str:
    return (
        s.replace("\\", "\\\\")
        .replace("\n", "\\n")
        .replace(",", "\\,")
        .replace(";", "\\;")
    )


def make_ics(
    summary: str,
    dtstart: datetime,
    dtend: datetime,
    description: str = "",
    location: str = "",
    tz_name: str | None = None,
) -> bytes:
    uid = str(uuid.uuid4())
    stamp = datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    fmt = "%Y%m%dT%H%M%S"

    if tz_name:
        start_line = f"DTSTART;TZID={tz_name}:{dtstart.strftime(fmt)}"
        end_line = f"DTEND;TZID={tz_name}:{dtend.strftime(fmt)}"
    else:
        start_line = f"DTSTART:{dtstart.strftime(fmt)}"
        end_line = f"DTEND:{dtend.strftime(fmt)}"

    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//email-to-khal//EN",
        "BEGIN:VEVENT",
        f"UID:{uid}",
        f"DTSTAMP:{stamp}",
        start_line,
        end_line,
        f"SUMMARY:{ics_escape(summary)}",
    ]
    if description:
        lines.append(f"DESCRIPTION:{ics_escape(description)}")
    if location:
        lines.append(f"LOCATION:{ics_escape(location)}")
    lines += ["END:VEVENT", "END:VCALENDAR"]
    return "\r\n".join(lines).encode("utf-8")


def import_ics_file(ics_data: bytes, calendar: str = "") -> bool:
    with tempfile.NamedTemporaryFile(
        mode="wb", suffix=".ics", delete=False
    ) as f:
        f.write(ics_data)
        path = f.name
    try:
        cmd = ["khal", "import", "--batch"]
        if calendar:
            cmd.extend(["-a", calendar])
        cmd.append(path)
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode == 0:
            return True
        print(f"khal error: {result.stderr.strip()}")
        return False
    finally:
        os.unlink(path)


# ── editor review ────────────────────────────────────────────────────

TEMPLATE = """\
# ┌──────────────────────────────────────────┐
# │  Review event — save & close to import   │
# │  Clear Title to cancel                   │
# └──────────────────────────────────────────┘

Title:    {title}
Date:     {date}
Time:     {time}
Duration: {duration}
Timezone: {timezone}
Location: {location}
Calendar: {calendar}

# ── Description (free text below this line) ──
{description}

# ── Original email (for reference — copy what you need) ──
{email_body}
"""


def editor_review(event: dict, email_body: str = "") -> dict | None:
    """Open $EDITOR with event details. Returns parsed dict or None if cancelled."""
    # Comment out each line of the email body so it doesn't get parsed as fields
    commented_body = "\n".join(f"# {line}" for line in email_body.splitlines())
    content = TEMPLATE.format(**event, email_body=commented_body)

    fd, path = tempfile.mkstemp(suffix=".event", prefix="khal-")
    with os.fdopen(fd, "w") as f:
        f.write(content)

    # Record mtime before editor opens
    mtime_before = os.path.getmtime(path)

    editor = os.environ.get("EDITOR", os.environ.get("VISUAL", "vi"))
    try:
        # Editor reads/writes /dev/tty, works in aerc :pipe context
        subprocess.run([editor, path], check=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        print(f"Could not open editor ({editor}): {e}")
        os.unlink(path)
        return None

    # If file wasn't modified, treat as cancel (:q! in vim)
    mtime_after = os.path.getmtime(path)
    if mtime_after == mtime_before:
        os.unlink(path)
        return None

    with open(path) as f:
        edited = f.read()
    os.unlink(path)

    return _parse_template(edited)


def _parse_template(text: str) -> dict | None:
    result = {}
    desc_lines = []
    in_desc = False

    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("#"):
            if "Description" in stripped:
                in_desc = True
            continue
        if in_desc:
            desc_lines.append(line)
            continue
        m = re.match(r"^(\w[\w\s]*?):\s*(.*)", line)
        if m:
            key = m.group(1).strip().lower()
            result[key] = m.group(2).strip()

    result["description"] = "\n".join(desc_lines).strip()

    if not result.get("title"):
        return None
    return result


# ── main flows ───────────────────────────────────────────────────────

def handle_ics_attachment(ics_parts: list[bytes]):
    """Show ICS summary and confirm before importing."""
    print(f"\n  Found {len(ics_parts)} calendar invite(s) attached.\n")

    # Quick parse of the ICS to show summary
    for i, data in enumerate(ics_parts):
        text = data.decode("utf-8", errors="ignore")
        summary = _ics_field(text, "SUMMARY") or "(no title)"
        dtstart = _ics_field(text, "DTSTART") or "?"
        print(f"  [{i+1}] {summary}")
        print(f"      {dtstart}")
    print()

    answer = tty_input("  Import? [Y/n] ").lower()
    if answer and answer != "y":
        print("  Cancelled.")
        return

    imported = 0
    for data in ics_parts:
        if import_ics_file(data):
            imported += 1
    print(f"\n  Imported {imported} event(s).")


def _ics_field(ics_text: str, field: str) -> str | None:
    """Extract a field value from raw ICS text."""
    m = re.search(rf"^{field}[^:]*:(.+)$", ics_text, re.MULTILINE)
    return m.group(1).strip() if m else None


def decode_mime_header(raw: str | None) -> str:
    """Decode MIME-encoded headers like =?utf-8?q?...?= into plain text."""
    if not raw:
        return "Untitled Event"
    parts = decode_header(raw)
    decoded = []
    for data, charset in parts:
        if isinstance(data, bytes):
            decoded.append(data.decode(charset or "utf-8", errors="ignore"))
        else:
            decoded.append(data)
    return " ".join(decoded)


def handle_body_parse(msg):
    """Parse email body, open editor for review, then import."""
    subject = decode_mime_header(msg["subject"])
    body = extract_body(msg)
    html_text = extract_html_text(msg)

    # Try plaintext first, fall back to HTML-derived text
    combined_body = body if body.strip() else html_text
    fields = parse_structured_fields(combined_body, msg)

    dt, tz_name = parse_datetime(fields, combined_body)
    # If plaintext had no dates, try HTML text too
    if not dt and html_text and combined_body != html_text:
        fields_html = parse_structured_fields(html_text, msg)
        fields.update({k: v for k, v in fields_html.items() if k not in fields})
        dt, tz_name = parse_datetime(fields, html_text)
    duration_min = fields.get("duration_min", 60)

    # Build description from extracted details
    desc_parts = []
    sender = msg.get("from", "")
    if sender:
        desc_parts.append(f"From: {sender}")
    if fields.get("password"):
        desc_parts.append(f"Password: {fields['password']}")
    if fields.get("link"):
        desc_parts.append(f"Link: {fields['link']}")

    location = fields.get("location", "")
    if not location and fields.get("link"):
        location = fields["link"]

    event = {
        "title": subject,
        "date": dt.strftime("%Y-%m-%d") if dt else "",
        "time": dt.strftime("%H:%M") if dt else "",
        "duration": f"{duration_min}m",
        "timezone": tz_name or "local",
        "location": location,
        "calendar": "",
        "description": "\n".join(desc_parts),
    }

    if not dt:
        print("\n  Could not auto-detect date/time — fill in manually.\n")
    else:
        print(f"\n  Detected: {event['date']} {event['time']} ({event['timezone']})")
        print(f"  Title:    {event['title']}")
        print(f"  Duration: {event['duration']}\n")

    print("  Opening editor for review...\n")

    # Include HTML URLs in the reference body so user can copy them
    html_urls = extract_html_links(msg)
    if html_urls:
        body += "\n\n── URLs found in email ──\n" + "\n".join(html_urls)

    edited = editor_review(event, email_body=body)
    if not edited:
        print("  Cancelled (title was empty).")
        return

    # Parse the edited values back into a datetime
    import dateparser

    dt_str = f"{edited.get('date', '')} {edited.get('time', '')}".strip()
    dt = dateparser.parse(dt_str, settings={"RETURN_AS_TIMEZONE_AWARE": False})
    if not dt:
        print(f"  Could not parse date/time: {dt_str!r}")
        return

    # Parse duration
    dur_str = edited.get("duration", "60m")
    dur_m = re.match(r"(\d+)\s*(m|min|h|hr|hour)?", dur_str, re.IGNORECASE)
    if dur_m:
        val = int(dur_m.group(1))
        unit = (dur_m.group(2) or "m").lower()
        delta = timedelta(hours=val) if unit.startswith("h") else timedelta(minutes=val)
    else:
        delta = timedelta(hours=1)

    # Resolve timezone
    tz_str = edited.get("timezone", "local")
    tz_ical = TIMEZONE_ICAL.get(tz_str.lower()) if tz_str != "local" else None
    # If it's already an IANA name (e.g. US/Eastern), use as-is
    if not tz_ical and "/" in tz_str:
        tz_ical = tz_str

    ics_data = make_ics(
        summary=edited["title"],
        dtstart=dt,
        dtend=dt + delta,
        description=edited.get("description", ""),
        location=edited.get("location", ""),
        tz_name=tz_ical,
    )

    calendar = edited.get("calendar", "")
    if import_ics_file(ics_data, calendar):
        print(f"\n  Event created:")
        print(f"    {edited['title']}")
        print(f"    {dt.strftime('%Y-%m-%d %H:%M')} ({dur_str})")
        if edited.get("location"):
            print(f"    {edited['location']}")
    else:
        print("\n  Failed to import event.")
        sys.exit(1)


def main():
    raw = sys.stdin.buffer.read()
    msg = BytesParser().parsebytes(raw)

    ics_parts = extract_ics_parts(msg)
    if ics_parts:
        handle_ics_attachment(ics_parts)
    else:
        handle_body_parse(msg)


if __name__ == "__main__":
    main()
