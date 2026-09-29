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


def main() -> None:
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
