"""tasq widgets: sidebar, task table, status bar, and the modal screens."""

from __future__ import annotations

from textual import on
from textual.binding import Binding
from textual.containers import Vertical
from textual.screen import ModalScreen
from textual.widgets import DataTable, Input, Label, OptionList, Static


class ListSidebar(OptionList):
    """Left pane: task lists (Reminders, Family, ...) plus an All entry."""


class TaskTable(DataTable):
    BINDINGS = [
        Binding("j", "cursor_down", show=False),
        Binding("k", "cursor_up", show=False),
    ]


class StatusBar(Static):
    """Bottom line: current list · sort · filters · count."""


class LineModal(ModalScreen):
    """Single-line input modal (add/edit task, filter prompts).

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


HELP_TEXT = """\
 tasq — VTODO task TUI                       (q or esc closes this help)

  a        add task           "summary +project @context (A) due:YYYY-MM-DD"
  e        edit selected task (same one-line form)
  x/space  toggle done
  d        delete (confirm)
  p        cycle priority     none → (A) → (B) → (C) → none

  /        filter: grep summary        (empty input clears)
  +        filter: project category    (empty input clears)
  @        filter: context category    (empty input clears)
  esc      clear all filters
  s        cycle sort         priority → due → created
  c        show/hide completed tasks

  l / L    next / previous list (All → Reminders → Family → ...)
  j/k g/G  move cursor / jump top/bottom

  r        reload from disk (after a sync pulled phone changes)
  R        run `vdirsyncer sync tasks` now, then reload

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
