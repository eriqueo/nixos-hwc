"""Store — the hexagonal port over todoman.model.

ALL vdir/todoman access goes through this class; the UI never touches the
filesystem or todoman directly. Writes reuse todoman's VtodoWriter via
db.save() (atomic temp+rename, bumps SEQUENCE/LAST-MODIFIED, preserves
foreign properties on edit), so files stay byte-compatible with the `todo`
CLI and safe alongside vdirsyncer.

The sqlite cache is tasq's own (~/.cache/tasq/), deliberately separate from
todoman's — both rebuild from the same vdir, but sharing the file would
collide on integer todo ids.
"""

from __future__ import annotations

import base64
import glob as globlib
import json
import os
import shutil
import subprocess
import urllib.error
import urllib.request
from datetime import datetime, time, timezone
from uuid import uuid4

from todoman.model import Database, Todo, TodoList


class ListDeleteError(RuntimeError):
    """Raised when a list can't be hard-deleted (no Radicale backend wired,
    or the CalDAV DELETE failed). The shell catches it and notifies."""

ACTIVE_STATUS = "NEEDS-ACTION,IN-PROCESS"

SORT_MODES = ("priority", "due", "created")


def _ts(d) -> float | None:
    """Normalize date/datetime (naive or aware) to a comparable timestamp."""
    if d is None:
        return None
    if not isinstance(d, datetime):
        d = datetime.combine(d, time(23, 59, 59))
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    return d.timestamp()


def _pri_key(t: Todo):
    p = t.priority or 0
    return (1, 0) if p == 0 else (0, p)  # 1 = highest; none last


def _due_key(t: Todo):
    ts = _ts(t.due)
    return (1, 0.0) if ts is None else (0, ts)  # undated last


def _created_key(t: Todo):
    return -(_ts(t.created_at) or 0.0)  # newest first


_SORT_KEYS = {
    "priority": lambda t: (t.is_completed, _pri_key(t), _due_key(t), _created_key(t)),
    "due": lambda t: (t.is_completed, _due_key(t), _pri_key(t), _created_key(t)),
    "created": lambda t: (t.is_completed, _created_key(t)),
}


class Store:
    def __init__(self, glob_paths: list[str], cache_path: str) -> None:
        self.cache_path = os.path.expanduser(cache_path)
        os.makedirs(os.path.dirname(self.cache_path), exist_ok=True)
        self._globs = [os.path.expanduser(g) for g in glob_paths]
        self.db: Database | None = None
        self.reload()

    def _list_dirs(self) -> list[str]:
        dirs: list[str] = []
        for g in self._globs:
            dirs.extend(p for p in sorted(globlib.glob(g)) if os.path.isdir(p))
        return dirs

    def reload(self) -> None:
        """Re-instantiate the Database — rescans the vdir, absorbing
        vdirsyncer pulls (phone-side changes)."""
        if self.db is not None:
            try:
                self.db.close()
            except Exception:
                pass
        dirs = self._list_dirs()
        if not dirs:
            raise RuntimeError(
                f"no vdir list dirs match {self._globs} — has the Phase A "
                "tasks sync run yet? (vdirsyncer sync tasks)"
            )
        self.db = Database(dirs, self.cache_path)

    # -- read ---------------------------------------------------------------

    def lists(self) -> list[TodoList]:
        return sorted(self.db.lists(), key=lambda l: l.name.lower())

    def list_named(self, name: str) -> TodoList | None:
        for tl in self.lists():
            if tl.name == name:
                return tl
        return None

    def todos(
        self,
        *,
        list_name: str | None = None,
        category: str | None = None,
        grep: str | None = None,
        sort: str = "priority",
        show_completed: bool = False,
    ) -> list[Todo]:
        kwargs: dict = {"status": "ANY" if show_completed else ACTIVE_STATUS}
        if list_name:
            kwargs["lists"] = [list_name]
        if category:
            kwargs["categories"] = [category]
        if grep:
            kwargs["grep"] = grep
        todos = list(self.db.todos(**kwargs))
        todos.sort(key=_SORT_KEYS[sort])
        return todos

    # -- write (all funnel through db.save → VtodoWriter) -------------------

    def add(
        self,
        summary: str,
        *,
        todo_list: TodoList,
        categories=(),
        priority: int = 0,
        due=None,
        description: str = "",
    ) -> Todo:
        todo = Todo(new=True, list=todo_list)
        todo.summary = summary
        todo.categories = [str(c) for c in categories]
        todo.priority = priority
        if due is not None:
            todo.due = due
        todo.description = description
        self.db.save(todo)
        return todo

    def edit(self, todo: Todo, **fields) -> None:
        for name, value in fields.items():
            setattr(todo, name, value)
        self.db.save(todo)

    def toggle_done(self, todo: Todo) -> None:
        if todo.is_completed:
            todo.status = "NEEDS-ACTION"
            todo.completed_at = None
            todo.percent_complete = 0
        else:
            todo.complete()  # recurring: spawns next instance into .related
        self.db.save(todo)

    def move(self, todo: Todo, new_list: TodoList) -> None:
        """Move a todo's .ics into another list's dir (db.move is an
        os.rename between collection dirs; vdirsyncer carries it as
        delete+create). Reload so the cache's file paths stay truthful."""
        self.db.move(todo, new_list, from_list=todo.list)
        self.reload()

    def rename_list(self, todo_list: TodoList, name: str) -> None:
        """Rewrite the vdir displayname file. The collection dirname (its
        sync identity) is untouched, so this is rename-in-place; metasync
        propagates the new name server-side."""
        with open(os.path.join(todo_list.path, "displayname"), "w") as f:
            f.write(name + "\n")
        self.reload()

    # -- list deletion (CalDAV DELETE → Radicale; vdirsyncer can't) ----------

    # The Radicale backend means complete control: vdirsyncer never
    # propagates a *collection* deletion (a removed local dir is re-pulled by
    # the next `from a` discover), so deletion goes straight to the server
    # via a CalDAV DELETE — which Radicale honors (the collection vanishes
    # for the phone too). These come from the HM wrapper (TASQ_RADICALE_*),
    # mirroring the vdirsyncer pair's own url/user/password.fetch.
    _radicale_root = os.path.expanduser(os.environ.get("TASQ_NEW_LIST_ROOT", ""))
    _radicale_url = os.environ.get("TASQ_RADICALE_URL", "")
    _radicale_user = os.environ.get("TASQ_RADICALE_USER", "")
    _radicale_pw_cmd = os.environ.get("TASQ_RADICALE_PW_CMD", "")

    def list_is_radicale(self, todo_list: TodoList) -> bool:
        return bool(
            self._radicale_root
            and self._radicale_url
            and os.path.abspath(todo_list.path).startswith(
                os.path.abspath(self._radicale_root)
            )
        )

    def _radicale_password(self) -> str:
        out = subprocess.run(
            self._radicale_pw_cmd, shell=True, capture_output=True, text=True
        )
        if out.returncode != 0:
            raise ListDeleteError("could not read the Radicale password")
        return out.stdout.strip()

    def delete_list(self, todo_list: TodoList) -> None:
        """Hard-delete a Radicale-backed list: CalDAV DELETE the collection
        server-side, then drop the local vdir dir and its vdirsyncer status.
        Irreversible — removes the list and all its tasks everywhere."""
        if not self.list_is_radicale(todo_list):
            raise ListDeleteError(
                "only Radicale-backed lists can be deleted in tasq"
            )
        coll_id = os.path.basename(todo_list.path.rstrip("/"))
        url = self._radicale_url.rstrip("/") + f"/{self._radicale_user}/{coll_id}/"
        token = base64.b64encode(
            f"{self._radicale_user}:{self._radicale_password()}".encode()
        ).decode()
        req = urllib.request.Request(url, method="DELETE")
        req.add_header("Authorization", f"Basic {token}")
        try:
            urllib.request.urlopen(req, timeout=30)
        except urllib.error.HTTPError as exc:
            if exc.code != 404:  # 404 = already gone server-side; proceed
                raise ListDeleteError(f"Radicale DELETE failed ({exc.code})") from exc
        except urllib.error.URLError as exc:
            raise ListDeleteError(f"Radicale unreachable: {exc.reason}") from exc

        shutil.rmtree(todo_list.path, ignore_errors=True)
        self._purge_vdirsyncer_status(coll_id)
        self.reload()

    def _purge_vdirsyncer_status(self, coll_id: str) -> None:
        """Remove the now-orphaned per-collection vdirsyncer status files so
        the next sync doesn't carry stale state. Best-effort: stale status is
        inert (vdirsyncer only processes discovered collections), so any
        failure here is non-fatal."""
        pair = os.environ.get("TASQ_NEW_LIST_PAIR", "tasks_radicale")
        base = os.path.dirname(os.path.abspath(self._radicale_root))
        status_dir = os.path.join(base, "status", pair)
        for ext in (".items", ".metadata"):
            try:
                os.remove(os.path.join(status_dir, coll_id + ext))
            except OSError:
                pass

    def create_list(self, name: str, root: str | None = None) -> str:
        """Create a new vdir list dir (uuid dirname + displayname file).

        With the Radicale backend (TASQ_NEW_LIST_ROOT pointing at its local
        storage), the next discover+sync creates the collection server-side —
        a genuinely synced list. Under the iCloud-only setup the pair is
        pinned to specific collection IDs, so a locally created list stays
        LOCAL-ONLY (synced iCloud lists must be created in Apple Reminders;
        see WALKTHROUGH.md). Call reload() afterwards to pick it up.
        """
        root = os.path.expanduser(root) if root else os.path.dirname(self._globs[0])
        path = os.path.join(root, uuid4().hex.upper())
        os.makedirs(path)
        with open(os.path.join(path, "displayname"), "w") as f:
            f.write(name + "\n")
        return path

    def delete(self, todo: Todo) -> None:
        path = todo.path
        self.db.delete(todo)
        # db.delete only unlinks the file; evict it from the cache too so the
        # next todos() call doesn't resurrect it.
        self.db.cache.expire_file(path)
        self.db.cache.save_to_disk()

    # -- calendar events (khal is the port for VEVENTs) -----------------------

    def week_events(self, days: int = 7) -> list[list[dict]] | None:
        """Events for today..today+days-1 via `khal list --json` (khal expands
        recurrence). One list per day, in order. None if khal is unavailable
        or errors. Call from a worker, never the UI thread."""
        if shutil.which("khal") is None:
            return None
        cmd = ["khal", "list"]
        for field in ("title", "start", "end", "all-day"):
            cmd += ["--json", field]
        cmd += ["today", f"{days}d"]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if proc.returncode != 0:
            return None
        out: list[list[dict]] = []
        for line in proc.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                day = json.loads(line)
            except ValueError:
                continue
            if isinstance(day, list):
                out.append(day)
        while len(out) < days:
            out.append([])
        return out[:days]

    # -- sync ----------------------------------------------------------------

    # Pairs to sync; the HM module appends "tasks_radicale" when that backend
    # is enabled (TASQ_SYNC_PAIRS).
    sync_pairs = tuple(os.environ.get("TASQ_SYNC_PAIRS", "tasks").split())

    def _run_vdirsyncer(self, args: list[str], input_text: str | None = None) -> tuple[int, str]:
        try:
            proc = subprocess.run(
                ["vdirsyncer", *args],
                capture_output=True,
                text=True,
                timeout=120,
                input=input_text,
            )
        except FileNotFoundError:
            return 127, "vdirsyncer not found on PATH"
        except subprocess.TimeoutExpired:
            return 124, "vdirsyncer timed out after 120s"
        out = (proc.stdout + proc.stderr).strip()
        return proc.returncode, out

    def sync(self) -> tuple[int, str]:
        """Run `vdirsyncer sync <pairs>` (+ metasync so list names/colors
        propagate). Call from a worker, never the UI thread."""
        code, out = self._run_vdirsyncer(["sync", *self.sync_pairs])
        if code == 0:
            self._run_vdirsyncer(["metasync", *self.sync_pairs])
        return code, out

    def discover_and_sync(self, pair: str) -> tuple[int, str]:
        """Re-run collection discovery for one pair (answering yes to
        creation prompts), then sync it. Needed after creating a new list
        locally so vdirsyncer creates the collection server-side. metasync
        carries the displayname so the phone shows the list's real name.
        Call from a worker."""
        code, out = self._run_vdirsyncer(["discover", pair], input_text="y\n" * 20)
        if code != 0:
            return code, out
        code, out = self._run_vdirsyncer(["sync", pair])
        if code == 0:
            self._run_vdirsyncer(["metasync", pair])
        return code, out
