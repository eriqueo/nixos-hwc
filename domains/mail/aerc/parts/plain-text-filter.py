"""Make sender-authored plain email calm and safe to read in a terminal.

The aerc wrap filter runs before this program so format=flowed messages keep
their intended paragraphs.  This final pass removes terminal control strings,
hides long tracking URLs behind truthful OSC 8 domain labels, and bounds
vertical whitespace.  It never resolves a URL or makes a network request.
"""

from __future__ import annotations

import re
import subprocess
import sys
import resource
import shutil
from email import policy
from email.parser import BytesParser
from html.parser import HTMLParser
from urllib.parse import urlsplit


COMPACT_URL_AT = 72
OSC_8 = "\x1b]8;;{url}\x1b\\{label}\x1b]8;;\x1b\\"

# Email is untrusted terminal input. Remove control strings before introducing
# our own narrowly constructed OSC 8 links.
CONTROL_STRING_RE = re.compile(
    r"\x1b(?:\][^\x07]*(?:\x07|\x1b\\)|[PX^_].*?\x1b\\)", re.DOTALL
)
CSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
CONTROL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]")
URL_RE = re.compile(
    r"<(?P<angle>https?://[^<>\s]+)>|(?P<bare>https?://[^<>\s]+)", re.IGNORECASE
)


def sanitize(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = CONTROL_STRING_RE.sub("", text)
    text = CSI_RE.sub("", text)
    text = text.replace("\x1b", "")
    return CONTROL_RE.sub("", text)


def compact_url(match: re.Match[str]) -> str:
    url = match.group("angle") or match.group("bare")
    if len(url) < COMPACT_URL_AT:
        return match.group(0)

    try:
        hostname = urlsplit(url).hostname
        if not hostname:
            return match.group(0)
        hostname = hostname.encode("idna").decode("ascii").lower()
    except (UnicodeError, ValueError):
        return match.group(0)

    if hostname.startswith("www."):
        hostname = hostname[4:]
    if not re.fullmatch(r"[a-z0-9.-]+", hostname):
        return match.group(0)

    return OSC_8.format(url=url, label=f"↗ {hostname}")


def render(text: str) -> str:
    text = URL_RE.sub(compact_url, sanitize(text))

    lines: list[str] = []
    previous_blank = True
    for raw_line in text.split("\n"):
        line = raw_line.rstrip()
        blank = not line
        if blank:
            if not previous_blank:
                lines.append("")
        else:
            lines.append(line)
        previous_blank = blank

    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines) + ("\n" if lines else "")


class HTMLLinks(HTMLParser):
    """Keep original web targets and labels, including table-based buttons."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, str]] = []
        self.target: str | None = None
        self.label: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "a":
            self.finish_link()
            href = dict(attrs).get("href") or ""
            # Validate once at the HTML boundary. Never put terminal controls
            # or non-web schemes in a generated hyperlink.
            try:
                parsed = urlsplit(href)
                valid = parsed.scheme in ("http", "https") and parsed.hostname
            except ValueError:
                valid = False
            if valid and sanitize(href) == href and not re.search(r"\s", href):
                self.target = href
        elif tag == "img" and self.target:
            self.label.append(dict(attrs).get("alt") or "")

    def handle_data(self, data: str) -> None:
        if self.target:
            self.label.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a":
            self.finish_link()

    def finish_link(self) -> None:
        if self.target:
            label = " ".join(sanitize(" ".join(self.label)).split())[:100]
            link = (label or "Open link", self.target)
            if link not in self.links:
                self.links.append(link)
        self.target = None
        self.label = []


def render_html(source: str, rendered_body: str) -> str:
    links = HTMLLinks()
    links.feed(source)
    links.finish_link()
    body = render(rendered_body)
    if not links.links:
        return body
    references = "\n".join(
        f"[{number}] {label} → " + OSC_8.format(url=url, label=urlsplit(url).hostname)
        for number, (label, url) in enumerate(links.links, 1)
    )
    return body.rstrip() + "\n\nLinks — Ctrl-click to open in your browser:\n" + references + "\n"


MAX_MESSAGE_BYTES = 32 * 1024 * 1024
MAX_IMAGES = 32
RASTER_TYPES = {"image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/tiff"}


class HTMLImages(HTMLParser):
    """Replace image tags with markers before the isolated HTML text pass."""

    def __init__(self, source: str) -> None:
        super().__init__(convert_charrefs=False)
        # One-cell markers survive narrow table layouts. Reserve only characters
        # absent from sender text, so replacement cannot alter original content.
        self.markers = (chr(code) for code in range(0xE000, 0xF900) if chr(code) not in source)
        self.fragments: list[str] = []
        self.images: dict[str, tuple[str, str]] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "img":
            self.fragments.append(self.get_starttag_text())
            return
        attrs_map = dict(attrs)
        if len(self.images) >= MAX_IMAGES:
            self.fragments.append("<p>[Image limit reached]</p>")
            return
        marker = next(self.markers, None)
        if marker is None:
            raise ValueError("Image placeholders unavailable. Use the normal view.")
        self.images[marker] = (attrs_map.get("src") or "", attrs_map.get("alt") or "Image")
        self.fragments.append(f"<p>{marker}</p>")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag: str) -> None:
        self.fragments.append(f"</{tag}>")

    def handle_data(self, data: str) -> None:
        self.fragments.append(data)

    def handle_entityref(self, name: str) -> None:
        self.fragments.append(f"&{name};")

    def handle_charref(self, name: str) -> None:
        self.fragments.append(f"&#{name};")


def render_message_images(raw: bytes, html_renderer: str, image_renderer: str, columns: int) -> str:
    """Render attached CID pictures locally; remote pictures never enter a decoder.

    Permanent by design: portable symbol graphics work through SSH, multiplexers,
    and less without changing the normal viewer or requiring a graphics protocol.
    """
    if len(raw) > MAX_MESSAGE_BYTES:
        raise ValueError("Message exceeds the 32 MiB image-view limit. Use the normal view.")
    message = BytesParser(policy=policy.default).parsebytes(raw)
    body = message.get_body(preferencelist=("html", "plain"))
    if body is None:
        return "No readable message body. Use the normal view.\n"
    source = body.get_content()
    if body.get_content_type() == "text/plain":
        return render(source)

    # Resolve CIDs in the related container that owns the selected HTML body.
    # An attached forwarded message must not supply a conflicting image.
    related = next((part for part in message.walk()
                    if part.get_content_type() == "multipart/related"
                    and any(child is body for child in part.walk())), message)
    attachments = {}
    for part in related.walk():
        cid = str(part.get("Content-ID", "")).strip("<>")
        if cid and part.get_content_type() in RASTER_TYPES:
            attachments.setdefault(cid, part)
    images = HTMLImages(source)
    images.feed(source)
    result = subprocess.run([html_renderer, "-o", "decode_url=false"],
                            input="".join(images.fragments), text=True,
                            capture_output=True, timeout=15, check=True)
    text = render_html(source, result.stdout)
    columns = max(10, min(columns, 100))
    for marker, (src, alt) in images.images.items():
        label = " ".join(sanitize(alt).split())[:100] or "Image"
        part = attachments.get(src[4:]) if src.lower().startswith("cid:") else None
        replacement = f"[{label}: remote image blocked]\n" if part is None and not src.lower().startswith("cid:") else f"[{label}: attached image missing]\n"
        if part is not None:
            try:
                preview = subprocess.run(
                    [image_renderer, "--format=symbols", "--symbols=half",
                     "--colors=full", "--animate=off", "--probe=off",
                     "--polite=on", "--size=" + str(columns) + "x24", "-"],
                    input=part.get_payload(decode=True), capture_output=True,
                    timeout=10, check=True,
                )
                replacement = f"[{label}]\n" + preview.stdout.decode("utf-8", errors="replace")
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                replacement = f"[{label}: image could not be displayed. Use the image attachment view.]\n"
        text = text.replace(marker, replacement.rstrip())
    return text


def main() -> None:
    if len(sys.argv) == 4 and sys.argv[1] == "--message-images":
        # Decoder children inherit this ceiling. Oversized decoded images fail
        # locally instead of exhausting the mail host's memory.
        resource.setrlimit(resource.RLIMIT_AS, (512 * 1024 * 1024,) * 2)
        resource.setrlimit(resource.RLIMIT_CPU, (10, 10))
        try:
            raw = sys.stdin.buffer.read(MAX_MESSAGE_BYTES + 1)
            columns = shutil.get_terminal_size(fallback=(80, 24)).columns
            sys.stdout.write(render_message_images(raw, sys.argv[2], sys.argv[3], columns))
        except (ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
            sys.stderr.write("Image view failed. Use the normal view.\n")
            raise SystemExit(1) from error
        return
    source = sys.stdin.read()
    if len(sys.argv) == 3 and sys.argv[1] == "--html-renderer":
        # The configured bundled renderer owns network isolation. Keep its
        # readable layout, but derive links from source so targets stay exact.
        result = subprocess.run(
            [sys.argv[2], "-o", "decode_url=false"],
            input=source, text=True, capture_output=True,
        )
        if result.returncode:
            sys.stderr.write(result.stderr)
            raise SystemExit(result.returncode)
        sys.stdout.write(render_html(source, result.stdout))
    else:
        sys.stdout.write(render(source))


if __name__ == "__main__":
    main()
