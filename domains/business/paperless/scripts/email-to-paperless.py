#!/usr/bin/env python3
"""Render an email as a safe, deterministic PDF and queue it for Paperless."""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import tempfile
import textwrap
import unicodedata
from email import policy
from email.header import decode_header
from email.parser import BytesParser
from html.parser import HTMLParser
from pathlib import Path

from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas


MAX_MESSAGE_BYTES = 25 * 1024 * 1024
MAX_RENDER_CHARS = 120_000


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
        return re.sub(r"\n\s*\n\s*\n+", "\n\n", value).strip()


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
        if part.get_content_type() not in {"text/plain", "text/html"}:
            continue
        try:
            content = str(part.get_content())
        except (LookupError, UnicodeError):
            content = (part.get_payload(decode=True) or b"").decode("utf-8", errors="replace")
        if part.get_content_type() == "text/plain":
            plain.append(content)
        else:
            html_parts.append(content)
    if any(value.strip() for value in plain):
        return "\n".join(plain).strip()
    extractor = TextExtractor()
    extractor.feed("\n".join(html_parts))
    return extractor.text()


def pdf_text(value: str) -> str:
    value = unicodedata.normalize("NFKD", value)
    return value.encode("latin-1", errors="replace").decode("latin-1")


def safe_stem(subject: str) -> str:
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", pdf_text(subject).lower()).strip("-.")
    return (stem or "email-record")[:80]


def render_pdf(path: str, *, subject: str, sender: str, recipient: str, date: str, message_id: str, body: str, attachments: list[str]) -> None:
    # invariant=1 removes timestamps/random document IDs, making the same email
    # byte-identical across repeated handoffs for downstream checksum dedupe.
    doc = canvas.Canvas(path, pagesize=letter, invariant=1, pageCompression=1)
    doc.setTitle(pdf_text(subject))
    doc.setAuthor(pdf_text(sender))
    doc.setCreator("email-to-paperless")
    width, height = letter
    left = 54
    y = height - 54

    def line(value: str, *, bold: bool = False, gap: int = 14) -> None:
        nonlocal y
        if y < 54:
            doc.showPage()
            y = height - 54
        doc.setFont("Helvetica-Bold" if bold else "Helvetica", 10)
        doc.drawString(left, y, pdf_text(value)[:180])
        y -= gap

    line(subject, bold=True, gap=20)
    for label, value in (("From", sender), ("To", recipient), ("Date", date), ("Message-ID", message_id)):
        line(f"{label}: {value or '(none)'}")
    if attachments:
        line("Attachments: " + ", ".join(attachments))
    y -= 8
    for paragraph in body[:MAX_RENDER_CHARS].splitlines() or ["(No readable message body)"]:
        wrapped = textwrap.wrap(paragraph, width=95, replace_whitespace=False, drop_whitespace=True) or [""]
        for value in wrapped:
            line(value, gap=12)
    doc.save()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--consume-dir", required=True)
    parser.add_argument("--staging-dir", required=True)
    args = parser.parse_args()

    raw = sys.stdin.buffer.read(MAX_MESSAGE_BYTES + 1)
    if len(raw) > MAX_MESSAGE_BYTES:
        print("Paperless handoff failed: email exceeds the 25 MiB limit.", file=sys.stderr)
        return 1
    msg = BytesParser(policy=policy.default).parsebytes(raw)
    subject = decoded_header(msg.get("Subject"), "Email record")
    sender = decoded_header(msg.get("From"))
    recipient = decoded_header(msg.get("To"))
    date = decoded_header(msg.get("Date"))
    message_id = (msg.get("Message-ID") or "").strip()
    attachments = [decoded_header(part.get_filename()) for part in msg.iter_attachments() if part.get_filename()]
    body = message_text(msg)
    fingerprint = hashlib.sha256(raw).hexdigest()
    filename = f"email-{safe_stem(subject)}-{fingerprint[:16]}.pdf"

    consume = Path(args.consume_dir)
    staging = Path(args.staging_dir)
    if not consume.is_dir() or not staging.is_dir():
        print("Paperless handoff failed: consume or staging directory is missing.", file=sys.stderr)
        return 1
    if consume.stat().st_dev != staging.stat().st_dev:
        print("Paperless handoff failed: staging and consume are not on one filesystem.", file=sys.stderr)
        return 1

    fd, temp_path = tempfile.mkstemp(prefix=".email-to-paperless-", suffix=".pdf", dir=staging)
    os.close(fd)
    try:
        render_pdf(
            temp_path,
            subject=subject,
            sender=sender,
            recipient=recipient,
            date=date,
            message_id=message_id,
            body=body,
            attachments=attachments,
        )
        with open(temp_path, "rb") as handle:
            os.fsync(handle.fileno())
        destination = consume / filename
        os.replace(temp_path, destination)
        directory_fd = os.open(consume, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except Exception as exc:
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass
        print(f"Paperless handoff failed: {exc}. Email is unchanged.", file=sys.stderr)
        return 1

    print(f"Queued {filename} for Paperless. Press a to finish with this email.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
