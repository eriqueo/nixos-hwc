"""Bounded read-only recording checks; Frigate owns video and database writes.

labelmap.py owns model derivation, and cleanup.nix owns empty directories.
Neither is a recording observer. This command publishes idempotent metrics and
an AUTO-MANAGED versioned case ledger, bounded to 30 days / 10 MiB.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import time

LIMIT = 10 * 1024 * 1024
RETENTION = 30 * 86400


def observe(rows, now):
    ordered = sorted(rows, key=lambda row: row[0])
    gaps = [(a[1], b[0]) for a, b in zip(ordered, ordered[1:]) if b[0] - a[1] > 30]
    return {"age": max(0, now - ordered[-1][1]) if ordered else 86400,
            "gap": max((b - a for a, b in gaps), default=0),
            "evidence": gaps, "overflow": len(rows) >= 120}


def atomic_json(path, value):
    atomic(path, json.dumps(value, separators=(",", ":")))


def atomic(path, data):
    temporary = path.with_suffix(".tmp")
    with temporary.open("w") as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def transition(state, camera, kind, failed, evidence, now):
    key = camera + ":" + kind
    fingerprint = hashlib.sha256(json.dumps([key, evidence], sort_keys=True).encode()).hexdigest()
    previous = state["cases"].get(key)
    status = "open" if failed else "recovered"
    if previous is None and not failed:
        return
    if previous and previous["state"] == status:
        return
    event = {"case": key, "fingerprint": fingerprint, "state": status,
             "outcome": "failure" if failed else "success", "at": now}
    state["events"].append(event)
    state["cases"][key] = event


def run(settings, now, decode):
    state_path = Path(settings["state"]) / "state.json"
    state = {"schemaVersion": 1, "events": [], "cases": {}, "decode": {}, "watermark": now}
    state_error = 0
    if state_path.exists():
        try:
            if state_path.stat().st_size > LIMIT:
                raise ValueError("STATE_CAPACITY")
            old = json.loads(state_path.read_text())
            if old["schemaVersion"] != 1:
                raise ValueError("STATE_VERSION")
            for key in ("events", "cases", "decode", "watermark"):
                state[key] = old[key]
        except (ValueError, KeyError, TypeError):
            # Preserve malformed state for inspection; still publish failed health.
            state_error = 1
    coverage_error = int(now - state["watermark"] > 600)
    metrics = []
    database_error = 0
    try:
        connection = sqlite3.connect(Path(settings["database"]).as_uri() + "?mode=ro", uri=True, timeout=2)
        connection.execute("pragma query_only=ON")
        for camera in settings["cameras"]:
            rows = connection.execute(
                "select start_time,end_time,path from recordings where camera=? and start_time>? "
                "order by start_time desc limit 120", (camera, now - 600)).fetchall()
            result = observe(rows, now)
            coverage_error |= int(result["overflow"])
            cached = state["decode"].get(camera, {"at": 0, "failed": 0})
            if rows and now - cached["at"] >= 300:
                raw_path = Path(rows[0][2])
                relative = raw_path.relative_to("/media/frigate")
                path = Path(settings["media"]) / relative
                cached = {"at": now, "failed": int(not decode(path))}
                state["decode"][camera] = cached
            failures = {"stale": result["age"] > 60, "gap": result["gap"] > 30,
                        "decode": bool(cached["failed"])}
            for kind, failed in failures.items():
                transition(state, camera, kind, failed, result["evidence"] if kind == "gap" else kind, now)
            label = '{camera_name=' + json.dumps(camera) + '}'
            for name, value in {"age_seconds": result["age"], "gap_seconds": result["gap"],
                                "decode_failed": cached["failed"]}.items():
                metrics.append(f"frigate_recording_{name}{label} {value}")
        connection.close()
    except (sqlite3.Error, OSError, ValueError):
        database_error = 1
    transition(state, "checker", "database", bool(database_error), "DATABASE", now)
    transition(state, "checker", "coverage", bool(coverage_error), "COVERAGE", now)
    # Retain open cases even at capacity. Never discard an unresolved incident.
    open_keys = {k for k, v in state["cases"].items() if v["state"] == "open"}
    state["events"] = [e for e in state["events"] if e["at"] >= now - RETENTION or e["case"] in open_keys]
    state["watermark"] = now
    while len(json.dumps(state)) > LIMIT and any(e["case"] not in open_keys for e in state["events"]):
        index = next(i for i, e in enumerate(state["events"]) if e["case"] not in open_keys)
        state["events"].pop(index)
    if len(json.dumps(state)) > LIMIT:
        state_error = 1
    if not state_error:
        atomic_json(state_path, state)
    metrics.extend([f"frigate_recording_check_timestamp_seconds {now}",
                    f"frigate_recording_check_failed {int(bool(database_error or state_error or coverage_error))}"])
    atomic(Path(settings["metrics"]), "\n".join(metrics) + "\n")
    return database_error or state_error or coverage_error


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("settings")
    args = parser.parse_args()
    settings = json.loads(Path(args.settings).read_text())
    def decode(path):
        try:
            result = subprocess.run([settings["ffmpeg"], "-v", "error", "-threads", "1",
                                     "-i", str(path), "-t", "15", "-f", "null", "-"],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=15)
            return result.returncode == 0 and not result.stderr
        except (subprocess.TimeoutExpired, OSError):
            return False
    raise SystemExit(run(settings, time.time(), decode))


if __name__ == "__main__":
    main()
