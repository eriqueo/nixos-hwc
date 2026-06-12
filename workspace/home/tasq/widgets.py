"""tasq widgets: filter sidebar, task table, and the modal screens."""

from __future__ import annotations

from rich.text import Text
from textual import events, on
from textual.binding import Binding
from textual.containers import Vertical
from textual.screen import ModalScreen
from textual.widgets import DataTable, Input, Label, OptionList, Static


class FilterSidebar(OptionList):
    """Left pane: LISTS / PROJECTS / CONTEXTS sections with task counts.

    The app rebuilds its options on every data refresh and keeps a parallel
    payload list mapping option index -> ("list", name) | ("cat", name).
    Section headers are disabled options (navigation skips them).
    """


class TaskTable(DataTable):
    BINDINGS = [
        Binding("j", "cursor_down", show=False),
        Binding("k", "cursor_up", show=False),
    ]


class DetailPanel(Static):
    """Right pane: full detail of the selected task (tuxedo-style)."""


class WeekStrip(Static):
    """Bottom strip: 7-day calendar of khal events + tasks due this week.

    The app renders a rich Table into it (one column per day, today first);
    events are ◆-prefixed in the info color, tasks ☐-prefixed in priority
    colors, overdue tasks lead today's column in red. Toggled with `w`.
    """


class LineModal(ModalScreen):
    """Single-line input modal (add/edit task, filter prompts, new list).

    Dismisses with the entered string (may be empty = clear), or None on
    escape/cancel.
    """

    BINDINGS = [Binding("escape", "cancel", "Cancel", show=False)]

    def __init__(self, title: str, value: str = "", placeholder: str = "") -> None:
        super().__init__()
        self._title = title
        self._value = value
        self._placeholder = placeholder

    def compose(self):
        with Vertical(classes="modal-box"):
            yield Label(self._title, classes="modal-title")
            yield Input(value=self._value, placeholder=self._placeholder)

    def on_mount(self) -> None:
        inp = self.query_one(Input)
        inp.cursor_position = len(self._value)
        inp.focus()

    @on(Input.Submitted)
    def _submit(self, event: Input.Submitted) -> None:
        self.dismiss(event.value)

    def action_cancel(self) -> None:
        self.dismiss(None)


class ConfirmModal(ModalScreen):
    """y/n confirmation. Dismisses True/False."""

    BINDINGS = [
        Binding("y", "yes", "Yes", show=False),
        Binding("n", "no", "No", show=False),
        Binding("escape", "no", "No", show=False),
    ]

    def __init__(self, question: str) -> None:
        super().__init__()
        self._question = question

    def compose(self):
        with Vertical(classes="modal-box"):
            yield Label(self._question, classes="modal-title")
            yield Label("y = yes · n / esc = no", classes="modal-hint")

    def action_yes(self) -> None:
        self.dismiss(True)

    def action_no(self) -> None:
        self.dismiss(False)


class LeaderMenu(ModalScreen):
    """Which-key style leader menu (space leader, nvim/yazi/aerc-style).

    Shows (key, label) rows; pressing a listed key dismisses with that key
    string — the app maps it to an action or a deeper LeaderMenu. Escape or
    space again cancels (dismisses None).
    """

    BINDINGS = [
        Binding("escape", "cancel", show=False),
        Binding("space", "cancel", show=False),
    ]

    def __init__(self, title: str, entries: list[tuple[str, str]]) -> None:
        super().__init__()
        self._title = title
        self._entries = entries
        self._keys = {key for key, _ in entries}

    def compose(self):
        body = Text()
        for key, label in self._entries:
            body.append(f"  {key:>3}  ", style="bold")
            body.append(f"{label}\n")
        with Vertical(classes="modal-box leader-box"):
            yield Label(self._title, classes="modal-title")
            yield Static(body)

    def on_key(self, event: events.Key) -> None:
        if event.key in self._keys:
            event.stop()
            self.dismiss(event.key)

    def action_cancel(self) -> None:
        self.dismiss(None)


HELP_TEXT = """\
 tasq — VTODO task TUI                       (q or esc closes this help)

 SIDEBAR
  LISTS     Reminders lists — these sync to the phone.
  PROJECTS  +name tags: the outcome you're working toward (+baxter-kitchen).
  CONTEXTS  @name tags: where/when you can do it (@shop, @errand, @phone).
  Select a project/context to filter; select it again (or esc) to clear.

 EDITING
  a        add task           "summary +project @context (A) due:fri list:Name"
  e        edit selected task (same one-line form)
           list:Name targets/moves the task (ci; unique prefix: list:heart)
           due: takes today · tomorrow · mon…sun · YYYY-MM-DD
  x        toggle done
  d        delete (confirm)
  p        cycle priority     none → (A) → (B) → (C) → none

 LEADER (space) — acts on the selected task; menus are built live
  space l  move it to a list         (pick a number)
  space p  set its +project          (number · n new · x clear)
  space c  set its @context          (number · n new · x clear)
  space d  edit its due date         today · tomorrow · fri · YYYY-MM-DD

 MANAGE
  L        lists                     n new · pick → rename / DELETE
           (delete = CalDAV DELETE to Radicale: removes the list and its
            tasks from the server and your phone — irreversible)
  P        projects                  pick → rename everywhere / remove from all
  C        contexts                  pick → rename everywhere / remove from all
  N        new list                  (shortcut for L n)

 VIEW
  /        filter: grep summary        (empty input clears)
  +        filter: project category    (empty input clears)
  @        filter: context category    (empty input clears)
  esc      clear all filters
  s        cycle sort         priority → due → created
  c        show/hide completed tasks
  ^j / ^k  step the sidebar selection (lists → projects → contexts)
  [ / ]    toggle sidebar / detail panel
  w        toggle the 7-day week strip (◆ khal events · ☐ tasks due)
  j/k g/G  move cursor / jump top/bottom

 SYSTEM
  r        reload from disk (after a sync pulled phone changes)
  R        run `vdirsyncer sync tasks` now, then reload
  K        open khal interactive (calendar view) — q returns to tasq

 Changes write standard VTODO .ics into the vdir; the 15-min vdirsyncer
 timer (or R) carries them to iCloud → Apple Reminders, and back.\
"""


class HelpModal(ModalScreen):
    BINDINGS = [
        Binding("escape", "close", show=False),
        Binding("q", "close", show=False),
        Binding("question_mark", "close", show=False),
    ]

    def compose(self):
        with Vertical(classes="modal-box help-box"):
            yield Static(HELP_TEXT)

    def action_close(self) -> None:
        self.dismiss(None)
