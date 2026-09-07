#!/usr/bin/env python3
r"""Deterministic canonicalizer + secret scanner for tracked n8n workflow JSON.

WHY THIS EXISTS
    Live n8n is the source of truth for workflow behaviour. The JSON under
    domains/automation/n8n/parts/workflows/ is a *derived export*: a
    deterministic, redacted projection of a live workflow, kept in git so that
    changes are reviewable and so that a lost instance can be rebuilt. Before
    this tool the two were "kept in sync by hand", which let the tracked
    Frigate export drift past a snapshot-upload rewrite while the live workflow
    still carried a raw Discord webhook that a future export could expose.

WHAT IT DOES NOT DO
    It never talks to n8n. There is no HTTP client here on purpose: the
    operator exports from the UI or the n8n CLI and hands this tool a FILE.
    Input path, output path and the clock are all explicit parameters; nothing
    is read from the environment or from the wall clock, so the same input
    always produces the same bytes.

USAGE
    # canonical write (fails, writing nothing, if any secret is left)
    python3 workspace/automation/n8n-workflow-export.py canonicalize \
        --in /tmp/live-export.json \
        --out domains/automation/n8n/parts/workflows/02-frigate-surveillance-intelligence.json

    # same, but replace KNOWN secret shapes with a placeholder first
    ... canonicalize --in X --out Y --redact

    # audit tracked artifacts (this is what the flake check runs)
    python3 workspace/automation/n8n-workflow-export.py scan \
        --dir domains/automation/n8n/parts/workflows

EXIT CODES
    0 clean   1 usage/IO error   2 secret findings (nothing written)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from typing import Any, Iterable, List, NamedTuple, Optional, Tuple

TOOL_PATH = "workspace/automation/n8n-workflow-export.py"
PLACEHOLDER = "__HWC_REDACTED__"

GENERATED_NOTE = (
    "GENERATED — deterministic redacted export of the live n8n workflow. "
    "Live n8n is the source of truth; do not hand-edit. Re-export and rerun "
    "the rebuild command instead."
)

# ---------------------------------------------------------------------------
# CANONICAL FORM
# ---------------------------------------------------------------------------
# Dropped at the TOP LEVEL of the document. Every one is instance state, not
# workflow definition: it changes when nobody edited the workflow, so keeping
# it makes every export a diff. `activeVersion` in particular is a verbatim
# second copy of nodes+connections (see the tracked 09/10/12 API dumps) — two
# producers of one fact, and the copy is what a careless reader edits.
#
# Anchored at the top level ON PURPOSE. Dropping these names at any depth
# would silently delete a connection whose source node is named "meta", or a
# node parameter called "createdAt". Every volatile field n8n actually emits
# lives either here or inside `tags[]` (handled by _normalize_tags), so the
# blanket walk would buy nothing and could corrupt topology.
VOLATILE_TOP_LEVEL_KEYS = frozenset({
    "active",
    "activeVersion",
    "activeVersionId",
    "authors",
    "autosaved",
    "createdAt",
    "isArchived",
    "meta",
    "pinData",
    "shared",
    "staticData",
    "triggerCount",
    "updatedAt",
    "versionCounter",
    "versionId",
    "workflowPublishHistory",
})

# Deliberately KEPT, so the decision is visible rather than implied:
#   nodes[].position   UI layout; dropping it stacks every node at the origin
#                      on re-import. Noisy but load-bearing.
#   nodes[].id         referenced by n8n internals; stable across exports.
#   credentials{}      credential *references* (id + display name), never
#                      credential material. n8n keeps the secret in its own
#                      encrypted store.


def _prune_top(doc: dict) -> dict:
    return {k: v for k, v in doc.items() if k not in VOLATILE_TOP_LEVEL_KEYS}


def _normalize_tags(doc: dict) -> None:
    """Tags carry instance-local ids and timestamps; only the name is portable."""
    tags = doc.get("tags")
    if not isinstance(tags, list):
        return
    names = set()
    for tag in tags:
        if isinstance(tag, dict) and isinstance(tag.get("name"), str):
            names.add(tag["name"])
        elif isinstance(tag, str):
            names.add(tag)
    doc["tags"] = [{"name": name} for name in sorted(names)]


def _sort_nodes(doc: dict) -> None:
    """Node ORDER is not semantic — connections address nodes by name — but the
    UI reorders the array on every save. Sorting kills that diff noise.
    Connection lists are NOT sorted: their index IS the output branch."""
    nodes = doc.get("nodes")
    if isinstance(nodes, list):
        doc["nodes"] = sorted(
            nodes,
            key=lambda n: (
                str(n.get("name", "")) if isinstance(n, dict) else "",
                str(n.get("id", "")) if isinstance(n, dict) else "",
            ),
        )


def rebuild_command(out_path: Optional[str]) -> str:
    target = out_path if out_path else "<canonical-path>.json"
    return (
        "python3 " + TOOL_PATH + " canonicalize "
        "--in <live-export.json> --out " + target
    )


def canonicalize(doc: dict, out_path: Optional[str] = None) -> dict:
    """Pure: volatile fields out, ordering fixed, provenance marker in.

    The marker carries the source workflow id and name and NO timestamp — a
    timestamp would make every regeneration a diff and would defeat the point
    of a deterministic artifact.
    """
    result = _prune_top(doc)
    _normalize_tags(result)
    _sort_nodes(result)
    result["_hwc"] = {
        "generatedBy": TOOL_PATH,
        "note": GENERATED_NOTE,
        "rebuild": rebuild_command(out_path),
        "sourceWorkflowId": doc.get("id"),
        "sourceWorkflowName": doc.get("name"),
    }
    return result


def dumps(doc: dict) -> str:
    """One serialization, used by every writer and every test."""
    return json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=True) + "\n"


# ---------------------------------------------------------------------------
# SECRET DETECTION
# ---------------------------------------------------------------------------
# Named shapes are split across a concatenation so this file never contains the
# literal it hunts for. Same trick as charter-law14's `nixos[-]hwc`: a check
# that matches its own definition is a check nobody can keep green.
SECRET_PATTERNS = {
    "discord-webhook": re.compile(
        r"https?://(?:[a-z]+\.)?discord(?:app)?\.com/api/web" + r"hooks/\d+/[A-Za-z0-9_.-]{16,}"
    ),
    "slack-webhook": re.compile(
        r"https?://hooks\.slack\.com/serv" + r"ices/[A-Za-z0-9]{5,}/[A-Za-z0-9]{5,}/[A-Za-z0-9]{16,}"
    ),
    "bearer-token": re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]{16,}"),
    "anthropic-key": re.compile(r"sk-ant-[A-Za-z0-9_-]{16,}"),
    "openai-key": re.compile(r"\bsk-[A-Za-z0-9]{32,}"),
    "aws-access-key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "jwt": re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
    "private-key-block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
}

# Keys whose STRING value is credential material if it is a literal.
CRED_KEY_RE = re.compile(
    r"(?i)(pass(word|phrase)|secret|token|api[_-]?key|apikey|grant[_-]?key"
    r"|authorization|auth[_-]?token|webhook[_-]?url|private[_-]?key|client[_-]?secret)"
)
TOKEN_SHAPE_RE = re.compile(r"^[A-Za-z0-9._~+/=-]{16,}$")
ENV_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")

URL_RE = re.compile(r"https?://[^\s\"'<>`\\]+")
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")
SEGMENT_SPLIT_RE = re.compile(r"[/?&=;#]")
# An unknown provider's webhook/token lives in a long opaque path or query
# segment. 20 chars clears every routing word used by the tracked workflows
# ("script-executor", "transcript-extract", "master.m3u8") while still
# catching a pasted credential from a service this tool has never heard of.
OPAQUE_MIN = 20
OPAQUE_RE = re.compile(r"^[A-Za-z0-9_.~-]{%d,}$" % OPAQUE_MIN)


class Finding(NamedTuple):
    """One credential-shaped literal: which rule matched, where, and a prefix.

    Deliberately NO __str__. A NamedTuple *is* the argument tuple, so
    `"%s" % finding` raises TypeError before any __str__ could run — a __str__
    here would read like a safety net that %-formatting never reaches. Render
    through format_finding(), which is the one producer of the reported line.
    """
    rule: str
    where: str
    excerpt: str


# A finding is located by `where` (its JSON path), not by its text, so the
# excerpt only has to let a reader recognise the literal once they open the
# file. Anything longer is credential material in a CI transcript.
EXCERPT_HEAD = 12


def _excerpt(text: str) -> str:
    """Never echo a full credential into a log or a CI transcript.

    Reports a short prefix plus the full length, so a truncated report is
    distinguishable from a genuinely short value without printing the value.
    """
    flat = text.strip().replace("\n", " ")
    if len(flat) <= EXCERPT_HEAD:
        return flat
    return "%s...(%d chars)" % (flat[:EXCERPT_HEAD], len(flat))


def format_finding(finding: Finding) -> str:
    """The reported line for one finding. Fields are named rather than
    positional so a path containing ':' or '|' cannot be misread as structure."""
    return "rule=%s where=%s excerpt=%s" % (finding.rule, finding.where, finding.excerpt)


def _is_expression(value: str) -> bool:
    """n8n expressions (`={{ $env.X }}`) are references, not literals."""
    return "{{" in value or "${" in value


def _opaque_url_findings(value: str, where: str) -> List[Finding]:
    out = []
    for match in URL_RE.finditer(value):
        url = match.group(0).rstrip(".,);\"'")
        after_scheme = url.split("://", 1)[1]
        if "/" not in after_scheme:
            continue
        tail = after_scheme.split("/", 1)[1]
        for segment in SEGMENT_SPLIT_RE.split(tail):
            if not segment or any(ch in segment for ch in "{}$%+"):
                continue
            if segment == PLACEHOLDER or UUID_RE.match(segment):
                continue
            if OPAQUE_RE.match(segment):
                out.append(Finding("opaque-url-segment", where, _excerpt(segment)))
    return out


def scan_text(value: str, where: str = "<text>") -> List[Finding]:
    """Named shapes + opaque URL segments. Used on raw text and on every
    string value inside a workflow (jsCode and jsonBody are strings too, so an
    embedded secret cannot hide behind n8n's own encodings)."""
    out = [
        Finding(name, where, _excerpt(match.group(0)))
        for name, pattern in sorted(SECRET_PATTERNS.items())
        for match in pattern.finditer(value)
    ]
    out.extend(_opaque_url_findings(value, where))
    return out


def _literal_credential(value: str) -> bool:
    if _is_expression(value) or value == PLACEHOLDER:
        return False
    if "://" in value:
        return False  # URL rules own this one; don't double-report
    if ENV_NAME_RE.match(value):
        return False  # an env var NAME, not its value
    return bool(TOKEN_SHAPE_RE.match(value))


def scan_doc(node: Any, where: str = "$") -> List[Finding]:
    out: List[Finding] = []
    if isinstance(node, dict):
        # n8n header/body parameters are {"name": ..., "value": ...} pairs, so
        # the credential-ish word is in a VALUE, not in the key.
        name, value = node.get("name"), node.get("value")
        if (
            isinstance(name, str)
            and isinstance(value, str)
            and CRED_KEY_RE.search(name)
            and _literal_credential(value)
        ):
            out.append(Finding("credential-parameter", where + "." + name, _excerpt(value)))
        for key, sub in node.items():
            child = where + "." + str(key)
            if isinstance(sub, str) and CRED_KEY_RE.search(str(key)) and _literal_credential(sub):
                out.append(Finding("credential-key", child, _excerpt(sub)))
            out.extend(scan_doc(sub, child))
    elif isinstance(node, list):
        for index, item in enumerate(node):
            out.extend(scan_doc(item, "%s[%d]" % (where, index)))
    elif isinstance(node, str):
        out.extend(scan_text(node, where))
    return out


def redact_known(node: Any) -> Tuple[Any, int]:
    """Replace matches of the NAMED patterns with the placeholder.

    Only named shapes are redacted. A credential-ish key or an opaque URL from
    a provider this tool does not know is a finding the operator must look at,
    not something to paper over: silently concealing an unrecognised secret is
    the failure mode this whole tool exists to prevent.
    """
    if isinstance(node, dict):
        total = 0
        out = {}
        for key, sub in node.items():
            out[key], count = redact_known(sub)
            total += count
        return out, total
    if isinstance(node, list):
        total = 0
        out_list = []
        for item in node:
            new_item, count = redact_known(item)
            out_list.append(new_item)
            total += count
        return out_list, total
    if isinstance(node, str):
        total = 0
        text = node
        for pattern in SECRET_PATTERNS.values():
            text, count = pattern.subn(PLACEHOLDER, text)
            total += count
        return text, total
    return node, 0


# ---------------------------------------------------------------------------
# I/O EDGES
# ---------------------------------------------------------------------------
def _load(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        doc = json.load(handle)
    if not isinstance(doc, dict):
        raise ValueError("%s: expected a workflow object, got %s" % (path, type(doc).__name__))
    return doc


def _report(findings: Iterable[Finding], stream) -> None:
    for finding in findings:
        stream.write("  " + format_finding(finding) + "\n")


def cmd_canonicalize(args: argparse.Namespace, stdout, stderr) -> int:
    doc = _load(getattr(args, "in"))
    redacted = 0
    if args.redact:
        doc, redacted = redact_known(doc)
    canonical = canonicalize(doc, out_path=None if args.out == "-" else args.out)

    findings = scan_doc(canonical)
    if findings:
        stderr.write(
            "REFUSING TO WRITE %s — %d secret finding(s) remain:\n" % (args.out, len(findings))
        )
        _report(findings, stderr)
        stderr.write(
            "  Fix the LIVE workflow to reference $env instead of a literal, re-export,\n"
            "  and rerun. --redact only covers known shapes, by design.\n"
        )
        return 2

    text = dumps(canonical)
    if args.out == "-":
        stdout.write(text)
    else:
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text)
    stderr.write(
        "canonicalized %s -> %s (%d known secret(s) redacted, clock=%s)\n"
        % (getattr(args, "in"), args.out, redacted, args.now)
    )
    return 0


def _targets(args: argparse.Namespace) -> List[str]:
    paths = list(args.path or [])
    if args.dir:
        for entry in sorted(os.listdir(args.dir)):
            if entry.endswith(".json"):
                paths.append(os.path.join(args.dir, entry))
    return paths


def cmd_scan(args: argparse.Namespace, stdout, stderr) -> int:
    paths = _targets(args)
    if not paths:
        stderr.write("nothing to scan (pass --dir or --path)\n")
        return 1
    failed = 0
    for path in paths:
        findings = scan_doc(_load(path))
        if findings:
            failed += 1
            stderr.write("%s: %d secret finding(s)\n" % (path, len(findings)))
            _report(findings, stderr)
    if failed:
        stderr.write("%d of %d workflow artifact(s) contain credential-shaped literals\n"
                     % (failed, len(paths)))
        return 2
    stdout.write("scanned %d workflow artifact(s): clean\n" % len(paths))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=os.path.basename(TOOL_PATH), description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    can = sub.add_parser("canonicalize", help="write a deterministic redacted export")
    can.add_argument("--in", required=True, metavar="FILE", help="operator-supplied n8n export")
    can.add_argument("--out", required=True, metavar="FILE", help="canonical path, or - for stdout")
    can.add_argument("--redact", action="store_true", help="replace KNOWN secret shapes first")
    can.add_argument(
        "--now",
        default="unset",
        metavar="STAMP",
        help="explicit clock. Recorded in the stderr summary only — it can never "
             "reach the artifact, which is what keeps regeneration byte-stable.",
    )
    can.set_defaults(func=cmd_canonicalize)

    scan = sub.add_parser("scan", help="fail on credential-shaped literals")
    scan.add_argument("--dir", metavar="DIR", help="scan every *.json in DIR")
    scan.add_argument("--path", action="append", metavar="FILE", help="scan one file (repeatable)")
    scan.set_defaults(func=cmd_scan)
    return parser


def main(argv: Optional[List[str]] = None, stdout=None, stderr=None) -> int:
    args = build_parser().parse_args(argv)
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    try:
        return args.func(args, stdout, stderr)
    except (OSError, ValueError) as err:
        stderr.write("error: %s\n" % err)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
