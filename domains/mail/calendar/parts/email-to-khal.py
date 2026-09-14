#!/usr/bin/env python3
"""
email-to-khal: Import calendar events from emails into khal.

Workflow:
  ICS attachment found  → preview details → confirm → import
  No ICS attachment     → parse body for date/time/details → open $EDITOR → import

Designed for aerc's :pipe command. Reads email from stdin,
interacts with user via /dev/tty.
"""

import argparse
import ipaddress
import socket
import sys
import re
import tempfile
import subprocess
import os
import textwrap
import uuid
from datetime import datetime, timedelta, timezone
from email.parser import BytesParser
from email.header import decode_header
from html import unescape
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

MAX_REMOTE_IMAGE_BYTES = 8 * 1024 * 1024
REMOTE_IMAGE_TIMEOUT_SECONDS = 10
OCR_TIMEOUT_SECONDS = 20

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

def has_tty() -> bool:
    """Check if /dev/tty is available (not available in aerc :pipe without -p)."""
    try:
        with open("/dev/tty", "r"):
            return True
    except OSError:
        return False


def tty_input(prompt: str, default: str = "") -> str:
    """Read a line from /dev/tty, or return default if no tty available."""
    if not has_tty():
        return default
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
    elif msg.get_content_type() == "text/plain":
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


def is_campaign_tracking_url(value: str) -> bool:
    """Identify campaign redirects without resolving them over the network."""
    parsed = urlparse(value)
    host = (parsed.hostname or "").lower()
    path = parsed.path.lower()
    return (
        host in {"t.e2ma.net", "e2ma.net"}
        or host.endswith(".list-manage.com")
        or "mailchi.mp" in host
        or "/click/" in path
        or "/track/" in path
    )


def extract_html_link_records(msg) -> list[dict]:
    """Return offline metadata for links and any images they wrap."""
    records = []
    for part in msg.walk():
        if part.get_content_type() != "text/html":
            continue
        payload = part.get_payload(decode=True)
        if not payload:
            continue
        source = payload.decode("utf-8", errors="ignore")
        for match in re.finditer(
            r"<a\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>",
            source,
            re.IGNORECASE | re.DOTALL,
        ):
            href = unescape(match.group(1)).strip()
            if not href.lower().startswith(("http://", "https://")):
                continue
            inner = match.group(2)
            text = unescape(re.sub(r"<[^>]+>", " ", inner))
            text = re.sub(r"\s+", " ", text).strip()
            image_area = 0
            image_src = ""
            for image in re.finditer(r"<img\b([^>]*)>", inner, re.IGNORECASE | re.DOTALL):
                attrs = image.group(1)
                width = re.search(r"\bwidth=[\"']?(\d+)", attrs, re.IGNORECASE)
                height = re.search(r"\bheight=[\"']?(\d+)", attrs, re.IGNORECASE)
                if width and height:
                    area = int(width.group(1)) * int(height.group(1))
                    if area > image_area:
                        image_area = area
                        src = re.search(r"\bsrc=[\"']([^\"']+)[\"']", attrs, re.IGNORECASE)
                        image_src = unescape(src.group(1)).strip() if src else ""
                alt = re.search(r"\balt=[\"']([^\"']*)[\"']", attrs, re.IGNORECASE)
                if not text and alt:
                    text = unescape(alt.group(1)).strip()
            records.append({
                "href": href,
                "text": text,
                "image_area": image_area,
                "image_src": image_src,
            })
    return records


def extract_event_link(msg) -> tuple[str, str] | None:
    """Find a labeled event link or a link wrapped around the main flyer.

    This is intentionally offline. Campaign redirects are retained as tracked
    references for the user to open, but are never followed while parsing.
    """
    records = extract_html_link_records(msg)

    label_pattern = re.compile(
        r"\b(register|registration|rsvp|event|details|learn more|calendar|join)\b",
        re.IGNORECASE,
    )
    for record in records:
        if label_pattern.search(record["text"]):
            return "Event page", record["href"]
    for record in records:
        if record["image_area"] >= 120_000:
            label = (
                "Event page (tracked flyer)"
                if is_campaign_tracking_url(record["href"])
                else "Event page"
            )
            return label, record["href"]
    return None


def extract_remote_flyer(msg) -> str | None:
    """Return the large flyer image URL without requesting it."""
    candidates = [
        record for record in extract_html_link_records(msg)
        if record["image_area"] >= 120_000
        and record["image_src"].lower().startswith("https://")
        and not is_campaign_tracking_url(record["image_src"])
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda record: record["image_area"])["image_src"]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def public_https_image_url(value: str, resolver=socket.getaddrinfo) -> bool:
    """Reject local, credentialed, non-HTTPS, and nonstandard-port targets."""
    parsed = urlparse(value)
    try:
        port = parsed.port
    except ValueError:
        return False
    if (
        parsed.scheme.lower() != "https"
        or not parsed.hostname
        or parsed.username is not None
        or parsed.password is not None
        or port not in (None, 443)
    ):
        return False
    try:
        addresses = resolver(parsed.hostname, 443, type=socket.SOCK_STREAM)
    except OSError:
        return False
    if not addresses:
        return False
    return all(ipaddress.ip_address(item[4][0]).is_global for item in addresses)


def fetch_remote_image(
    value: str,
    resolver=socket.getaddrinfo,
    opener=None,
) -> bytes:
    """Fetch one public HTTPS image once, with redirects and large bodies denied."""
    if not public_https_image_url(value, resolver=resolver):
        raise ValueError("flyer URL is not a public HTTPS image")
    opener = opener or build_opener(NoRedirect)
    request = Request(value, headers={"Accept": "image/*"})
    with opener.open(request, timeout=REMOTE_IMAGE_TIMEOUT_SECONDS) as response:
        content_type = response.headers.get_content_type()
        if not content_type.startswith("image/"):
            raise ValueError(f"flyer returned {content_type}, not an image")
        declared_size = response.headers.get("Content-Length")
        if declared_size:
            try:
                size = int(declared_size)
            except ValueError as error:
                raise ValueError("flyer returned an invalid size") from error
            if size > MAX_REMOTE_IMAGE_BYTES:
                raise ValueError("flyer is larger than 8 MiB")
        data = response.read(MAX_REMOTE_IMAGE_BYTES + 1)
    if len(data) > MAX_REMOTE_IMAGE_BYTES:
        raise ValueError("flyer is larger than 8 MiB")
    return data


def ocr_remote_image(value: str, tesseract: str) -> str:
    """Download a consented flyer once and OCR it locally with a hard deadline."""
    image = fetch_remote_image(value)
    result = subprocess.run(
        [tesseract, "stdin", "stdout"],
        input=image,
        capture_output=True,
        timeout=OCR_TIMEOUT_SECONDS,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="ignore").strip()
        raise RuntimeError(detail or "local OCR failed")
    return result.stdout.decode("utf-8", errors="ignore")[:131_072].strip()


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

    # School/community mail and OCR text often contain a compact time range.
    # Normalize it into the same fields as explicit Date:/Time: lines and
    # derive the duration.
    time_range = re.search(
        r"(?P<sh>\d{1,2})(?::(?P<sm>\d{2}))?\s*(?P<sa>[ap])(?:m)?\s*"
        r"[-–—]\s*(?P<eh>\d{1,2})(?::(?P<em>\d{2}))?\s*(?P<ea>[ap])(?:m)?",
        body,
        re.IGNORECASE,
    )
    if time_range:
        fields.setdefault(
            "time_raw",
            f"{time_range.group('sh')}:{time_range.group('sm') or '00'} {time_range.group('sa')}m",
        )

        def minutes(hour: str, minute: str | None, meridiem: str) -> int:
            value = int(hour) % 12
            if meridiem.lower() == "p":
                value += 12
            return value * 60 + int(minute or "0")

        start = minutes(time_range.group("sh"), time_range.group("sm"), time_range.group("sa"))
        end = minutes(time_range.group("eh"), time_range.group("em"), time_range.group("ea"))
        duration = (end - start) % (24 * 60)
        if 0 < duration <= 12 * 60:
            fields["duration_min"] = duration

    numeric_date = re.search(r"\b\d{1,2}/\d{1,2}/(?:\d{2}|\d{4})\b", body)
    if numeric_date:
        fields.setdefault("date_raw", numeric_date.group(0))

    # Link: try plaintext first, then fall back to HTML hrefs
    m = re.search(
        r"(?:^|\n)\s*(?:Link|URL|Join|Meeting\s*Link)[^:]*:\s*(https?://\S+)",
        body, re.IGNORECASE,
    )
    if m:
        fields["link"] = m.group(1).strip()
    elif msg:
        html_urls = extract_html_links(msg)
        # Meeting links are safe to identify from their destination. For image-
        # based newsletters, retain only the main flyer link as a candidate;
        # never promote the first arbitrary campaign link.
        meeting_urls = [
            u for u in html_urls
            if re.search(r"zoom|meet|teams|webinar|gotomeeting|whereby", u, re.IGNORECASE)
        ]
        if meeting_urls:
            fields["link"] = meeting_urls[0]
            fields["link_label"] = "Meeting link"
        else:
            event_link = extract_event_link(msg)
            if event_link:
                fields["link_label"], fields["link"] = event_link

    m = re.search(r"(?:^|\n)\s*Password:\s*(\S+)", body, re.IGNORECASE)
    if m:
        fields["password"] = m.group(1).strip()

    m = re.search(
        r"(?:^|\n)\s*(?:Location|Where|Venue):\s*(.+)", body, re.IGNORECASE
    )
    if m:
        fields["location"] = m.group(1).strip()

    # Duration: "90-minute", "1 hour", "2h", "30 min". Preserve a time-
    # range-derived duration, which is more authoritative, and do not allow a
    # bare "h" across whitespace (OCR once turned "$25\nh..." into 25 hours).
    m = re.search(
        r"\b(?P<val>\d+)\s*[- ]?\s*(?P<unit>minutes?|mins?|hours?|hrs?)\b|"
        r"\b(?P<hours>\d+)h\b",
        body,
        re.IGNORECASE,
    )
    if m and "duration_min" not in fields:
        if m.group("hours"):
            fields["duration_min"] = int(m.group("hours")) * 60
        else:
            value = int(m.group("val"))
            unit = m.group("unit").lower()
            fields["duration_min"] = value * 60 if unit.startswith(("hour", "hr")) else value

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


def parse_date_only(text: str):
    """Parse a written or numeric date without inventing a start time."""
    import dateparser

    month = (
        r"January|February|March|April|May|June|July|August|"
        r"September|October|November|December"
    )
    patterns = [
        rf"(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\w*,?\s+)?"
        rf"(?:{month})\s+\d{{1,2}}(?:st|nd|rd|th)?,\s*\d{{4}}",
        r"\b\d{1,2}/\d{1,2}/(?:\d{2}|\d{4})\b",
        r"\b\d{4}-\d{2}-\d{2}\b",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if not match:
            continue
        parsed = dateparser.parse(match.group(0), settings={
            "PREFER_DATES_FROM": "future",
            "RETURN_AS_TIMEZONE_AWARE": False,
        })
        if parsed:
            return parsed
    return None


def has_explicit_time(text: str) -> bool:
    return bool(re.search(
        r"\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|\b\d{1,2}:\d{2}\b",
        text,
        re.IGNORECASE,
    ))


def clean_event_title(subject: str) -> str:
    """Remove a trailing written date that is already shown in the form."""
    month = (
        r"January|February|March|April|May|June|July|August|"
        r"September|October|November|December"
    )
    trailing_date = (
        rf"\s*[-–—]\s*(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\w*,?\s+)?"
        rf"(?:{month})\s+\d{{1,2}}(?:st|nd|rd|th)?,\s*\d{{4}}\s*$"
    )
    return re.sub(trailing_date, "", subject, flags=re.IGNORECASE).strip()


def compact_reference_text(text: str, width: int = 96, limit: int = 1600) -> str:
    """Keep review context readable without dumping a newsletter footer wall."""
    text = re.sub(r"\s+", " ", text).strip()
    if len(text) > limit:
        text = text[: limit - 1].rstrip() + "…"
    return "\n".join(textwrap.wrap(text, width=width, break_long_words=False))


def extract_street_address(text: str) -> str:
    """Extract one conventional street-address line from OCR text."""
    suffix = (
        r"Avenue|Ave|Street|St|Road|Rd|Boulevard|Blvd|Drive|Dr|"
        r"Lane|Ln|Way"
    )
    match = re.search(
        rf"(?im)^\s*(\d{{1,6}}\s+[^\n]{{1,70}}?\b(?:{suffix})\.?(?:,\s*[^\n]{{1,30}})?)\s*$",
        text,
    )
    return match.group(1).strip() if match else ""


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

    answer = tty_input("  Import? [Y/n] ", default="y").lower()
    if answer and answer != "y":
        print("  Cancelled.")
        return False

    imported = 0
    for data in ics_parts:
        if import_ics_file(data):
            imported += 1
    print(f"\n  Imported {imported} event(s).")
    return imported > 0


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


def handle_body_parse(msg, tesseract: str):
    """Parse email body, open editor for review, then import."""
    subject = decode_mime_header(msg["subject"])
    body = extract_body(msg)
    html_text = extract_html_text(msg)

    # Try plaintext first, fall back to HTML-derived text
    combined_body = body if body.strip() else html_text
    fields = parse_structured_fields(combined_body, msg)

    searchable_text = f"{subject}\n{combined_body}"
    date_only = parse_date_only(searchable_text)
    if date_only:
        fields.setdefault("date_raw", date_only.strftime("%Y-%m-%d"))
    dt, tz_name = parse_datetime(fields, searchable_text)
    # If plaintext had no dates, try HTML text too
    if not dt and html_text and combined_body != html_text:
        fields_html = parse_structured_fields(html_text, msg)
        fields.update({k: v for k, v in fields_html.items() if k not in fields})
        searchable_text = f"{subject}\n{html_text}"
        date_only = parse_date_only(searchable_text)
        if date_only:
            fields.setdefault("date_raw", date_only.strftime("%Y-%m-%d"))
        dt, tz_name = parse_datetime(fields, searchable_text)

    ocr_text = ""
    time_was_found = bool(dt) and has_explicit_time(
        f"{fields.get('time_raw', '')}\n{searchable_text}"
    )
    flyer = extract_remote_flyer(msg)
    if has_tty() and flyer and (not dt or not time_was_found):
        answer = tty_input(
            "  Event details may be inside a remote flyer. Run local OCR? [y/N] ",
            default="n",
        ).lower()
        if answer == "y":
            try:
                ocr_text = ocr_remote_image(flyer, tesseract)
                ocr_fields = parse_structured_fields(ocr_text)
                ocr_location = extract_street_address(ocr_text)
                if ocr_location:
                    ocr_fields["location"] = ocr_location
                fields.update({
                    key: value for key, value in ocr_fields.items()
                    if not fields.get(key)
                })
                searchable_text += f"\n{ocr_text}"
                date_only = parse_date_only(searchable_text)
                if date_only:
                    fields.setdefault("date_raw", date_only.strftime("%Y-%m-%d"))
                dt, tz_name = parse_datetime(fields, searchable_text)
                time_was_found = bool(dt) and has_explicit_time(
                    f"{fields.get('time_raw', '')}\n{ocr_text}"
                )
            except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
                print(f"  Could not read the remote flyer: {error}")
    duration_min = fields.get("duration_min", 60)

    # Build description from extracted details
    desc_parts = []
    sender = msg.get("from", "")
    if sender:
        desc_parts.append(f"From: {sender}")
    if fields.get("password"):
        desc_parts.append(f"Password: {fields['password']}")
    if fields.get("link"):
        desc_parts.append(f"{fields.get('link_label', 'Link')}: {fields['link']}")

    location = fields.get("location", "")

    event = {
        "title": clean_event_title(subject),
        "date": (dt or date_only).strftime("%Y-%m-%d") if (dt or date_only) else "",
        "time": dt.strftime("%H:%M") if time_was_found else "",
        "duration": f"{duration_min}m",
        "timezone": tz_name or "local",
        "location": location,
        "calendar": "",
        "description": "\n".join(desc_parts),
    }

    if not event["date"]:
        print("\n  Could not detect a date or time — fill them in manually.\n")
    elif not event["time"]:
        print(f"\n  Detected date: {event['date']}; fill in the event time.\n")
    else:
        print(f"\n  Detected: {event['date']} {event['time']} ({event['timezone']})")
        print(f"  Title:    {event['title']}")
        print(f"  Duration: {event['duration']}\n")

    # The review reference must always be readable text. `body` is empty for an
    # HTML-only message; using it here previously dumped raw markup into nvim.
    reference_body = compact_reference_text(combined_body)
    if ocr_text:
        reference_body += f"\n\n── Text read from flyer ──\n{compact_reference_text(ocr_text)}"
    if fields.get("link"):
        reference_body += (
            f"\n\n── Suggested link ──\n"
            f"{fields.get('link_label', 'Link')}: {fields['link']}"
        )

    if has_tty():
        print("  Opening editor for review...\n")
        edited = editor_review(event, email_body=reference_body)
        if not edited:
            print("  Cancelled. Email is unchanged.")
            return False
    else:
        # No tty (aerc :pipe without -p) — use auto-detected values directly
        if not event["date"] or not event["time"]:
            print("  Date or time is missing and no terminal is available for review. Aborting.")
            sys.exit(1)
        edited = {
            "title": event["title"],
            "date": event["date"],
            "time": event["time"],
            "duration": event["duration"],
            "timezone": event["timezone"],
            "location": event["location"],
            "calendar": event["calendar"],
            "description": event["description"],
        }

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
        print("\n  Event created:")
        print(f"    {edited['title']}")
        print(f"    {dt.strftime('%Y-%m-%d %H:%M')} ({dur_str})")
        if edited.get("location"):
            print(f"    {edited['location']}")
        return True
    else:
        print("\n  Failed to import event.")
        sys.exit(1)


def sync_calendar():
    """Push new events to the configured calendar server via vdirsyncer."""
    print("  Syncing calendar...")
    result = subprocess.run(
        ["vdirsyncer", "sync"],
        capture_output=True, text=True,
    )
    if result.returncode == 0:
        print("  Synced. Press a to finish with this email.")
    else:
        print(f"  Calendar item was created locally, but sync failed: {result.stderr.strip()}")
        print("  Do not create it again; the next scheduled sync can finish it. Email is unchanged.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tesseract", default="tesseract")
    args = parser.parse_args()

    raw = sys.stdin.buffer.read()
    msg = BytesParser().parsebytes(raw)

    ics_parts = extract_ics_parts(msg)
    if ics_parts:
        created = handle_ics_attachment(ics_parts)
    else:
        created = handle_body_parse(msg, args.tesseract)

    if created:
        sync_calendar()


if __name__ == "__main__":
    main()
