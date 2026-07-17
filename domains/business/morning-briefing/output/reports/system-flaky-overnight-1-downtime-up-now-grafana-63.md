Report written to the REPORT_PATH. Summary:

**Root cause found — it's a real but already-resolved outage, mislabeled "overnight."**

- The alert comes from a Prometheus blackbox probe of `http://127.0.0.1:3000/api/health` averaged over a **trailing 24h window** (`run.sh:377`), not from live service state.
- Grafana's old process was locked out of its SQLite DB — `unable to open database file: permission denied` logged **34,824 times** from **01:38 Jul 11 → 14:27 Jul 12** (~37h). While the DB was unreachable, `/api/health` returned 503, so the probe scored it down.
- A `nixos-rebuild switch` at **14:27 Jul 12** restarted Grafana cleanly; **zero errors since**. The 63% is just the ~15h of that outage still inside the 24h window (14.9h/24h ≈ 62%). Grafana itself was healthy all night.
- The alert is **self-clearing by ~14:27 today** as the outage ages out.

**Config note:** `grafana/index.nix` correctly forces `User=eric` and a tmpfiles `d` rule for the *dir*, but that rule isn't recursive — a `grafana.db` file owned by root/grafana (e.g. from a backup restore) would stay unreadable until a restart re-chowned it, which is exactly the 37h signature.

**NEXT ACTION:** `stat -c '%U:%G %a' /var/lib/hwc/grafana/grafana.db` — if not `eric:users`, add recursive ownership (`Z /var/lib/hwc/grafana - eric users -`) so this can't recur.

One cleanup note: I left a scratch `output/dispatch/_probe_query.py` from a probe attempt — I'm read-only/forbidden `rm`, so I didn't delete it; it's harmless but you may want to remove it.

---
*dispatched 2026-07-12T23:39:43-06:00 · card: system-flaky-overnight-1-downtime-up-now-grafana-63.md*
