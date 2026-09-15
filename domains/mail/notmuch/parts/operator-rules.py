#!/usr/bin/env python3
"""Reviewed exact-sender rules for aerc and the notmuch post-new hook.

The command owns the mutable operator-rule ledger.  Nix owns the static mail
taxonomy; this ledger records decisions Eric makes while triaging real mail.
All paths and executable locations arrive as command-line arguments from the
Nix composition root so the rule core has no ambient filesystem contract.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from email import policy
from email.parser import BytesParser
from pathlib import Path
from typing import TextIO


SCHEMA_VERSION = 1
MAX_ACTIVE_RULES = 1000
MAX_MESSAGE_BYTES = 25 * 1024 * 1024
DISPOSITIONS = ("now", "archive", "trash")
FOLDER_TAGS = ("", "family", "datax", "hwc")
DESTRUCTIVE_DISPOSITIONS = ("archive", "trash")
ADDRESS_RE = re.compile(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
    r"[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$"
)


class RuleError(Exception):
    """Boundary error with a stable code suitable for UI routing."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


@dataclass(frozen=True)
class MessageContext:
    sender: str
    display_name: str
    subject: str
    message_id: str


@dataclass(frozen=True)
class RulePlan:
    sender: str
    display_name: str
    disposition: str
    folder_tag: str
    source_message_id: str
    example_subject: str


@dataclass(frozen=True)
class ActiveRule:
    rule_id: str
    sender: str
    display_name: str
    disposition: str
    folder_tag: str


def utc_now() -> str:
    """Bind the clock at the CLI boundary, not inside ledger operations."""

    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def normalize_address(value: str) -> str:
    address = value.strip().lower()
    if (
        not address
        or len(address) > 320
        or not ADDRESS_RE.fullmatch(address)
        or ".." in address
        or address.startswith(".")
        or address.endswith(".")
    ):
        raise RuleError("INVALID_SENDER", f"Not an exact email address: {value!r}")
    return address


def parse_message(raw: bytes) -> MessageContext:
    if len(raw) > MAX_MESSAGE_BYTES:
        raise RuleError(
            "MESSAGE_TOO_LARGE",
            f"Message is larger than the {MAX_MESSAGE_BYTES // (1024 * 1024)} MiB review limit.",
        )
    if raw.startswith(b"From "):
        raise RuleError(
            "MULTIPLE_MESSAGES",
            "More than one message appears selected. Clear marks and select one message.",
        )
    try:
        message = BytesParser(policy=policy.default).parsebytes(raw)
        from_header = message["From"]
        addresses = tuple(from_header.addresses) if from_header is not None else ()
    except Exception as exc:
        raise RuleError("INVALID_MESSAGE", f"Could not parse the selected email: {exc}") from exc
    if len(addresses) != 1:
        raise RuleError(
            "INVALID_SENDER",
            "The selected email must contain exactly one From address.",
        )
    sender = normalize_address(addresses[0].addr_spec)
    display_name = str(addresses[0].display_name or "").strip()
    subject = str(message.get("Subject", "(no subject)")).strip() or "(no subject)"
    message_id = str(message.get("Message-ID", "")).strip().strip("<>")
    return MessageContext(
        sender=sender,
        display_name=display_name,
        subject=subject,
        message_id=message_id,
    )


def rule_id_for(sender: str) -> str:
    material = f"mail-rule:v1:from:{normalize_address(sender)}".encode()
    return "sender-" + hashlib.sha256(material).hexdigest()[:24]


def validate_plan(plan: RulePlan) -> RulePlan:
    sender = normalize_address(plan.sender)
    if plan.disposition not in DISPOSITIONS:
        raise RuleError(
            "INVALID_DISPOSITION",
            f"Handling must be one of {', '.join(DISPOSITIONS)}.",
        )
    if plan.folder_tag not in FOLDER_TAGS:
        visible = [value or "none" for value in FOLDER_TAGS]
        raise RuleError(
            "INVALID_FOLDER",
            f"Folder must be one of {', '.join(visible)}.",
        )
    return RulePlan(
        sender=sender,
        display_name=plan.display_name.strip(),
        disposition=plan.disposition,
        folder_tag=plan.folder_tag,
        source_message_id=plan.source_message_id.strip().strip("<>"),
        example_subject=plan.example_subject.strip(),
    )


SCHEMA = """
CREATE TABLE rule_cases (
    rule_id TEXT PRIMARY KEY,
    sender TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('active', 'disabled')),
    first_recorded_at TEXT NOT NULL,
    last_recorded_at TEXT NOT NULL
);

CREATE TABLE rule_events (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    rule_id TEXT NOT NULL REFERENCES rule_cases(rule_id),
    action TEXT NOT NULL CHECK (action IN ('set', 'disable')),
    disposition TEXT CHECK (disposition IN ('now', 'archive', 'trash')),
    folder_tag TEXT CHECK (folder_tag IN ('', 'family', 'datax', 'hwc')),
    source_message_id TEXT NOT NULL,
    example_subject TEXT NOT NULL,
    recorded_at TEXT NOT NULL
);

CREATE INDEX rule_events_by_case ON rule_events(rule_id, sequence);
"""


def open_ledger(db_path: Path) -> sqlite3.Connection:
    try:
        db_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(db_path.parent, 0o700)
        conn = sqlite3.connect(db_path, timeout=5)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA busy_timeout = 5000")
        conn.execute("PRAGMA synchronous = FULL")
        version = int(conn.execute("PRAGMA user_version").fetchone()[0])
        if version == 0:
            with conn:
                conn.executescript(SCHEMA)
                conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
        elif version != SCHEMA_VERSION:
            conn.close()
            raise RuleError(
                "UNSUPPORTED_SCHEMA",
                f"Rule ledger schema is {version}; this command supports {SCHEMA_VERSION}.",
            )
        quick_check = str(conn.execute("PRAGMA quick_check").fetchone()[0])
        if quick_check != "ok":
            conn.close()
            raise RuleError("RULE_STORE_INVALID", f"Rule ledger check failed: {quick_check}")
        os.chmod(db_path, 0o600)
        return conn
    except RuleError:
        raise
    except (OSError, sqlite3.DatabaseError) as exc:
        raise RuleError("RULE_STORE_INVALID", f"Cannot open the rule ledger: {exc}") from exc


def _last_event(conn: sqlite3.Connection, rule_id: str) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT event_id, action, disposition, folder_tag, source_message_id,
               example_subject
          FROM rule_events
         WHERE rule_id = ?
         ORDER BY sequence DESC
         LIMIT 1
        """,
        (rule_id,),
    ).fetchone()


def _event_id(rule_id: str, previous: str, payload: dict[str, str]) -> str:
    material = json.dumps(
        {
            "schema_version": SCHEMA_VERSION,
            "rule_id": rule_id,
            "previous": previous,
            **payload,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return "event-" + hashlib.sha256(material).hexdigest()


def set_rule(
    conn: sqlite3.Connection,
    plan: RulePlan,
    *,
    recorded_at: str,
) -> tuple[str, bool]:
    """Append a reviewed judgment and activate its deterministic sender case."""

    plan = validate_plan(plan)
    rule_id = rule_id_for(plan.sender)
    with conn:
        existing = conn.execute(
            "SELECT state FROM rule_cases WHERE rule_id = ?", (rule_id,)
        ).fetchone()
        if existing is None or existing["state"] != "active":
            active_count = int(
                conn.execute(
                    "SELECT count(*) FROM rule_cases WHERE state = 'active'"
                ).fetchone()[0]
            )
            if active_count >= MAX_ACTIVE_RULES:
                raise RuleError(
                    "RULE_LIMIT_REACHED",
                    f"The {MAX_ACTIVE_RULES}-rule safety limit is reached; disable a rule first.",
                )

        last = _last_event(conn, rule_id)
        desired = (
            "set",
            plan.disposition,
            plan.folder_tag,
            plan.source_message_id,
            plan.example_subject,
        )
        current = None if last is None else (
            last["action"],
            last["disposition"],
            last["folder_tag"],
            last["source_message_id"],
            last["example_subject"],
        )
        if existing is not None and existing["state"] == "active" and current == desired:
            return rule_id, False

        conn.execute(
            """
            INSERT INTO rule_cases(
                rule_id, sender, display_name, state,
                first_recorded_at, last_recorded_at
            ) VALUES (?, ?, ?, 'active', ?, ?)
            ON CONFLICT(rule_id) DO UPDATE SET
                display_name = excluded.display_name,
                state = 'active',
                last_recorded_at = excluded.last_recorded_at
            """,
            (rule_id, plan.sender, plan.display_name, recorded_at, recorded_at),
        )
        payload = {
            "action": "set",
            "disposition": plan.disposition,
            "folder_tag": plan.folder_tag,
            "source_message_id": plan.source_message_id,
            "example_subject": plan.example_subject,
        }
        previous = "root" if last is None else str(last["event_id"])
        conn.execute(
            """
            INSERT INTO rule_events(
                event_id, rule_id, action, disposition, folder_tag,
                source_message_id, example_subject, recorded_at
            ) VALUES (?, ?, 'set', ?, ?, ?, ?, ?)
            """,
            (
                _event_id(rule_id, previous, payload),
                rule_id,
                plan.disposition,
                plan.folder_tag,
                plan.source_message_id,
                plan.example_subject,
                recorded_at,
            ),
        )
    return rule_id, True


def disable_rule(
    conn: sqlite3.Connection,
    sender: str,
    *,
    recorded_at: str,
) -> bool:
    sender = normalize_address(sender)
    rule_id = rule_id_for(sender)
    with conn:
        case = conn.execute(
            "SELECT state FROM rule_cases WHERE rule_id = ?", (rule_id,)
        ).fetchone()
        if case is None:
            raise RuleError("RULE_NOT_FOUND", f"No rule exists for {sender}.")
        if case["state"] == "disabled":
            return False
        last = _last_event(conn, rule_id)
        previous = "root" if last is None else str(last["event_id"])
        payload = {
            "action": "disable",
            "disposition": "",
            "folder_tag": "",
            "source_message_id": "",
            "example_subject": "",
        }
        conn.execute(
            """
            INSERT INTO rule_events(
                event_id, rule_id, action, disposition, folder_tag,
                source_message_id, example_subject, recorded_at
            ) VALUES (?, ?, 'disable', NULL, NULL, '', '', ?)
            """,
            (_event_id(rule_id, previous, payload), rule_id, recorded_at),
        )
        conn.execute(
            """
            UPDATE rule_cases
               SET state = 'disabled', last_recorded_at = ?
             WHERE rule_id = ?
            """,
            (recorded_at, rule_id),
        )
    return True


def active_rules(conn: sqlite3.Connection) -> list[ActiveRule]:
    rows = conn.execute(
        """
        SELECT c.rule_id, c.sender, c.display_name,
               e.disposition, e.folder_tag
          FROM rule_cases AS c
          JOIN rule_events AS e
            ON e.sequence = (
                SELECT max(latest.sequence)
                  FROM rule_events AS latest
                 WHERE latest.rule_id = c.rule_id
                   AND latest.action = 'set'
            )
         WHERE c.state = 'active'
         ORDER BY c.sender
        """
    ).fetchall()
    return [
        ActiveRule(
            rule_id=str(row["rule_id"]),
            sender=str(row["sender"]),
            display_name=str(row["display_name"]),
            disposition=str(row["disposition"]),
            folder_tag=str(row["folder_tag"] or ""),
        )
        for row in rows
    ]


def all_rule_rows(conn: sqlite3.Connection) -> list[sqlite3.Row]:
    return conn.execute(
        """
        SELECT c.sender, c.display_name, c.state, c.last_recorded_at,
               e.disposition, e.folder_tag,
               (SELECT count(*) FROM rule_events history
                 WHERE history.rule_id = c.rule_id) AS event_count
          FROM rule_cases AS c
          LEFT JOIN rule_events AS e
            ON e.sequence = (
                SELECT max(latest.sequence)
                  FROM rule_events AS latest
                 WHERE latest.rule_id = c.rule_id
                   AND latest.action = 'set'
            )
         ORDER BY c.state, c.sender
        """
    ).fetchall()


def _query_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def rule_operations(disposition: str, folder_tag: str) -> list[str]:
    operations = [f"+{folder_tag}"] if folder_tag else []
    if disposition == "now":
        operations += ["+inbox", "+queue", "-archive", "-trash"]
    elif disposition == "archive":
        operations += ["+archive", "-inbox", "-unread", "-queue", "-trash"]
    elif disposition == "trash":
        operations += ["+trash", "-inbox", "-unread", "-queue", "-archive"]
    else:
        raise RuleError("INVALID_DISPOSITION", f"Unknown handling: {disposition}")
    return _unique(operations)


def _run_notmuch(notmuch: str, args: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            [notmuch, *args],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        raise RuleError("NOTMUCH_UNAVAILABLE", f"Could not start notmuch: {exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "unknown error"
        raise RuleError("NOTMUCH_FAILED", detail)
    return result


def apply_active_rules(conn: sqlite3.Connection, notmuch: str) -> int:
    """Apply active rules in at most 12 idempotent tag operations."""

    grouped: dict[tuple[str, str], list[str]] = {}
    for rule in active_rules(conn):
        grouped.setdefault((rule.disposition, rule.folder_tag), []).append(rule.sender)

    for (disposition, folder_tag), senders in sorted(grouped.items()):
        clauses = " OR ".join(
            f"from:{_query_quote(sender)}" for sender in sorted(senders)
        )
        protection = " AND NOT tag:keep" if disposition in DESTRUCTIVE_DISPOSITIONS else ""
        query = f"tag:new{protection} AND ({clauses})"
        _run_notmuch(
            notmuch,
            ["tag", *rule_operations(disposition, folder_tag), "--", query],
        )
    return len(grouped)


def message_tags(notmuch: str, message_id: str) -> set[str]:
    if not message_id:
        return set()
    result = _run_notmuch(
        notmuch,
        ["search", "--format=text0", "--output=tags", "--", f"id:{_query_quote(message_id)}"],
    )
    return {tag for tag in result.stdout.split("\0") if tag}


def infer_folder(tags: set[str]) -> str:
    if "datax" in tags:
        return "datax"
    if "family" in tags:
        return "family"
    if tags.intersection({"hwc", "work", "office", "hwcmt", "proton-hwc"}):
        return "hwc"
    return ""


def apply_current(plan: RulePlan, notmuch: str) -> tuple[bool, str]:
    plan = validate_plan(plan)
    if not plan.source_message_id:
        return False, "The message has no Message-ID, so only the future rule was saved."
    exact = f"id:{_query_quote(plan.source_message_id)}"
    if plan.disposition in DESTRUCTIVE_DISPOSITIONS:
        kept = _run_notmuch(notmuch, ["count", "--", f"{exact} AND tag:keep"])
        try:
            if int(kept.stdout.strip() or "0") > 0:
                return False, "The current message is protected by keep and was not moved."
        except ValueError as exc:
            raise RuleError("NOTMUCH_INVALID_OUTPUT", "notmuch count returned invalid output") from exc
    _run_notmuch(
        notmuch,
        ["tag", *rule_operations(plan.disposition, plan.folder_tag), "--", exact],
    )
    return True, "The current message was updated."


def _tty() -> TextIO:
    try:
        return open("/dev/tty", "r+", encoding="utf-8", buffering=1)
    except OSError as exc:
        raise RuleError(
            "NO_TTY",
            "Interactive review needs a terminal; use mail-rule set for scripting.",
        ) from exc


def _ask_choice(tty: TextIO, prompt: str, choices: dict[str, str], default: str) -> str:
    while True:
        tty.write(prompt)
        answer = tty.readline()
        if answer == "":
            raise RuleError("REVIEW_CANCELLED", "Review terminal closed; no rule was saved.")
        key = answer.strip().lower() or default
        if key == "q":
            raise RuleError("REVIEW_CANCELLED", "No rule was saved.")
        if key in choices:
            return choices[key]
        tty.write("Choose one of the displayed keys, or q to cancel.\n")


def review_message(
    conn: sqlite3.Connection,
    notmuch: str,
    raw: bytes,
    *,
    recorded_at: str,
) -> None:
    context = parse_message(raw)
    tags = message_tags(notmuch, context.message_id)
    inferred = infer_folder(tags)
    folder_key = {"": "n", "family": "f", "datax": "d", "hwc": "h"}[inferred]
    tty = _tty()
    try:
        sender_label = (
            f"{context.display_name} <{context.sender}>"
            if context.display_name
            else context.sender
        )
        tty.write("\nFuture mail rule\n")
        tty.write("────────────────────────────────────────────────────────\n")
        tty.write(f"Sender:  {sender_label}\n")
        tty.write(f"Example: {context.subject[:100]}\n")
        tty.write("Match:   this exact email address only\n\n")
        tty.write("Permanent folder tag\n")
        tty.write("  [f] family   [d] datax   [h] hwc   [n] none\n")
        if inferred:
            tty.write(f"  Enter keeps the detected folder: {inferred}\n")
        else:
            tty.write("  Enter keeps no folder tag\n")
        folder = _ask_choice(
            tty,
            "Folder [Enter=detected, q=cancel]: ",
            {"f": "family", "d": "datax", "h": "hwc", "n": ""},
            folder_key,
        )

        tty.write("\nFuture handling\n")
        tty.write("  [n] now      show it for a decision\n")
        tty.write("  [a] archive  keep it, but remove it from now\n")
        tty.write("  [t] trash    move it to recoverable Trash\n")
        disposition = _ask_choice(
            tty,
            "Handling [Enter=now, q=cancel]: ",
            {"n": "now", "a": "archive", "t": "trash"},
            "n",
        )
        apply_now = _ask_choice(
            tty,
            "Apply this decision to the current message? [Y/n/q]: ",
            {"y": "yes", "n": "no"},
            "y",
        ) == "yes"

        target = folder or "no folder tag"
        tty.write("\nReview\n")
        tty.write(f"  Future mail from {context.sender}: {disposition}; {target}\n")
        tty.write(f"  Current message: {'apply now' if apply_now else 'leave unchanged'}\n")
        confirmed = _ask_choice(
            tty,
            "Save this rule? [y/N]: ",
            {"y": "yes", "n": "no"},
            "n",
        )
        if confirmed != "yes":
            raise RuleError("REVIEW_CANCELLED", "No rule was saved.")

        plan = RulePlan(
            sender=context.sender,
            display_name=context.display_name,
            disposition=disposition,
            folder_tag=folder,
            source_message_id=context.message_id,
            example_subject=context.subject,
        )
        _, changed = set_rule(conn, plan, recorded_at=recorded_at)
        tty.write("\nRule saved.\n" if changed else "\nThat rule was already current.\n")
        if apply_now:
            _, message = apply_current(plan, notmuch)
            tty.write(message + "\n")
        tty.write("Future matching mail will be handled during the next mail index.\n")
    finally:
        tty.close()


def print_rules(conn: sqlite3.Connection, out: TextIO = sys.stdout) -> None:
    rows = all_rule_rows(conn)
    if not rows:
        out.write("No operator mail rules.\n")
        return
    out.write("STATE     HANDLING  FOLDER   SENDER\n")
    out.write("────────  ────────  ───────  ─────────────────────────────\n")
    for row in rows:
        out.write(
            f"{str(row['state']):8}  {str(row['disposition']):8}  "
            f"{str(row['folder_tag'] or '-'):7}  {row['sender']}\n"
        )


def manage_rules(conn: sqlite3.Connection, *, recorded_at: str) -> None:
    rows = [row for row in all_rule_rows(conn) if row["state"] == "active"]
    if not rows:
        print("No active operator mail rules.")
        return
    print("\nActive future mail rules\n")
    for index, row in enumerate(rows, 1):
        folder = str(row["folder_tag"] or "no folder")
        print(f"{index:>3}. {row['sender']} → {row['disposition']}, {folder}")
    answer = input("\nEnter a number to disable it, or press Enter to close: ").strip()
    if not answer:
        return
    try:
        selected = int(answer)
    except ValueError as exc:
        raise RuleError("INVALID_SELECTION", "Enter a displayed rule number.") from exc
    if selected < 1 or selected > len(rows):
        raise RuleError("INVALID_SELECTION", "Enter a displayed rule number.")
    sender = str(rows[selected - 1]["sender"])
    confirm = input(f"Disable the rule for {sender}? [y/N]: ").strip().lower()
    if confirm != "y":
        print("No change.")
        return
    disable_rule(conn, sender, recorded_at=recorded_at)
    print(f"Disabled the future mail rule for {sender}.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mail-rule",
        description="Review and apply exact-sender mail rules.",
    )
    parser.add_argument("--db", required=True, type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--notmuch", required=True, help=argparse.SUPPRESS)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("review", help="review a rule from one RFC 822 message on stdin")
    commands.add_parser("apply-new", help="apply active rules to messages tagged new")
    commands.add_parser("list", help="list active and disabled rules")
    commands.add_parser("manage", help="interactively list and disable rules")

    set_cmd = commands.add_parser("set", help="set an exact-sender rule without aerc")
    set_cmd.add_argument("sender")
    set_cmd.add_argument("--name", default="")
    set_cmd.add_argument("--disposition", choices=DISPOSITIONS, default="now")
    set_cmd.add_argument(
        "--folder", choices=("none", "family", "datax", "hwc"), default="none"
    )
    set_cmd.add_argument("--message-id", default="")
    set_cmd.add_argument("--subject", default="")

    disable_cmd = commands.add_parser("disable", help="disable one exact-sender rule")
    disable_cmd.add_argument("sender")
    return parser


def main(argv: list[str] | None = None) -> int:
    os.umask(0o077)
    args = build_parser().parse_args(argv)
    try:
        conn = open_ledger(args.db)
        try:
            if args.command == "review":
                raw = sys.stdin.buffer.read(MAX_MESSAGE_BYTES + 1)
                review_message(conn, args.notmuch, raw, recorded_at=utc_now())
            elif args.command == "apply-new":
                groups = apply_active_rules(conn, args.notmuch)
                print(f"Applied {groups} operator rule group(s).")
            elif args.command == "list":
                print_rules(conn)
            elif args.command == "manage":
                manage_rules(conn, recorded_at=utc_now())
            elif args.command == "set":
                plan = RulePlan(
                    sender=args.sender,
                    display_name=args.name,
                    disposition=args.disposition,
                    folder_tag="" if args.folder == "none" else args.folder,
                    source_message_id=args.message_id,
                    example_subject=args.subject,
                )
                rule_id, changed = set_rule(conn, plan, recorded_at=utc_now())
                print(f"{'Saved' if changed else 'Unchanged'} {rule_id} for {plan.sender}.")
            elif args.command == "disable":
                changed = disable_rule(conn, args.sender, recorded_at=utc_now())
                print("Rule disabled." if changed else "Rule was already disabled.")
        finally:
            conn.close()
    except RuleError as exc:
        if exc.code == "REVIEW_CANCELLED":
            print(exc.message)
            return 0
        print(f"{exc.code}: {exc.message}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
