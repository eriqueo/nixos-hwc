#!/usr/bin/env python3
"""tasq — keyboard-driven VTODO task TUI over the Phase A vdir.

Layout (calcurse-style): ListSidebar | TaskTable / StatusBar, Footer.
All data access goes through Store (store.py); the one-line task dialect
lives in model_map.py. Run via the HM `tasq` wrapper (sets TASQ_PATH /
TASQ_CACHE), or directly — the defaults below match the Phase A backend.
"""

from __future__ import annotations

import os
import sys
from datetime import date, datetime

from rich.text import Text
from textual import on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.widgets import Footer

import model_map
from store import SORT_MODES, Store
from widgets import (
    ConfirmModal,
    HelpModal,
    LineModal,
    ListSidebar,
    StatusBar,
    TaskTable,
)

DEFAULT_GLOB = "~/.local/share/vdirsyncer/tasks/*"
DEFAULT_CACHE = "~/.cache/tasq/cache.sqlite3"
DEFAULT_LIST = "Reminders"

ALL_LISTS = "All"

# gruvbox accents for cell rendering (matches theme.tcss)
C_RED = "#fb4934"
C_ORANGE = "#fe8019"
C_YELLOW = "#fabd2f"
C_GREEN = "#b8bb26"
C_AQUA = "#8ec07c"
C_GRAY = "#928374"


def _due_text(todo) -> Text:
    if not todo.due:
        return Text("")
    d = todo.due
    if isinstance(d, datetime):
        d = d.astimezone().date()
    label = model_map.due_str(todo.due)
    if todo.is_completed:
        return Text(label, style=C_GRAY)
    today = date.today()
    if d < today:
        return Text(label, style=f"bold {C_RED}")
    if d == today:
        return Text(label, style=C_YELLOW)
    return Text(label)


_PRI_STYLE = {1: f"bold {C_RED}", 2: f"bold {C_ORANGE}", 3: f"bold {C_YELLOW}"}


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
        Binding("slash", "filter_grep", "Filter"),
        Binding("plus", "filter_project", "+proj", show=False),
        Binding("at", "filter_context", "@ctx", show=False),
        Binding("escape", "clear_filters", "Clear", show=False),
        Binding("s", "cycle_sort", "Sort"),
        Binding("c", "toggle_completed", "±Done", show=False),
        Binding("l", "next_list", "List"),
        Binding("L", "prev_list", "Prev list", show=False),
        Binding("g", "go_top", "Top", show=False),
        Binding("G", "go_bottom", "Bottom", show=False),
        Binding("r", "reload", "Reload"),
        Binding("R", "sync", "Sync"),
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

    # -- layout ---------------------------------------------------------------

    def compose(self) -> ComposeResult:
        with Horizontal():
            yield ListSidebar(id="sidebar")
            with Vertical(id="main"):
                yield TaskTable(id="table")
                yield StatusBar(id="status")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one(TaskTable)
        table.cursor_type = "row"
        table.zebra_stripes = True
        table.add_columns(" ", "P", "Summary", "Due", "Tags", "List")
        self._refresh_sidebar()
        self.refresh_tasks()
        table.focus()

    # -- data → widgets ---------------------------------------------------------

    def _list_names(self) -> list[str]:
        return [tl.name for tl in self.store.lists()]

    def _refresh_sidebar(self) -> None:
        sidebar = self.query_one(ListSidebar)
        sidebar.clear_options()
        names = [ALL_LISTS, *self._list_names()]
        sidebar.add_options(names)
        target = self.current_list if self.current_list in names else ALL_LISTS
        sidebar.highlighted = names.index(target)

    def _cells(self, todo) -> tuple:
        done = (
            Text("☑", style=C_GREEN)
            if todo.is_completed
            else Text("☐", style=C_GRAY)
        )
        pri = Text(
            model_map.priority_letter(todo.priority),
            style=_PRI_STYLE.get(todo.priority, C_GRAY),
        )
        summary = Text(
            todo.summary,
            style=f"strike {C_GRAY}" if todo.is_completed else "",
        )
        tags = Text(" ".join(todo.categories or []), style=C_AQUA)
        list_name = Text(todo.list.name if todo.list else "", style=C_GRAY)
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
        self._update_status()

    def _update_status(self) -> None:
        parts = [
            f"[{C_YELLOW}]{self.current_list or ALL_LISTS}[/]",
            f"sort:{self.sort_mode}",
            "showing:all" if self.show_completed else "showing:active",
        ]
        if self.grep:
            parts.append(f"/{self.grep}")
        if self.category:
            parts.append(f"cat:{self.category}")
        parts.append(f"{len(self._rows)} task{'s' if len(self._rows) != 1 else ''}")
        self.query_one(StatusBar).update(" · ".join(parts))

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

    # -- sidebar events ----------------------------------------------------------

    @on(ListSidebar.OptionSelected)
    def _list_selected(self, event: ListSidebar.OptionSelected) -> None:
        name = str(event.option.prompt)
        self.current_list = None if name == ALL_LISTS else name
        self.refresh_tasks(keep_cursor=False)
        self.query_one(TaskTable).focus()

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
            self.refresh_tasks(keep_cursor=False)

    def action_cycle_sort(self) -> None:
        idx = SORT_MODES.index(self.sort_mode)
        self.sort_mode = SORT_MODES[(idx + 1) % len(SORT_MODES)]
        self.refresh_tasks()

    def action_toggle_completed(self) -> None:
        self.show_completed = not self.show_completed
        self.refresh_tasks(keep_cursor=False)

    # -- lists ------------------------------------------------------------------

    def _cycle_list(self, step: int) -> None:
        names: list[str | None] = [None, *self._list_names()]
        idx = names.index(self.current_list) if self.current_list in names else 0
        self.current_list = names[(idx + step) % len(names)]
        self._refresh_sidebar()
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

    # -- reload / sync ---------------------------------------------------------------

    def action_reload(self) -> None:
        self.store.reload()
        self._refresh_sidebar()
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
            self._refresh_sidebar()
            self.refresh_tasks()
            self.notify("sync ok ✓")
        else:
            self.notify(f"sync failed ({code}): {out[-300:]}", severity="error", timeout=10)

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
