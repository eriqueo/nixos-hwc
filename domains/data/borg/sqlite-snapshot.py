#!/usr/bin/env python3
"""Create a self-contained SQLite backup before Borg reads application data.

The application user reads the source. The caller validates and publishes its own
private copy. One last-good file and one bounded staging slot exist per name.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import random
import re
import resource
import shutil
import signal
import sqlite3
import stat
import subprocess
import sys
import time
import uuid


class Held(Exception):
    pass


def require(value, code):
    if not value:
        raise Held(code)


def signature(value):
    return (value.st_dev, value.st_ino, value.st_uid, value.st_nlink,
            value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def directory(path, mode, owner):
    require(path.is_absolute() and path.parent.resolve(strict=True) == path.parent,
            "unsafe-parent")
    try:
        path.mkdir(mode=mode)
        path.chmod(mode)
    except FileExistsError:
        pass
    value = path.lstat()
    require(stat.S_ISDIR(value.st_mode) and value.st_uid == owner
            and stat.S_IMODE(value.st_mode) == mode, "unsafe-directory")
    return os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)


def check_database(path, deadline, clock):
    require(clock() < deadline, "snapshot-deadline")
    connection = sqlite3.connect(path.as_uri() + "?mode=ro&immutable=1", uri=True, timeout=1)
    try:
        connection.execute("PRAGMA query_only=ON")
        connection.set_progress_handler(lambda: int(clock() >= deadline), 10000)
        require(connection.execute("PRAGMA integrity_check").fetchone() == ("ok",),
                "snapshot-integrity-failed")
        require(clock() < deadline, "snapshot-deadline")
    finally:
        connection.close()


def copy_database(source, destination, maximum, deadline, owner, clock, sleep, jitter):
    initial = source.lstat()
    require(stat.S_ISREG(initial.st_mode) and initial.st_uid == owner
            and initial.st_nlink == 1 and 0 < initial.st_size <= maximum,
            "unsafe-source")
    require(source != destination and source.resolve(strict=True) == source,
            "unsafe-source-path")
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    os.fchmod(fd, 0o600)
    os.close(fd)
    resource.setrlimit(resource.RLIMIT_FSIZE, (maximum, maximum))
    reader = writer = None
    busy = 0
    try:
        reader = sqlite3.connect(source.as_uri() + "?mode=ro", uri=True, timeout=.1)
        reader.execute("PRAGMA query_only=ON")
        reader.execute("PRAGMA cache_size=-16384")
        writer = sqlite3.connect(destination, timeout=.1)
        writer.execute("PRAGMA cache_size=-16384")

        def progress(status, remaining, total):
            nonlocal busy
            require(clock() < deadline, "snapshot-deadline")
            require(destination.stat().st_size <= maximum, "snapshot-size-limit")
            if status in (sqlite3.SQLITE_BUSY, sqlite3.SQLITE_LOCKED):
                busy += 1
                require(busy <= 64, "snapshot-busy-limit")
                sleep(jitter(.005, .025))

        reader.backup(writer, pages=256, progress=progress, sleep=.01)
    finally:
        if writer:
            writer.close()
        if reader:
            reader.close()
    current = source.lstat()
    require((initial.st_dev, initial.st_ino, initial.st_uid)
            == (current.st_dev, current.st_ino, current.st_uid), "source-replaced")
    require(not any(Path(str(destination) + suffix).exists()
                    for suffix in ("-wal", "-shm", "-journal")), "snapshot-sidecar-remains")
    check_database(destination, deadline, clock)


def group_empty(pid):
    try:
        os.killpg(pid, 0)
    except ProcessLookupError:
        return True
    return False


def entries(fd):
    result = []
    with os.scandir(fd) as iterator:
        for entry in iterator:
            require(len(result) < 3, "unexpected-stage-entries")
            result.append(entry.name)
    return set(result)


def create(args, clock):
    require(re.fullmatch(r"[a-z][a-z0-9-]{0,31}", args.name), "invalid-name")
    root, source = Path(args.state_root), Path(args.source)
    require(root.is_absolute() and source.is_absolute() and not source.is_relative_to(root),
            "invalid-paths")
    actor = os.geteuid()
    account = pwd.getpwnam(args.user)
    require(actor in (0, account.pw_uid), "wrong-caller")
    require(shutil.disk_usage(root.parent).free > 2 * args.max_bytes + 1073741824,
            "insufficient-disk-headroom")
    deadline = clock() + args.timeout_seconds
    root_fd = staging_fd = ready_fd = stage_fd = input_fd = temp_fd = None
    stage_created = worker_clear = False
    temp_name = None
    input_identity = None
    try:
        root_fd = directory(root, 0o711, actor)
        staging_fd = directory(root / "staging", 0o711, actor)
        ready_fd = directory(root / "ready", 0o700, actor)
        # Exclusive slot is the operation reservation. A leftover slot is held,
        # never reused or purged by a later attempt.
        os.mkdir(args.name, 0o700, dir_fd=staging_fd)
        stage_created = True
        stage_fd = os.open(args.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                           dir_fd=staging_fd)
        os.fchown(stage_fd, account.pw_uid, account.pw_gid)
        os.fchmod(stage_fd, 0o700)
        stage_identity = os.fstat(stage_fd)
        staged = root / "staging" / args.name / "state.sqlite"
        command = [sys.executable, str(Path(__file__).resolve()), "copy", "--source", str(source),
                   "--destination", str(staged), "--max-bytes", str(args.max_bytes),
                   "--timeout-seconds", str(args.timeout_seconds)]
        if actor != account.pw_uid:
            command = [shutil.which("runuser"), "-u", account.pw_name, "--", *command]
        command = [shutil.which("timeout"), "--kill-after=5s", str(args.timeout_seconds) + "s",
                   *command]
        require(all(isinstance(part, str) and part for part in command), "runtime-port-unavailable")
        environment = {"HOME": account.pw_dir, "USER": account.pw_name,
                       "LOGNAME": account.pw_name, "LANG": "C.UTF-8",
                       "PATH": os.environ.get("PATH", ""), "PYTHONDONTWRITEBYTECODE": "1"}
        worker = subprocess.Popen(command, cwd="/", env=environment, stdin=subprocess.DEVNULL,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            stdout, stderr = worker.communicate(timeout=args.timeout_seconds + 10)
        except subprocess.TimeoutExpired:
            # This group was created by this Popen, never predicted from a name.
            if not group_empty(worker.pid):
                os.killpg(worker.pid, signal.SIGKILL)
            worker.communicate(timeout=5)
            raise Held("worker-deadline")
        finally:
            worker_clear = group_empty(worker.pid)
        require(worker_clear, "worker-scope-not-empty")
        require(len(stdout) <= 16384 and len(stderr) <= 16384, "worker-output-limit")
        require(worker.returncode == 0, "worker-failed")
        require(entries(stage_fd) == {"state.sqlite"}, "unexpected-stage-entries")
        input_fd = os.open("state.sqlite", os.O_RDONLY | os.O_NOFOLLOW, dir_fd=stage_fd)
        original = os.fstat(input_fd)
        require(stat.S_ISREG(original.st_mode) and original.st_uid == account.pw_uid
                and original.st_nlink == 1 and 0 < original.st_size <= args.max_bytes
                and stat.S_IMODE(original.st_mode) == 0o600, "unsafe-staged-file")
        input_identity = (original.st_dev, original.st_ino)
        temp_name = "." + args.name + "-" + uuid.uuid4().hex + ".sqlite"
        temp_fd = os.open(temp_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                          0o600, dir_fd=ready_fd)
        os.fchmod(temp_fd, 0o600)
        checksum, copied = hashlib.sha256(), 0
        while True:
            require(clock() < deadline, "snapshot-deadline")
            chunk = os.read(input_fd, 1048576)
            if not chunk:
                break
            copied += len(chunk)
            require(copied <= args.max_bytes, "snapshot-size-limit")
            checksum.update(chunk)
            view = memoryview(chunk)
            while view:
                view = view[os.write(temp_fd, view):]
        require(copied == original.st_size and signature(original) == signature(os.fstat(input_fd)),
                "staged-file-changed")
        os.fsync(temp_fd)
        check_database(Path("/proc/self/fd") / str(ready_fd) / temp_name, deadline, clock)
        require(clock() < deadline, "snapshot-deadline")
        final_name = args.name + ".sqlite"
        try:
            previous = os.stat(final_name, dir_fd=ready_fd, follow_symlinks=False)
            require(stat.S_ISREG(previous.st_mode) and previous.st_uid == actor
                    and previous.st_nlink == 1, "unsafe-last-good")
        except FileNotFoundError:
            pass
        os.replace(temp_name, final_name, src_dir_fd=ready_fd, dst_dir_fd=ready_fd)
        temp_name = None
        os.fsync(ready_fd)
        return {"schemaVersion": 1, "state": "succeeded", "path": str(root / "ready" / final_name),
                "bytes": copied, "sha256": checksum.hexdigest(), "sourceUid": account.pw_uid}
    finally:
        if temp_fd is not None:
            os.close(temp_fd)
        if temp_name is not None and ready_fd is not None:
            os.unlink(temp_name, dir_fd=ready_fd)
        if input_fd is not None:
            os.close(input_fd)
        if stage_created and worker_clear and stage_fd is not None:
            observed = os.stat(args.name, dir_fd=staging_fd, follow_symlinks=False)
            require((observed.st_dev, observed.st_ino) == (stage_identity.st_dev, stage_identity.st_ino),
                    "stage-replaced")
            names = entries(stage_fd)
            if names == {"state.sqlite"}:
                value = os.stat("state.sqlite", dir_fd=stage_fd, follow_symlinks=False)
                require(stat.S_ISREG(value.st_mode) and value.st_uid == account.pw_uid
                        and value.st_nlink == 1 and (input_identity is None
                        or (value.st_dev, value.st_ino) == input_identity), "stage-cleanup-held")
                os.unlink("state.sqlite", dir_fd=stage_fd)
            elif names:
                raise Held("stage-cleanup-held")
            os.rmdir(args.name, dir_fd=staging_fd)
            os.fsync(staging_fd)
        for fd in (stage_fd, ready_fd, staging_fd, root_fd):
            if fd is not None:
                os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("create", "copy"):
        command = commands.add_parser(name)
        command.add_argument("--source", required=True)
        command.add_argument("--max-bytes", type=int, required=True)
        command.add_argument("--timeout-seconds", type=float, required=True)
        if name == "create":
            for field in ("state-root", "name", "user"):
                command.add_argument("--" + field, required=True)
        else:
            command.add_argument("--destination", required=True)
    args = parser.parse_args()
    require(0 < args.max_bytes <= 68719476736 and 0 < args.timeout_seconds <= 3600,
            "invalid-limits")
    os.umask(0o077)
    if args.command == "copy":
        copy_database(Path(args.source), Path(args.destination), args.max_bytes,
                      time.monotonic() + args.timeout_seconds, os.geteuid(),
                      time.monotonic, time.sleep, random.uniform)
        result = {"schemaVersion": 1, "state": "succeeded"}
    else:
        result = create(args, time.monotonic)
    print(json.dumps(result))


if __name__ == "__main__":
    try:
        main()
    except (Held, OSError, ValueError, KeyError, sqlite3.Error, subprocess.SubprocessError) as error:
        code = str(error) if isinstance(error, Held) else "snapshot-unavailable"
        print(json.dumps({"schemaVersion": 1, "state": "failed", "code": code}), file=sys.stderr)
        raise SystemExit(1)
