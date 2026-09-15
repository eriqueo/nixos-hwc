#!/usr/bin/env python3
"""Review an email as a task, then write it through the HWC MCP gateway."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from email import policy
from email.header import decode_header
from email.parser import BytesParser
from html.parser import HTMLParser


MAX_MESSAGE_BYTES = 25 * 1024 * 1024
MAX_DESCRIPTION_CHARS = 8000


class TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.hidden = 0

    def handle_starttag(self, tag: str, attrs) -> None:
        if tag in {"script", "style", "head"}:
            self.hidden += 1
        elif tag in {"br", "p", "div", "li", "tr", "h1", "h2", "h3", "h4"}:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "head"} and self.hidden:
            self.hidden -= 1
        elif tag in {"p", "div", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data: str) -> None:
        if not self.hidden:
            self.parts.append(data)

    def text(self) -> str:
        value = "".join(self.parts)
        value = re.sub(r"[ \t]+", " ", value)
        value = re.sub(r"\n\s*\n\s*\n+", "\n\n", value)
        return value.strip()


def decoded_header(value: str | None, default: str = "") -> str:
    if not value:
        return default
    out: list[str] = []
    for part, charset in decode_header(value):
        out.append(part.decode(charset or "utf-8", errors="replace") if isinstance(part, bytes) else part)
    return "".join(out).strip()


def message_text(msg) -> str:
    plain: list[str] = []
    html_parts: list[str] = []
    for part in msg.walk() if msg.is_multipart() else [msg]:
        if part.get_content_disposition() == "attachment":
            continue
        content_type = part.get_content_type()
        if content_type not in {"text/plain", "text/html"}:
            continue
        try:
            content = part.get_content()
        except (LookupError, UnicodeError):
            payload = part.get_payload(decode=True) or b""
            content = payload.decode("utf-8", errors="replace")
        if content_type == "text/plain":
            plain.append(str(content))
        else:
            html_parts.append(str(content))
    if any(value.strip() for value in plain):
        return "\n".join(plain).strip()
    extractor = TextExtractor()
    extractor.feed("\n".join(html_parts))
    return extractor.text()


def parse_proposal(text: str) -> dict[str, str] | None:
    values: dict[str, str] = {}
    notes: list[str] = []
    in_notes = False
    for line in text.splitlines():
        if line.startswith("#"):
            if "Notes" in line:
                in_notes = True
            continue
        if in_notes:
            notes.append(line)
            continue
        match = re.match(r"^(Summary|List|Due|Categories|Priority):\s*(.*)$", line, re.IGNORECASE)
        if match:
            values[match.group(1).lower()] = match.group(2).strip()
    values["description"] = "\n".join(notes).strip()
    return values if values.get("summary") else None


def review(proposal: str) -> dict[str, str] | None:
    fd, path = tempfile.mkstemp(prefix="mail-task-", suffix=".txt")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(proposal)
        before = os.stat(path).st_mtime_ns
        editor = shlex.split(os.environ.get("EDITOR") or os.environ.get("VISUAL") or "vi")
        subprocess.run([*editor, path], check=True)
        if os.stat(path).st_mtime_ns == before:
            return None
        with open(path, encoding="utf-8") as handle:
            return parse_proposal(handle.read())
    finally:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def task_lists() -> list[str]:
    try:
        result = subprocess.run(
            ["hwc-mcp-call", "hwc_tasks_lists", '{"action":"list"}'],
            check=True,
            capture_output=True,
            text=True,
        )
        payload = json.loads(result.stdout)
        rows = payload.get("data", {}).get("lists", []) if isinstance(payload, dict) else []
        return [str(row["name"]) for row in rows if isinstance(row, dict) and row.get("name")]
    except (FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError, TypeError):
        return []


def main() -> int:
    raw = sys.stdin.buffer.read(MAX_MESSAGE_BYTES + 1)
    if len(raw) > MAX_MESSAGE_BYTES:
        print("Task not created: email is larger than the 25 MiB handoff limit.", file=sys.stderr)
        return 1
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    subject = decoded_header(msg.get("Subject"), "Follow up on email")
    sender = decoded_header(msg.get("From"), "unknown sender")
    message_id = (msg.get("Message-ID") or "").strip()
    source_key = message_id or f"sha256:{hashlib.sha256(raw).hexdigest()}"
    body = message_text(msg)
    source_url = f"mid:{message_id.strip('<>')}" if message_id else ""
    reference = [
        f"Source: Email from {sender}",
        f"Subject: {subject}",
        f"Message-ID: {message_id or '(missing; raw-message hash used)'}",
    ]
    if source_url:
        reference.append(f"Email link: {source_url}")
    description = "\n".join(reference)
    if body:
        description += "\n\nEmail excerpt:\n" + body[:4000]

    lists = task_lists()
    default_list = next(
        (name for name in ("Work", "work", "hwc") if name in lists),
        lists[0] if lists else "Work",
    )
    available = ", ".join(lists) if lists else "unavailable (the write will validate your choice)"
    proposal = f"""# Review task — save and close to create it
# Clear Summary to cancel. Nothing is archived automatically.
# Available lists: {available}

Summary: {subject}
List: {default_list}
Due:
Categories:
Priority:

# Notes
{description[:MAX_DESCRIPTION_CHARS]}
"""
    try:
        values = review(proposal)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"Task not created: editor failed: {exc}", file=sys.stderr)
        return 1
    if not values:
        print("Task handoff cancelled. Email is unchanged.")
        return 0

    arguments: dict[str, object] = {
        "summary": values["summary"],
        "list": values.get("list") or default_list,
        "description": values.get("description", "")[:MAX_DESCRIPTION_CHARS],
        "idempotencyKey": f"email:{source_key}",
        "requestVersion": 1,
    }
    categories = [token for token in re.split(r"[,\s]+", values.get("categories", "")) if token]
    if categories:
        arguments["categories"] = categories
    if values.get("due"):
        arguments["due"] = values["due"]
    if values.get("priority"):
        priority = values["priority"].strip().upper().strip("()")
        if len(priority) == 1 and "A" <= priority <= "I":
            arguments["priority"] = ord(priority) - 64
        elif priority.isdigit() and 1 <= int(priority) <= 9:
            arguments["priority"] = int(priority)
        else:
            print("Task not created: Priority must be A-I or 1-9.", file=sys.stderr)
            return 1

    try:
        result = subprocess.run(
            ["hwc-mcp-call", "--write", "hwc_tasks_add", json.dumps(arguments)],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        print("Task not created: hwc-mcp-call is not installed on this host.", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout).strip()
        print(f"Task result is unknown: {detail}", file=sys.stderr)
        print("Inspect Tasks before trying again. Email is unchanged.", file=sys.stderr)
        return 1

    payload = json.loads(result.stdout)
    message = payload.get("message", "Task created") if isinstance(payload, dict) else "Task created"
    print(f"{message}. Press a to finish with this email.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
