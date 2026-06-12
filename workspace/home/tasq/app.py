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
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta

from rich import box as rich_box
from rich.table import Table as RichTable
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
    LeaderMenu,
    LineModal,
    TaskTable,
    WeekStrip,
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
        Binding("space", "leader", "Leader"),
        Binding("d", "delete", "Del"),
        Binding("p", "cycle_priority", "Pri", show=False),
        Binding("N", "new_list", "New list", show=False),
        Binding("L", "lists_menu", "Lists", show=False),
        Binding("P", "projects_menu", "Projects", show=False),
        Binding("C", "contexts_menu", "Contexts", show=False),
        Binding("slash", "filter_grep", "Filter"),
        Binding("plus", "filter_project", "+proj", show=False),
        Binding("at", "filter_context", "@ctx", show=False),
        Binding("escape", "clear_filters", "Clear", show=False),
        Binding("s", "cycle_sort", "Sort"),
        Binding("c", "toggle_completed", "±Done", show=False),
        Binding("l", "next_list", "List"),
        Binding("ctrl+j", "sidebar_next", "Sidebar ↓", show=False),
        Binding("ctrl+k", "sidebar_prev", "Sidebar ↑", show=False),
        Binding("left_square_bracket", "toggle_sidebar", "Sidebar", show=False),
        Binding("right_square_bracket", "toggle_detail", "Detail", show=False),
        Binding("w", "toggle_week", "Week"),
        Binding("g", "go_top", "Top", show=False),
        Binding("G", "go_bottom", "Bottom", show=False),
        Binding("r", "reload", "Reload"),
        Binding("R", "sync", "Sync"),
        Binding("K", "calendar", "Cal"),
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
        self._week_events: list[list[dict]] | None = None  # khal, today..+6

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
        yield WeekStrip(id="week")
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one(TaskTable)
        table.cursor_type = "row"
        table.zebra_stripes = False
        table.add_columns(" ", "P", "Summary", "Due", "Tags", "List")
        self.refresh_tasks()
        self._fetch_week_events()
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
        self._update_week()

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

    # -- week strip -----------------------------------------------------------

    def _fetch_week_events(self) -> None:
        if self.query_one(WeekStrip).display:
            self._khal_worker()

    @work(thread=True, exclusive=True, group="khal")
    def _khal_worker(self) -> None:
        events = self.store.week_events(days=7)
        self.call_from_thread(self._set_week_events, events)

    def _set_week_events(self, events: list[list[dict]] | None) -> None:
        self._week_events = events
        self._update_week()

    def _update_week(self) -> None:
        strip = self.query_one(WeekStrip)
        if not strip.display:
            return
        today = date.today()
        days = [today + timedelta(days=i) for i in range(7)]
        events = self._week_events or [[] for _ in days]

        overdue = []
        tasks_by_day: dict[date, list] = defaultdict(list)
        for t in self.store.todos(show_completed=False):
            if not t.due:
                continue
            d = t.due.astimezone().date() if isinstance(t.due, datetime) else t.due
            if d < today:
                overdue.append((d, t))
            elif d <= days[-1]:
                tasks_by_day[d].append(t)

        grid = RichTable(
            box=rich_box.SIMPLE_HEAD,
            expand=True,
            padding=(0, 1),
            pad_edge=False,
            show_edge=False,
        )
        for d in days:
            style = f"bold {ROLE['accent']}" if d == today else f"bold {ROLE['blue']}"
            grid.add_column(
                Text(d.strftime("%a %d"), style=style),
                ratio=1, no_wrap=True, overflow="ellipsis",
            )

        cols: list[list[Text]] = []
        for i, d in enumerate(days):
            lines: list[Text] = []
            if i == 0:
                for od, t in sorted(
                    overdue,
                    key=lambda x: (x[0], x[1].priority or 10, x[1].summary.lower()),
                ):
                    lines.append(Text(
                        f"! {t.summary} ({od.strftime('%m-%d')})",
                        style=f"bold {ROLE['red']}",
                    ))
            for ev in events[i] if i < len(events) else []:
                title = ev.get("title", "")
                if ev.get("all-day") == "True":
                    lines.append(Text(f"◆ {title}", style=ROLE["blue"]))
                else:
                    start = ev.get("start", "")
                    hhmm = start[-5:] if ":" in start[-5:] else ""
                    lines.append(Text(f"◆ {hhmm} {title}".strip(), style=ROLE["blue"]))
            def _pri(t):
                return (t.priority or 10, t.summary.lower())
            for t in sorted(tasks_by_day.get(d, []), key=_pri):
                lines.append(Text(
                    f"☐ {t.summary}",
                    style=_PRI_STYLE.get(t.priority, ROLE["fg"]),
                ))
            cols.append(lines)

        height = min(max((len(c) for c in cols), default=0), 6)
        height = max(height, 1)
        for r in range(height):
            row = []
            for c in cols:
                if r == height - 1 and len(c) > height:
                    row.append(Text(f"+{len(c) - height + 1} more", style=ROLE["muted"]))
                elif r < len(c):
                    row.append(c[r])
                else:
                    row.append(Text(""))
            grid.add_row(*row)
        strip.update(grid)

    def action_toggle_week(self) -> None:
        strip = self.query_one(WeekStrip)
        strip.display = not strip.display
        if strip.display:
            self._update_week()
            self._khal_worker()

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

    def _resolve_list(self, name: str):
        """Resolve a list: token — case-insensitive exact, then unique
        prefix (so spaced names are reachable: list:heart → Heartwood…)."""
        lists = self.store.lists()
        low = name.lower()
        for tl in lists:
            if tl.name.lower() == low:
                return tl
        prefixed = [tl for tl in lists if tl.name.lower().startswith(low)]
        return prefixed[0] if len(prefixed) == 1 else None

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
        self._add_task()

    def _add_task(self, target=None, prefill: str = "") -> None:
        target = target or self._target_list()
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
            todo_list = target
            if fields["list"]:
                todo_list = self._resolve_list(fields["list"])
                if todo_list is None:
                    self.notify(
                        f"no list matching '{fields['list']}' — not added",
                        severity="warning",
                    )
                    return
            self.store.add(
                fields["summary"],
                todo_list=todo_list,
                categories=fields["categories"],
                priority=fields["priority"],
                due=fields["due"],
            )
            self.refresh_tasks()
            self.notify(f"added to {todo_list.name}")

        self.push_screen(
            LineModal(
                f"New task → {target.name}",
                value=prefill,
                placeholder="summary +project @context (A) due:… list:Name",
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
            new_list = None
            if fields["list"]:
                new_list = self._resolve_list(fields["list"])
                if new_list is None:
                    self.notify(
                        f"no list matching '{fields['list']}' — not saved",
                        severity="warning",
                    )
                    return
            self.store.edit(
                todo,
                summary=fields["summary"],
                categories=fields["categories"],
                priority=fields["priority"],
                due=fields["due"],
            )
            if new_list is not None and todo.list and new_list.path != todo.list.path:
                self.store.move(todo, new_list)
                self.notify(f"saved → {new_list.name}")
            else:
                self.notify("saved")
            self.refresh_tasks()

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
        # With a Radicale backend, new lists land in its storage and the
        # next discover+sync creates them server-side. Without it, lists
        # are local-only (iCloud pair is pinned to collection IDs).
        new_root = os.environ.get("TASQ_NEW_LIST_ROOT") or None
        radicale_pair = os.environ.get("TASQ_NEW_LIST_PAIR") or None

        def done(name: str | None) -> None:
            if not name or not name.strip():
                return
            name = name.strip()
            if self.store.list_named(name):
                self.notify(f"list '{name}' already exists", severity="warning")
                return
            self.store.create_list(name, root=new_root)
            self.store.reload()
            self.refresh_tasks()
            if radicale_pair:
                self.notify(f"list '{name}' created — pushing to Radicale…")
                self._new_list_worker(radicale_pair)
            else:
                self.notify(
                    f"list '{name}' created — LOCAL-ONLY. To get a phone-synced "
                    "list, create it in Apple Reminders instead (see walkthrough).",
                    timeout=10,
                )

        title = (
            "New list (synced via Radicale)" if radicale_pair
            else "New list (local-only — phone lists: create in Reminders)"
        )
        self.push_screen(LineModal(title, placeholder="list name"), done)

    @work(thread=True, exclusive=True, group="sync")
    def _new_list_worker(self, pair: str) -> None:
        code, out = self.store.discover_and_sync(pair)
        self.call_from_thread(self._sync_done, code, out)

    def _rename_list_flow(self, tl) -> None:
        def done(name: str | None) -> None:
            if not name or not name.strip():
                return
            name = name.strip()
            if name == tl.name:
                return
            if self.store.list_named(name):
                self.notify(f"list '{name}' already exists", severity="warning")
                return
            was_current = self.current_list == tl.name
            self.store.rename_list(tl, name)
            if was_current:
                self.current_list = name
            self._sidebar_pos = None
            self.refresh_tasks(keep_cursor=False)
            self.notify(f"renamed to '{name}' — R pushes it to the server")

        self.push_screen(LineModal(f"Rename list '{tl.name}'", value=tl.name), done)

    # -- leader key (space: act on the selected task) ------------------------------

    def _leader(self, title: str, entries) -> None:
        """Show a LeaderMenu for (key, label, fn) entries; run the picked fn.
        Every menu is built from live store data at open time."""
        actions = {key: fn for key, _, fn in entries}

        def done(key: str | None) -> None:
            if key is not None:
                actions[key]()

        self.push_screen(
            LeaderMenu(title, [(key, label) for key, label, _ in entries]), done
        )

    def action_leader(self) -> None:
        self._leader("task …", [
            ("l", "move to list …", self._leader_move_list),
            ("p", "set +project …", lambda: self._leader_set_category("+", "project")),
            ("c", "set @context …", lambda: self._leader_set_category("@", "context")),
            ("d", "edit due date", self._leader_due),
        ])

    def _leader_move_list(self) -> None:
        todo = self._selected()
        if todo is None:
            self.notify("no task selected", severity="warning")
            return
        cur_path = todo.list.path if todo.list else None

        def move(tl) -> None:
            if tl.path == cur_path:
                return
            self.store.move(todo, tl)
            self.refresh_tasks()
            self.notify(f"moved to {tl.name}")

        entries = [
            (str(i), tl.name + (" · current" if tl.path == cur_path else ""),
             lambda tl=tl: move(tl))
            for i, tl in enumerate(self.store.lists()[:9], start=1)
        ]
        self._leader(f"move '{todo.summary}' to", entries)

    def _used_categories(self, sigil: str) -> list[str]:
        return sorted({
            cat
            for t in self.store.todos(show_completed=True)
            for cat in t.categories or []
            if cat.startswith(sigil)
        })

    def _leader_set_category(self, sigil: str, label: str) -> None:
        todo = self._selected()
        if todo is None:
            self.notify("no task selected", severity="warning")
            return

        def assign(cat: str | None) -> None:
            # replace the task's sigil-categories; other sigils untouched
            cats = [c for c in (todo.categories or []) if not c.startswith(sigil)]
            if cat:
                cats.append(cat)
            self.store.edit(todo, categories=cats)
            self.refresh_tasks()
            self.notify(f"{label}: {cat or 'cleared'}")

        def new() -> None:
            def done(value: str | None) -> None:
                if not value or not value.strip():
                    return
                word = value.strip().split()[0]
                assign(word if word.startswith(sigil) else sigil + word)

            self.push_screen(
                LineModal(f"New {label} for '{todo.summary}'",
                          placeholder=f"{sigil}name"),
                done,
            )

        entries = [
            (str(i), cat + (" · current" if cat in (todo.categories or []) else ""),
             lambda cat=cat: assign(cat))
            for i, cat in enumerate(self._used_categories(sigil)[:9], start=1)
        ]
        entries.append(("n", f"new {label} …", new))
        entries.append(("x", f"clear {label}", lambda: assign(None)))
        self._leader(f"set {label} on '{todo.summary}'", entries)

    def _leader_due(self) -> None:
        todo = self._selected()
        if todo is None:
            self.notify("no task selected", severity="warning")
            return

        def done(value: str | None) -> None:
            if value is None:
                return
            value = value.strip()
            if not value:
                self.store.edit(todo, due=None)
                self.refresh_tasks()
                self.notify("due cleared")
                return
            d = model_map.parse_due(value)
            if d is None:
                self.notify(
                    f"can't read '{value}' — try today, tomorrow, fri, 2026-06-20",
                    severity="warning",
                )
                return
            self.store.edit(todo, due=d)
            self.refresh_tasks()
            self.notify(f"due {d.isoformat()}")

        self.push_screen(
            LineModal(
                f"Due — {todo.summary}",
                value=model_map.due_str(todo.due),
                placeholder="today · tomorrow · mon…sun · YYYY-MM-DD · empty clears",
            ),
            done,
        )

    # -- list / project / context management (L / P / C) ---------------------------

    def action_lists_menu(self) -> None:
        entries = [("n", "new list …", self.action_new_list)]
        entries += [
            (str(i), f"rename {tl.name} …", lambda tl=tl: self._rename_list_flow(tl))
            for i, tl in enumerate(self.store.lists()[:9], start=1)
        ]
        self._leader("lists", entries)

    def action_projects_menu(self) -> None:
        self._category_menu("+", "project")

    def action_contexts_menu(self) -> None:
        self._category_menu("@", "context")

    def _category_menu(self, sigil: str, label: str) -> None:
        cats = self._used_categories(sigil)
        if not cats:
            self.notify(
                f"no {sigil}{label}s yet — put one on a task with space-{label[0]}",
                severity="warning",
            )
            return
        entries = [
            (str(i), cat, lambda cat=cat: self._category_ops(cat, label))
            for i, cat in enumerate(cats[:9], start=1)
        ]
        self._leader(f"{label}s", entries)

    def _category_ops(self, cat: str, label: str) -> None:
        self._leader(cat, [
            ("r", "rename everywhere …", lambda: self._rename_category(cat, label)),
            ("d", "remove from all tasks …", lambda: self._delete_category(cat, label)),
        ])

    def _affected(self, cat: str):
        return [
            t for t in self.store.todos(show_completed=True)
            if cat in (t.categories or [])
        ]

    def _rename_category(self, cat: str, label: str) -> None:
        sigil = cat[0]

        def done(value: str | None) -> None:
            if not value or not value.strip():
                return
            new = value.strip().split()[0]
            new = new if new.startswith(sigil) else sigil + new
            if new == cat:
                return
            todos = self._affected(cat)
            for t in todos:
                self.store.edit(
                    t,
                    categories=[new if c == cat else c for c in (t.categories or [])],
                )
            self.refresh_tasks()
            self.notify(f"{cat} → {new} on {len(todos)} task(s)")

        self.push_screen(LineModal(f"Rename {label} {cat}", value=cat), done)

    def _delete_category(self, cat: str, label: str) -> None:
        todos = self._affected(cat)

        def done(confirmed: bool | None) -> None:
            if not confirmed:
                return
            for t in todos:
                self.store.edit(
                    t, categories=[c for c in (t.categories or []) if c != cat]
                )
            self.refresh_tasks()
            self.notify(f"removed {cat} from {len(todos)} task(s)")

        self.push_screen(
            ConfirmModal(f"Remove {cat} from {len(todos)} task(s)?"), done
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
        self._fetch_week_events()
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
            self._fetch_week_events()
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
    # TASQ_PATH may hold several globs (":"-separated) — e.g. the iCloud
    # tasks vdir plus the Radicale one.
    globs = [
        g for g in os.environ.get("TASQ_PATH", DEFAULT_GLOB).split(":") if g
    ]
    cache_path = os.environ.get("TASQ_CACHE", DEFAULT_CACHE)
    try:
        store = Store(globs, cache_path)
    except Exception as exc:
        print(f"tasq: {exc}", file=sys.stderr)
        raise SystemExit(1)
    TasqApp(store).run()


if __name__ == "__main__":
    main()
