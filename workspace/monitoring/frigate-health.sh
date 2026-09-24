#!/usr/bin/env bash
# Read-only evidence. JSON stdout never contains config, logs, process args or URLs.
set -euo pipefail
exec python3 - "$@" <<'PY'
import argparse, datetime as dt, json, math, subprocess, sys, time, urllib.parse, urllib.request

p = argparse.ArgumentParser(description="Read-only Frigate health and storage evidence")
p.add_argument("--api", default="http://127.0.0.1:5000")
p.add_argument("--prometheus", default="http://127.0.0.1:9090")
p.add_argument("--container", default="frigate")
p.add_argument(
    "--since", help="Post-change start as ISO timestamp including UTC offset"
)
p.add_argument(
    "--hours", type=float, default=24, help="Requested window, maximum 72 hours"
)
a = p.parse_args()
now = time.time()
if not math.isfinite(a.hours) or not 0 < a.hours <= 72:
    p.error("--hours must be greater than zero and at most 72")
try:
    d = dt.datetime.fromisoformat(a.since.replace("Z", "+00:00")) if a.since else None
    if d is not None and d.utcoffset() is None:
        raise ValueError()
    start = d.timestamp() if d else now - a.hours * 3600
    if start >= now:
        raise ValueError()
except ValueError:
    p.error("--since must be a past ISO timestamp including its UTC offset")
requested_end = start + a.hours * 3600
end = min(now, requested_end)
iso = lambda x: dt.datetime.fromtimestamp(x, dt.timezone.utc).isoformat()
r = {
    "schema_version": 1,
    "observed_at": iso(now),
    "errors": [],
    "window": {
        "start": iso(start),
        "end": iso(end),
        "requested_end": iso(requested_end),
        "complete": now >= requested_end,
        "post_change_start_explicit": a.since is not None,
        "observed_hours": round((end - start) / 3600, 4),
    },
    "limitations": [
        "Retained footage is not total activity; compare similar scene activity.",
        "A complete window does not prove day/night approach coverage.",
        "Historical deletion can reduce totals; collect before retention expires.",
        "No savings percentage is inferred from this report.",
    ],
}


def fetch(url):
    with urllib.request.urlopen(url, timeout=8) as f:
        return json.load(f)


try:
    stats = fetch(a.api.rstrip("/") + "/api/stats")
    config = fetch(a.api.rstrip("/") + "/api/config")
    r["cameras"] = {}
    for name, c in config["cameras"].items():
        enabled = c.get("enabled", True)
        s = stats["cameras"].get(name, {})
        r["cameras"][name] = {
            "enabled": enabled,
            "expected_fps": c["detect"]["fps"] if enabled else 0,
            **{k: s.get(k) for k in ("camera_fps", "process_fps", "skipped_fps")},
        }
        if enabled and (s.get("camera_fps", 0) < 1 or s.get("skipped_fps", 0) > 0):
            r["errors"].append("camera_not_healthy:" + name)
    r["inference_ms"] = {k: v["inference_speed"] for k, v in stats["detectors"].items()}
except (OSError, ValueError, KeyError, TypeError) as e:
    r["errors"].append("frigate_api:" + type(e).__name__)
query = r"""
import json,sqlite3,sys
c=sqlite3.connect('file:/config/frigate.db?mode=ro',uri=True,timeout=5);c.execute('PRAGMA query_only=ON')
start,end=map(float,sys.argv[1:])
rows=c.execute("SELECT camera,COUNT(*),SUM(duration),SUM(segment_size),SUM(CASE WHEN motion>0 THEN duration ELSE 0 END),MIN(start_time),MAX(end_time) FROM recordings WHERE start_time>=? AND end_time<=? GROUP BY camera",(start,end))
recordings={x[0]:dict(zip(('segments','retained_seconds','retained_mib','motion_seconds','first_segment_start','last_segment_end'),x[1:])) for x in rows}
events=[dict(zip(('camera','label','events','with_snapshot','with_clip'),x)) for x in c.execute("SELECT camera,label,COUNT(*),SUM(has_snapshot),SUM(has_clip) FROM event WHERE start_time>=? AND start_time<? AND false_positive=0 GROUP BY camera,label",(start,end))]
print(json.dumps({'recordings':recordings,'events':events}))
"""
try:
    out = subprocess.run(
        [
            "sudo",
            "-n",
            "podman",
            "exec",
            a.container,
            "python3",
            "-c",
            query,
            str(start),
            str(end),
        ],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    )
    r.update(json.loads(out.stdout))
    r["storage_method"] = (
        "Fully contained segments; boundary segments excluded; Frigate 0.16 segment_size is MiB rounded to 0.01 per segment"
    )
    for v in r["recordings"].values():
        v.update(
            retained_gib=round(v["retained_mib"] / 1024, 4),
            retained_hours=round(v["retained_seconds"] / 3600, 4),
        )
except (OSError, ValueError, subprocess.SubprocessError) as e:
    r["errors"].append("recording_database:" + type(e).__name__)
try:
    args = urllib.parse.urlencode(
        {
            "query": 'frigate_camera_fps{job="frigate"}',
            "start": start,
            "end": end,
            "step": 60,
        }
    )
    data = fetch(a.prometheus.rstrip("/") + "/api/v1/query_range?" + args)
    if data["status"] != "success":
        raise ValueError()
    expected = math.floor((end - start) / 60) + 1
    r["camera_online_samples"] = {
        name: {
            "expected_samples": expected,
            "present_samples": 0,
            "online_samples": 0,
            "sampling_seconds": 60,
        }
        for name in r.get("cameras", {})
    }
    for item in data["data"]["result"]:
        values = item["values"]
        r["camera_online_samples"][item["metric"]["camera_name"]] = {
            "expected_samples": expected,
            "present_samples": len(values),
            "online_samples": sum((float(v) >= 1 for _, v in values)),
            "sampling_seconds": 60,
        }
    r["limitations"].append(
        "Prometheus samples have up to its lookback interval of staleness."
    )
except (OSError, ValueError, KeyError, TypeError) as e:
    r["errors"].append("prometheus_history:" + type(e).__name__)
print(json.dumps(r, indent=2, sort_keys=True))
sys.exit(1 if r["errors"] else 0)
PY
