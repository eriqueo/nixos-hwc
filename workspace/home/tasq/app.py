#!/usr/bin/env python3
"""tasq — keyboard-driven VTODO task TUI over the Phase A vdir.

Layout (tuxedo-style): top header bar (list · count · sort · filters),
FilterSidebar (LISTS / PROJECTS / CONTEXTS with counts) | TaskTable |
DetailPanel, Footer. All data access goes through Store (store.py); the
one-line task dialect lives in model_map.py.

Colors come from the system theme: the HM module exports the materialized
hwc.home.theme.colors palette as TASQ_PALETTE (JSON); roles are derived
below and exposed to theme.tcss as $tq-* CSS variables. No hex literals
live in the stylesheet — switching the system palette restyles tasq.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from collections import Counter
from datetime import date, datetime

from rich.text import Text
from textual import on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal
from textual.widgets import Footer, Static
from textual.widgets.option_list import Option

import model_map
from store import SORT_MODES, Store
from widgets import (
    ConfirmModal,
    DetailPanel,
    FilterSidebar,
    HelpModal,
    LineModal,
    TaskTable,
)

DEFAULT_GLOB = "~/.local/share/vdirsyncer/tasks/*"
DEFAULT_CACHE = "~/.cache/tasq/cache.sqlite3"
DEFAULT_LIST = "Reminders"

ALL_LISTS = "All"

# Fallback = the hwc palette (domains/home/theme/palettes/hwc.nix), so the
# app still looks right when run outside the HM wrapper.
_FALLBACK_PALETTE = {
    "bg0": "1d2021", "bg1": "282828", "bg2": "2c3338", "bg3": "32373c",
    "fg0": "ebdbb2", "fg1": "d5c4a1", "fg2": "a7aaad", "fg3": "50626f",
    "accent": "d08770", "info": "5e81ac",
    "success": "a3be8c", "successDim": "8aab78",
    "warning": "cf995f", "warningBright": "fcbb74",
    "error": "bf616a",
    "selection": "434c5e", "selectionFg": "ebdbb2",
    "border": "32373c", "borderDim": "2c3338", "borderBright": "cf995f",
}


def _load_palette() -> dict[str, str]:
    pal = dict(_FALLBACK_PALETTE)
    raw = os.environ.get("TASQ_PALETTE")
    if raw:
        try:
            pal.update(
                {k: v for k, v in json.loads(raw).items() if isinstance(v, str)}
            )
        except (ValueError, AttributeError):
            pass
    return {k: v if v.startswith("#") else f"#{v}" for k, v in pal.items()}


PAL = _load_palette()

# Semantic roles used by cell rendering and (as $tq-*) by theme.tcss.
ROLE = {
    "bg": PAL["bg1"],
    "bg_dark": PAL["bg0"],
    "bg_panel": PAL["bg2"],
    "bg_hi": PAL["bg3"],
    "fg": PAL["fg1"],
    "fg_bright": PAL["fg0"],
    "fg_dim": PAL["fg2"],
    "muted": PAL["fg3"],
    "accent": PAL["accent"],
    "blue": PAL["info"],
    "green": PAL["success"],
    "aqua": PAL["successDim"],
    "orange": PAL["warning"],
    "orange_bright": PAL["warningBright"],
    "red": PAL["error"],
    "selection": PAL["selection"],
    "selection_fg": PAL["selectionFg"],
    "border": PAL["border"],
    "border_dim": PAL["borderDim"],
    "border_bright": PAL["borderBright"],
}

SIDEBAR_LABEL_W = 17


def _cat_style(cat: str) -> str:
    if cat.startswith("+"):
        return ROLE["green"]
    if cat.startswith("@"):
        return ROLE["orange"]
    return ROLE["aqua"]


def _date_str(d) -> str:
    if d is None:
        return ""
    # todoman's cache hands last_modified back as a raw epoch float
    if isinstance(d, (int, float)):
        d = datetime.fromtimestamp(d)
    if isinstance(d, datetime):
        return d.astimezone().strftime("%Y-%m-%d")
    return d.isoformat()


def _due_text(todo) -> Text:
    if not todo.due:
        return Text("")
    d = todo.due
    if isinstance(d, datetime):
        d = d.astimezone().date()
    label = model_map.due_str(todo.due)
    if todo.is_completed:
        return Text(label, style=ROLE["muted"])
    today = date.today()
    if d < today:
        return Text(label, style=f"bold {ROLE['red']}")
    if d == today:
        return Text(label, style=ROLE["orange"])
    return Text(label, style=ROLE["fg_dim"])


_PRI_STYLE = {
    1: f"bold {ROLE['red']}",
    2: f"bold {ROLE['orange']}",
    3: f"bold {ROLE['orange_bright']}",
}


class TasqApp(App):
    TITLE = "tasq"
    CSS_PATH = "theme.tcss"

    BINDINGS = [
        Binding("a", "add", "Add"),
        Binding("e", "edit", "Edit"),
        Binding("x", "toggle_done", "Done"),
        Binding("space", "toggle_done", "Done", show=False),
        Binding("d", "delete", "Del"),
        Binding("p", "cycle_priority", "Pri", show=False),
        Binding("N", "new_list", "New list", show=False),
        Binding("slash", "filter_grep", "Filter"),
        Binding("plus", "filter_project", "+proj", show=False),
        Binding("at", "filter_context", "@ctx", show=False),
        Binding("escape", "clear_filters", "Clear", show=False),
        Binding("s", "cycle_sort", "Sort"),
        Binding("c", "toggle_completed", "±Done", show=False),
        Binding("l", "next_list", "List"),
        Binding("L", "prev_list", "Prev list", show=False),
        Binding("J", "sidebar_next", "Sidebar ↓", show=False),
        Binding("K", "sidebar_prev", "Sidebar ↑", show=False),
        Binding("left_square_bracket", "toggle_sidebar", "Sidebar", show=False),
        Binding("right_square_bracket", "toggle_detail", "Detail", show=False),
        Binding("g", "go_top", "Top", show=False),
        Binding("G", "go_bottom", "Bottom", show=False),
        Binding("r", "reload", "Reload"),
        Binding("R", "sync", "Sync"),
        Binding("C", "calendar", "Cal"),
        Binding("question_mark", "help", "Help"),
        Binding("q", "quit", "Quit"),
    ]

    def __init__(self, store: Store) -> None:
        super().__init__()
        self.store = store
        self.current_list: str | None = None  # None = all lists
        self.grep: str | None = None
        self.category: str | None = None
        self.sort_mode: str = SORT_MODES[0]
        self.show_completed = False
        self._rows = []  # Todos parallel to table rows
        self._sidebar_payloads = []  # parallel to sidebar options
        self._sidebar_pos: int | None = None  # explicit J/K position

    def get_css_variables(self) -> dict[str, str]:
        css_vars = super().get_css_variables()
        css_vars.update(
            {f"tq-{name.replace('_', '-')}": color for name, color in ROLE.items()}
        )
        return css_vars

    # -- layout ---------------------------------------------------------------

    def compose(self) -> ComposeResult:
        yield Static(id="header")
        with Horizontal(id="body"):
            yield FilterSidebar(id="sidebar")
            yield TaskTable(id="table")
            yield DetailPanel(id="detail")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one(TaskTable)
        table.cursor_type = "row"
        table.zebra_stripes = False
        table.add_columns(" ", "P", "Summary", "Due", "Tags", "List")
        self.refresh_tasks()
        table.focus()

    # -- data → widgets ---------------------------------------------------------

    def _list_names(self) -> list[str]:
        return [tl.name for tl in self.store.lists()]

    def _refresh_sidebar(self) -> None:
        sidebar = self.query_one(FilterSidebar)
        active = self.store.todos(show_completed=False)
        list_counts = Counter(t.list.name for t in active)
        projects: Counter = Counter()
        contexts: Counter = Counter()
        other: Counter = Counter()
        for t in active:
            for cat in t.categories or []:
                if cat.startswith("+"):
                    projects[cat] += 1
                elif cat.startswith("@"):
                    contexts[cat] += 1
                else:
                    other[cat] += 1

        options: list[Option] = []
        payloads: list[tuple | None] = []

        def header(label: str, color: str) -> None:
            options.append(Option(Text(f" {label}", style=f"bold {color}"), disabled=True))
            payloads.append(None)

        def gap() -> None:
            options.append(Option(" ", disabled=True))
            payloads.append(None)

        def entry(label: str, count: int, color: str, payload: tuple) -> None:
            selected = payload == (
                ("cat", self.category) if self.category else ("list", self.current_list)
            )
            text = Text()
            text.append(f"  {label[:SIDEBAR_LABEL_W]:<{SIDEBAR_LABEL_W}}",
                        style=f"bold {color}" if selected else color)
            text.append(f"{count:>4}", style=ROLE["muted"])
            options.append(Option(text))
            payloads.append(payload)

        header("LISTS", ROLE["blue"])
        entry(ALL_LISTS, sum(list_counts.values()), ROLE["fg"], ("list", None))
        for name in self._list_names():
            entry(name, list_counts.get(name, 0), ROLE["fg"], ("list", name))
        if projects:
            gap()
            header("PROJECTS", ROLE["green"])
            for name, n in sorted(projects.items()):
                entry(name, n, ROLE["green"], ("cat", name))
        if contexts:
            gap()
            header("CONTEXTS", ROLE["orange"])
            for name, n in sorted(contexts.items()):
                entry(name, n, ROLE["orange"], ("cat", name))
        if other:
            gap()
            header("TAGS", ROLE["aqua"])
            for name, n in sorted(other.items()):
                entry(name, n, ROLE["aqua"], ("cat", name))

        sidebar.clear_options()
        sidebar.add_options(options)
        self._sidebar_payloads = payloads

        if (
            self._sidebar_pos is not None
            and 0 <= self._sidebar_pos < len(payloads)
            and payloads[self._sidebar_pos] is not None
        ):
            sidebar.highlighted = self._sidebar_pos
        else:
            target = ("cat", self.category) if self.category else ("list", self.current_list)
            if target in payloads:
                sidebar.highlighted = payloads.index(target)

    def _cells(self, todo) -> tuple:
        done = (
            Text("☑", style=ROLE["green"])
            if todo.is_completed
            else Text("☐", style=ROLE["muted"])
        )
        pri = Text(
            model_map.priority_letter(todo.priority),
            style=_PRI_STYLE.get(todo.priority, ROLE["muted"]),
        )
        summary = Text(
            todo.summary,
            style=f"strike {ROLE['muted']}" if todo.is_completed else ROLE["fg"],
        )
        tags = Text()
        for i, cat in enumerate(todo.categories or []):
            if i:
                tags.append(" ")
            tags.append(cat, style=_cat_style(cat))
        list_name = Text(todo.list.name if todo.list else "", style=ROLE["muted"])
        return (done, pri, summary, _due_text(todo), tags, list_name)

    def refresh_tasks(self, keep_cursor: bool = True) -> None:
        table = self.query_one(TaskTable)
        cur_uid = None
        if keep_cursor and self._rows and 0 <= table.cursor_row < len(self._rows):
            cur_uid = self._rows[table.cursor_row].uid

        self._rows = self.store.todos(
            list_name=self.current_list,
            category=self.category,
            grep=self.grep,
            sort=self.sort_mode,
            show_completed=self.show_completed,
        )
        table.clear()
        for todo in self._rows:
            table.add_row(*self._cells(todo))

        if cur_uid is not None:
            for i, todo in enumerate(self._rows):
                if todo.uid == cur_uid:
                    table.move_cursor(row=i)
                    break
        self._refresh_sidebar()
        self._update_header()
        self._update_detail()

    def _update_header(self) -> None:
        parts = [
            f"[bold {ROLE['blue']}]tasq[/]",
            f"[{ROLE['accent']}]{self.current_list or ALL_LISTS}[/]",
            f"[{ROLE['fg']}]{len(self._rows)} task{'s' if len(self._rows) != 1 else ''}[/]",
            f"[{ROLE['muted']}]sort:{self.sort_mode}[/]",
        ]
        if self.show_completed:
            parts.append(f"[{ROLE['muted']}]showing:all[/]")
        if self.grep:
            parts.append(f"[{ROLE['orange_bright']}]/{self.grep}[/]")
        if self.category:
            parts.append(f"[{_cat_style(self.category)}]{self.category}[/]")
        self.query_one("#header", Static).update(
            "  " + f" [{ROLE['muted']}]·[/] ".join(parts)
        )

    def _update_detail(self) -> None:
        panel = self.query_one(DetailPanel)
        todo = self._selected()
        if todo is None:
            panel.update(Text(" no task selected", style=ROLE["muted"]))
            return

        text = Text()
        text.append(" DETAIL\n\n", style=f"bold {ROLE['blue']}")

        def row(label: str, value, style: str = ROLE["fg"]) -> None:
            text.append(f" {label:<10}", style=ROLE["muted"])
            if isinstance(value, Text):
                text.append_text(value)
            else:
                text.append(str(value), style=style)
            text.append("\n")

        letter = model_map.priority_letter(todo.priority)
        row("priority", f"({letter})" if letter else "—",
            _PRI_STYLE.get(todo.priority, ROLE["fg"]))
        row("status", todo.status,
            ROLE["green"] if todo.is_completed else ROLE["fg"])
        row("due", _date_str(todo.due) or "—",
            _due_text(todo).style if todo.due else ROLE["fg"])
        row("created", _date_str(todo.created_at) or "—")
        row("modified", _date_str(todo.last_modified) or "—")
        row("list", todo.list.name if todo.list else "—", ROLE["accent"])
        if todo.rrule:
            row("repeats", todo.rrule.lower(), ROLE["aqua"])

        cats = todo.categories or []
        projects = [c for c in cats if c.startswith("+")]
        contexts = [c for c in cats if c.startswith("@")]
        tags = [c for c in cats if not c.startswith(("+", "@"))]
        row("projects", " ".join(projects) or "—", ROLE["green"])
        row("contexts", " ".join(contexts) or "—", ROLE["orange"])
        if tags:
            row("tags", " ".join(tags), ROLE["aqua"])

        text.append("\n RAW\n\n", style=f"bold {ROLE['blue']}")
        text.append(f" {model_map.render(todo)}\n", style=ROLE["fg_dim"])
        if todo.description:
            text.append("\n NOTES\n\n", style=f"bold {ROLE['blue']}")
            text.append(f" {todo.description}\n", style=ROLE["fg_dim"])
        panel.update(text)

    def _selected(self):
        table = self.query_one(TaskTable)
        if self._rows and 0 <= table.cursor_row < len(self._rows):
            return self._rows[table.cursor_row]
        return None

    def _target_list(self):
        name = self.current_list or DEFAULT_LIST
        tl = self.store.list_named(name)
        if tl is None:
            lists = self.store.lists()
            tl = lists[0] if lists else None
        return tl

    # -- events -------------------------------------------------------------------

    @on(FilterSidebar.OptionSelected)
    def _sidebar_selected(self, event: FilterSidebar.OptionSelected) -> None:
        if not (0 <= event.option_index < len(self._sidebar_payloads)):
            return
        payload = self._sidebar_payloads[event.option_index]
        if payload is None:
            return
        self._sidebar_pos = event.option_index
        kind, value = payload
        if kind == "list":
            self.current_list = value
        else:  # category filter; selecting it again clears
            self.category = None if self.category == value else value
        self.refresh_tasks(keep_cursor=False)
        self.query_one(TaskTable).focus()

    def _sidebar_step(self, step: int) -> None:
        """J/K: move the sidebar selection and activate it (aerc-style),
        without leaving the task table."""
        selectable = [
            i for i, p in enumerate(self._sidebar_payloads) if p is not None
        ]
        if not selectable:
            return
        cur = self._sidebar_pos
        if cur not in selectable:
            target = (
                ("cat", self.category) if self.category
                else ("list", self.current_list)
            )
            cur = (
                self._sidebar_payloads.index(target)
                if target in self._sidebar_payloads
                else selectable[0]
            )
        nxt = selectable[(selectable.index(cur) + step) % len(selectable)]
        self._sidebar_pos = nxt
        kind, value = self._sidebar_payloads[nxt]
        if kind == "list":
            self.current_list = value
            self.category = None
        else:
            self.category = value
        self.refresh_tasks(keep_cursor=False)

    def action_sidebar_next(self) -> None:
        self._sidebar_step(1)

    def action_sidebar_prev(self) -> None:
        self._sidebar_step(-1)

    @on(TaskTable.RowHighlighted)
    def _row_highlighted(self, _event: TaskTable.RowHighlighted) -> None:
        self._update_detail()

    # -- task actions -------------------------------------------------------------

    def action_add(self) -> None:
        target = self._target_list()
        if target is None:
            self.notify("no task lists found in the vdir", severity="error")
            return

        def done(line: str | None) -> None:
            if not line or not line.strip():
                return
            fields = model_map.parse(line)
            if not fields["summary"]:
                self.notify("task needs a summary", severity="warning")
                return
            self.store.add(
                fields["summary"],
                todo_list=target,
                categories=fields["categories"],
                priority=fields["priority"],
                due=fields["due"],
            )
            self.refresh_tasks()
            self.notify(f"added to {target.name}")

        self.push_screen(
            LineModal(
                f"New task → {target.name}",
                placeholder="summary +project @context (A) due:YYYY-MM-DD",
            ),
            done,
        )

    def action_edit(self) -> None:
        todo = self._selected()
        if todo is None:
            return

        def done(line: str | None) -> None:
            if not line or not line.strip():
                return
            fields = model_map.parse(line)
            if not fields["summary"]:
                self.notify("task needs a summary", severity="warning")
                return
            self.store.edit(
                todo,
                summary=fields["summary"],
                categories=fields["categories"],
                priority=fields["priority"],
                due=fields["due"],
            )
            self.refresh_tasks()
            self.notify("saved")

        self.push_screen(LineModal("Edit task", value=model_map.render(todo)), done)

    def action_toggle_done(self) -> None:
        todo = self._selected()
        if todo is None:
            return
        self.store.toggle_done(todo)
        self.refresh_tasks()
        self.notify("reopened" if not todo.is_completed else "completed ✓")

    def action_delete(self) -> None:
        todo = self._selected()
        if todo is None:
            return

        def done(confirmed: bool | None) -> None:
            if confirmed:
                self.store.delete(todo)
                self.refresh_tasks()
                self.notify("deleted")

        self.push_screen(ConfirmModal(f"Delete '{todo.summary}'?"), done)

    def action_cycle_priority(self) -> None:
        todo = self._selected()
        if todo is None:
            return
        nxt = (todo.priority + 1) % 4 if todo.priority in (0, 1, 2, 3) else 0
        self.store.edit(todo, priority=nxt)
        self.refresh_tasks()

    def action_new_list(self) -> None:
        def done(name: str | None) -> None:
            if not name or not name.strip():
                return
            name = name.strip()
            if self.store.list_named(name):
                self.notify(f"list '{name}' already exists", severity="warning")
                return
            self.store.create_list(name)
            self.store.reload()
            self.refresh_tasks()
            self.notify(
                f"list '{name}' created — LOCAL-ONLY. To get a phone-synced "
                "list, create it in Apple Reminders instead (see walkthrough).",
                timeout=10,
            )

        self.push_screen(
            LineModal("New list (local-only — phone lists: create in Reminders)",
                      placeholder="list name"),
            done,
        )

    # -- filters / sort / view -----------------------------------------------------

    def action_filter_grep(self) -> None:
        def done(value: str | None) -> None:
            if value is None:
                return
            self.grep = value.strip() or None
            self.refresh_tasks(keep_cursor=False)

        self.push_screen(
            LineModal("Filter summaries (empty clears)", value=self.grep or ""), done
        )

    def _filter_category(self, sigil: str, label: str) -> None:
        current = self.category if (self.category or "").startswith(sigil) else ""

        def done(value: str | None) -> None:
            if value is None:
                return
            value = value.strip()
            if not value:
                self.category = None
            else:
                self.category = value if value.startswith(sigil) else sigil + value
            self.refresh_tasks(keep_cursor=False)

        self.push_screen(
            LineModal(f"Filter by {label} (empty clears)", value=current), done
        )

    def action_filter_project(self) -> None:
        self._filter_category("+", "project (+name)")

    def action_filter_context(self) -> None:
        self._filter_category("@", "context (@name)")

    def action_clear_filters(self) -> None:
        if self.grep or self.category:
            self.grep = None
            self.category = None
            self._sidebar_pos = None
            self.refresh_tasks(keep_cursor=False)

    def action_cycle_sort(self) -> None:
        idx = SORT_MODES.index(self.sort_mode)
        self.sort_mode = SORT_MODES[(idx + 1) % len(SORT_MODES)]
        self.refresh_tasks()

    def action_toggle_completed(self) -> None:
        self.show_completed = not self.show_completed
        self.refresh_tasks(keep_cursor=False)

    def action_toggle_sidebar(self) -> None:
        sidebar = self.query_one(FilterSidebar)
        sidebar.display = not sidebar.display

    def action_toggle_detail(self) -> None:
        panel = self.query_one(DetailPanel)
        panel.display = not panel.display

    # -- lists ------------------------------------------------------------------

    def _cycle_list(self, step: int) -> None:
        names: list[str | None] = [None, *self._list_names()]
        idx = names.index(self.current_list) if self.current_list in names else 0
        self.current_list = names[(idx + step) % len(names)]
        self._sidebar_pos = None
        self.refresh_tasks(keep_cursor=False)

    def action_next_list(self) -> None:
        self._cycle_list(1)

    def action_prev_list(self) -> None:
        self._cycle_list(-1)

    # -- navigation ----------------------------------------------------------------

    def action_go_top(self) -> None:
        self.query_one(TaskTable).move_cursor(row=0)

    def action_go_bottom(self) -> None:
        table = self.query_one(TaskTable)
        if table.row_count:
            table.move_cursor(row=table.row_count - 1)

    # -- reload / sync / calendar ------------------------------------------------------

    def action_reload(self) -> None:
        self.store.reload()
        self.refresh_tasks()
        self.notify("reloaded from vdir")

    def action_sync(self) -> None:
        self.notify("syncing tasks…")
        self._sync_worker()

    @work(thread=True, exclusive=True, group="sync")
    def _sync_worker(self) -> None:
        code, out = self.store.sync()
        self.call_from_thread(self._sync_done, code, out)

    def _sync_done(self, code: int, out: str) -> None:
        if code == 0:
            self.store.reload()
            self.refresh_tasks()
            self.notify("sync ok ✓")
        else:
            self.notify(f"sync failed ({code}): {out[-300:]}", severity="error", timeout=10)

    def action_calendar(self) -> None:
        """Suspend the TUI and run khal interactive; resume on quit."""
        if shutil.which("khal") is None:
            self.notify("khal not found on PATH", severity="error")
            return
        try:
            with self.suspend():
                subprocess.call(["khal", "interactive"])
        except Exception as exc:
            self.notify(f"could not suspend for khal: {exc}", severity="error")
            return
        self.refresh_tasks()

    def action_help(self) -> None:
        self.push_screen(HelpModal())


def main() -> None:
    glob_path = os.environ.get("TASQ_PATH", DEFAULT_GLOB)
    cache_path = os.environ.get("TASQ_CACHE", DEFAULT_CACHE)
    try:
        store = Store([glob_path], cache_path)
    except Exception as exc:
        print(f"tasq: {exc}", file=sys.stderr)
        raise SystemExit(1)
    TasqApp(store).run()


if __name__ == "__main__":
    main()
