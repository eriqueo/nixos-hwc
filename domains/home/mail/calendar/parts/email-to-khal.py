#!/usr/bin/env python3
"""
Pipe emails from aerc to import into khal.
1. Extract text/calendar MIME part if present (standard invites)
2. Fall back to date-parsing from body text (best-effort)
"""

import sys
import re
import tempfile
import subprocess
import os
from datetime import datetime, timedelta
from email.parser import BytesParser


def import_ics(ics_data: bytes) -> bool:
    """Write ICS data to temp file and import via khal."""
    with tempfile.NamedTemporaryFile(mode='wb', suffix='.ics', delete=False) as f:
        f.write(ics_data)
        path = f.name
    try:
        result = subprocess.run(
            ['khal', 'import', '--batch', path],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"Imported event from ICS attachment")
            if result.stdout.strip():
                print(result.stdout.strip())
            return True
        else:
            print(f"khal import failed: {result.stderr.strip()}")
            return False
    finally:
        os.unlink(path)


def extract_ics_parts(msg):
    """Yield all text/calendar MIME parts as bytes."""
    for part in msg.walk():
        ct = part.get_content_type()
        if ct == 'text/calendar':
            payload = part.get_payload(decode=True)
            if payload:
                yield payload


def extract_body(msg) -> str:
    """Get plain text body from message."""
    if msg.is_multipart():
        parts = []
        for part in msg.walk():
            if part.get_content_type() == 'text/plain':
                payload = part.get_payload(decode=True)
                if payload:
                    parts.append(payload.decode('utf-8', errors='ignore'))
        return '\n'.join(parts)
    else:
        payload = msg.get_payload(decode=True)
        return payload.decode('utf-8', errors='ignore') if payload else ''


def find_best_date(body: str):
    """Find the best future date/time in email body using dateparser."""
    import dateparser

    patterns = [
        r'(?:meeting|call|scheduled|appointment).*?(?:(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),?\s*)?(\w+\s+\d+(?:st|nd|rd|th)?).*?(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm))?',
        r'(\d{1,2}:\d{2}\s*(?:AM|PM|am|pm))?\s*(?:on\s*)?(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec).*?\d{1,2}',
        r'(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday).*?(\d{1,2}(?::\d{2})?\s*(?:am|pm|AM|PM))',
        r'\b(\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?|\d{4}-\d{2}-\d{2})\s*.*?(\d{1,2}:\d{2})',
    ]

    candidates = []
    for pattern in patterns:
        candidates.extend(re.findall(pattern, body, re.IGNORECASE | re.DOTALL))

    now = datetime.now()
    for cand in candidates[:8]:
        text = ' '.join(str(x).strip() for x in cand if x)
        parsed = dateparser.parse(text, settings={
            'PREFER_DATES_FROM': 'future',
            'RETURN_AS_TIMEZONE_AWARE': False
        })
        if parsed and now < parsed < now + timedelta(days=90):
            return parsed
    return None


def fallback_parse(msg):
    """Best-effort: parse dates from body text, create ICS, import."""
    from ics import Event, Calendar

    now = datetime.now()
    subject = msg['subject'] or 'Untitled Meeting'
    body = extract_body(msg)

    dt = find_best_date(body)
    if not dt:
        dt = now + timedelta(days=1)
        dt = dt.replace(hour=9, minute=0, second=0, microsecond=0)
        print(f"No date found, defaulting to tomorrow 9 AM: {dt.strftime('%Y-%m-%d %H:%M')}")

    e = Event()
    e.name = subject
    e.begin = dt
    e.end = dt + timedelta(hours=1)

    # Try to extract a description / meeting link
    call_match = re.search(
        r'(call details|dial-in|join|zoom|teams|meet).*?([^\n\r]{10,300})',
        body, re.IGNORECASE | re.DOTALL
    )
    e.description = call_match.group(2).strip()[:500] if call_match else body[:300]

    loc = re.search(r'(https?://[^\s\n\r]+(?:zoom|meet|teams)[^\s\n\r]*)', body, re.IGNORECASE)
    if loc:
        e.location = loc.group(1)[:200]

    cal = Calendar(events=[e])
    ics_bytes = str(cal).encode('utf-8')

    if import_ics(ics_bytes):
        print(f"  Title: {e.name}")
        print(f"  Date:  {dt.strftime('%Y-%m-%d %H:%M')}")
    else:
        print("Failed to import generated event")
        sys.exit(1)


def main():
    raw = sys.stdin.buffer.read()
    msg = BytesParser().parsebytes(raw)

    # Try ICS attachments first (the reliable path)
    imported = 0
    for ics_data in extract_ics_parts(msg):
        if import_ics(ics_data):
            imported += 1

    if imported:
        print(f"Imported {imported} event(s) from ICS attachment(s)")
        return

    # No ICS found — fall back to body parsing
    print("No ICS attachment found, parsing email body...")
    fallback_parse(msg)


if __name__ == '__main__':
    main()
