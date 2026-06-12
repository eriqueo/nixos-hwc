"""Parse/render the one-line todo.txt-style task dialect.

    "Buy lumber +shop @errand (A) due:2026-06-20 list:errands"
      -> summary="Buy lumber", categories=["+shop", "@errand"],
         priority=1, due=date(2026, 6, 20), list="errands"

The list: value is an unresolved name fragment — the app matches it against
real lists (case-insensitive exact, then unique prefix), so spaced list
names are reachable by prefix ("list:heartwood" -> "Heartwood Craft").

Categories keep their +/@ sigils so they round-trip through iCloud and read
well as tags in Apple Reminders (CATEGORIES survives the round-trip —
verified Phase A). Priority letters map (A)->1 ... (I)->9 (todoman: 1 is
highest, 0 is none). Rendering a Todo back produces the same one-line form;
a datetime due renders as its date (editing downgrades it to all-day).
"""

from __future__ import annotations

import re
from datetime import date, datetime, timedelta

PRI_LETTERS = "ABCDEFGHI"

_PRI_RE = re.compile(r"^\(([A-Za-z])\)$")
_DUE_RE = re.compile(r"^due:(.+)$", re.IGNORECASE)
_LIST_RE = re.compile(r"^list:(.+)$", re.IGNORECASE)


def parse(line: str) -> dict:
    """Parse a task line into {summary, categories, priority, due, list}."""
    summary_words: list[str] = []
    categories: list[str] = []
    priority = 0
    due: date | None = None
    list_name: str | None = None

    for tok in line.split():
        m = _PRI_RE.match(tok)
        if m:
            priority = min(ord(m.group(1).upper()) - ord("A") + 1, 9)
            continue
        m = _DUE_RE.match(tok)
        if m:
            parsed = _parse_due(m.group(1))
            if parsed is not None:
                due = parsed
                continue
        m = _LIST_RE.match(tok)
        if m:
            list_name = m.group(1)
            continue
        if len(tok) > 1 and tok[0] in "+@":
            categories.append(tok)
            continue
        summary_words.append(tok)

    return {
        "summary": " ".join(summary_words),
        "categories": categories,
        "priority": priority,
        "due": due,
        "list": list_name,
    }


def _parse_due(raw: str) -> date | None:
    raw = raw.strip().lower()
    if raw == "today":
        return date.today()
    if raw in ("tomorrow", "tom"):
        return date.today() + timedelta(days=1)
    try:
        return date.fromisoformat(raw)
    except ValueError:
        return None


def priority_letter(priority: int) -> str:
    if 1 <= priority <= 9:
        return PRI_LETTERS[priority - 1]
    return ""


def due_str(due) -> str:
    if due is None:
        return ""
    if isinstance(due, datetime):
        return due.astimezone().date().isoformat()
    return due.isoformat()


def render(todo) -> str:
    """Render a todoman Todo back to the one-line dialect (parse() inverse)."""
    parts = [todo.summary] if todo.summary else []
    parts.extend(todo.categories or [])
    if todo.priority:
        parts.append(f"({priority_letter(todo.priority)})")
    if todo.due:
        parts.append(f"due:{due_str(todo.due)}")
    # tokens can't hold spaces; spaced list names stay reachable by prefix
    if todo.list and todo.list.name and " " not in todo.list.name:
        parts.append(f"list:{todo.list.name}")
    return " ".join(parts)
