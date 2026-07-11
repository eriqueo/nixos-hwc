# domains/monitoring/ — Monitoring Domain

## Purpose

Self-contained observability stack: Prometheus, Grafana, Alertmanager, cAdvisor, Exportarr, and Homepage dashboard.
Other domains register their scrape configs via `hwc.monitoring.prometheus.scrapeConfigs`.

## Boundaries

- Owns: metrics collection, dashboards, alerting, uptime monitoring, service dashboard, alert source detection
- Does NOT own: alert delivery (that's `domains/notifications/`), workflow automation (that's n8n in `domains/automation/`)
- External integrations: Immich, Frigate, and *arr containers push their scrape configs here

## Structure

```
monitoring/
├── index.nix           # Domain aggregator
├── README.md           # This file
├── options.nix         # Base toggle (hwc.monitoring.enable)
├── prometheus/         # Metrics collection + alert rules
│   ├── index.nix
│   ├── options.nix
│   └── parts/alerts.nix
├── grafana/            # Dashboards + visualization
│   ├── index.nix
│   ├── options.nix
│   └── dashboards/     # Pre-configured JSON dashboards
├── alertmanager/       # Alert routing to webhooks
│   ├── index.nix
│   └── options.nix
├── cadvisor/           # Container metrics
│   ├── index.nix
│   └── options.nix
├── exportarr/          # *arr application metrics
│   ├── index.nix
│   └── options.nix
├── homepage/           # Service dashboard (gethomepage)
│   ├── index.nix
│   └── parts/
│       ├── settings.yaml
│       ├── services.yaml
│       ├── widgets.yaml
│       ├── docker.yaml
│       └── bookmarks.yaml
└── alerts/             # Alert sources, thresholds, severity mapping
    └── index.nix
```

## Changelog
- 2026-07-11: **llama.cpp liveness probes.** Added the local-AI trio to the data-driven `httpServices` blackbox list — `llama.cpp GPU` (:11500), `llama.cpp CPU` (:11501), `llama.cpp Embed` (:11502), each probing `/health` (200 only when the model is loaded; 503-while-loading correctly reads as down). Closes the gap left by the 2026-06-27 ollama retirement, which removed the old n8n `:11434` healthcheck with nothing replacing it — brainvec semantic search depends on the embed service, so its liveness now shows on the Service Health dashboard. Dashboard-only (no alert rule; `service-alerts` are per named probe job).
- 2026-07-10: **Homepage link audit.** Tested every tile against live Caddy/backends (content-signature check, since the wildcard vhost returns an empty 200 for unmapped hosts). Two were dead: **JobTread MCP** (`:16100`, nothing listening) → replaced with **MCP Gateway** (`hwc-sys-mcp` on `:6200`, live `/health` widget showing status + tool count); **Estimator API** (`localhost:8099/docs`, retired FastAPI backend) → removed (the estimator is now a static PWA that calls n8n; the Estimator PWA tile already covers it). Added working-but-missing services found by diffing Homepage against every Caddy-routed host: **CRM** (crm), **Refinery** (refinery), **DataX Monitor** (monitor), **slskd**, **Tasks/Radicale** (tasks). Left off `tdarr`/`organizr` (backends 502), machine-only APIs (`hwc-leads`, `persona-daemon`, `llama-*`), and dups (`firefly-pico`).
- 2026-07-10: **Grafana image renderer + Cameras dashboard.** Enabled `services.grafana-image-renderer` (new toggle `hwc.monitoring.grafana.imageRenderer.enable`, default on) — a headless-Chromium sidecar that turns panels/dashboards into PNGs; `provisionGrafana = true` auto-wires `[rendering] server_url` (renderer) + `callback_url` (`http://127.0.0.1:3000`) into Grafana. Enables the `/render/...` API for alert screenshots and programmatic dashboard capture. Also added the **Cameras** dashboard (`/d/cameras`) fed by the now-working Frigate exporter (see `domains/media/frigate` changelog) — per-camera FPS, detection FPS, onnx inference speed, GPU utilisation, CPU-by-camera, stream bandwidth, surveillance storage %. Homepage gains the Cameras link.
- 2026-07-10: **Dashboard audit + real Containers dashboard.** Audited the 5 pre-existing dashboards (invisible for months while Grafana's DB was broken): deleted `arr-apps` (→ `media-library`), `system-health` (→ `server-overview`), and `frigate-monitoring`/`immich-monitoring` (no exporter feeding them — every panel empty). Replaced the dead `container-health` with a working **`containers`** dashboard (uid `containers`). Getting it working required fixing cAdvisor: podman gave it its own cgroup namespace (`/sys/fs/cgroup` showed empty tmpfs → only `id=/`), fixed with `--cgroupns=host`; but cAdvisor still can't map podman `libpod-*.scope` cgroups to names, so added the purpose-built **`podman-exporter`** (`hwc.monitoring.podman-exporter`, talks to the podman socket, every metric carries a `name` label). Containers dashboard reads `podman_container_*` — running count, per-container RAM/CPU bargauges, mem/CPU/network timeseries. New dashboards linked on the Homepage.
- 2026-07-09: **Grafana login removed (tailnet-only).** `auth.anonymous` enabled with `org_role = Admin` + `disable_login_form = true` — `grafana.hwc.*` is tailnet-only so the tailnet is the auth (same rationale as Uptime Kuma's disableAuth). You land straight on the dashboards with edit rights; no username/password. The agenix admin password still backs API + provisioning (append `?forceLogin=true` to reach the form).
- 2026-07-09: **Uptime Kuma decommissioned.** Module deleted (`uptime-kuma/`), profile enable dropped, homepage entry → Grafana Service Health, `workspace/utilities/setup-uptime-kuma.py` removed. Its monitors had drifted to retired endpoints (Ollama/NFS/Samba/Estimator failing 300–800 probes/night) and the declarative blackbox `probe-services-*` jobs + `grafana/d/service-health` dashboard replace it one-for-one with a Nix-owned service list. The morning briefing's ops digest now reads `probe_success` from Prometheus instead of scraping Kuma's journal. Data volume left at `/var/lib/uptime-kuma` — delete manually when confident.
- 2026-07-09: **Blackbox service liveness + Grafana "Service Health" dashboard — declarative Kuma replacement.** Added `http_reachable` (up = any alive status: 2xx/3xx/401/403) and `tcp_connect` blackbox modules, plus a data-driven `httpServices`/`tcpServices` list (30 HTTP + 5 TCP internal services, each carrying a human `service` label) probed via `probe-services-http`/`probe-services-tcp`. New provisioned dashboard `service-health.json` (uid `service-health`) at `https://grafana.hwc.iheartwoodcraft.com/d/service-health` — up/down counts, per-service status grid, latency trends, TLS-expiry table. The service list is now single-source-of-truth in Nix (add a service = one line), which is what the old hand-maintained Uptime Kuma monitors couldn't do — they drifted (Ollama/NFS/Samba/Estimator probed retired endpoints). **Also fixed a long-standing Grafana breakage:** `/var/lib/hwc/grafana` was owned `grafana:grafana 0700` (stale from before the `User=eric` migration) so the eric-run service got `database: permission denied` on every op → 503, no dashboards. One-time `chown eric:users` repaired it; the tmpfiles rule + `StateDirectory` keep it correct on clean deploys.
- 2026-07-09: Uptime Kuma auth disabled, declaratively — uptime-kuma.hwc.* is tailnet-only, so the login page added friction without security (the tailnet is the auth, like every other .hwc.* UI). Kuma has no env-var for this, so an ExecStartPre on podman-uptime-kuma upserts its `disableAuth` DB setting before each start (survives rebuilds/image updates/volume recreation; no-ops until Kuma's first boot creates kuma.db). The old wizard-set admin credential is no longer needed.
- 2026-07-07: Website + lead-pipeline monitoring — the blackbox exporter (enabled but previously probing nothing) gained three probe modules (CORS-preflight OPTIONS, unsigned-POST-expects-401, 200-or-401) and five probe jobs: public site pages/GEO artifacts, api.iheartwoodcraft.com webhook ingress, hwc-leads HMAC liveness, n8n /healthz, CMS API. New `website_alerts` rule group (P5: page down, webhook ingress down = leads being lost, leads service down, n8n down; P4: CMS down, cert expiry <14d; P3: slow responses). Alerts route via the existing alertmanager → hwc-notify receiver.
- 2026-07-06: Gotify decommission — dropped the stale gotify references from uptime-kuma header comments; the alertmanager `gotify-bridge` receiver was removed in profiles/monitoring/sys.nix (hwc-notify is now the sole receiver).
- 2026-07-05: Law 5 burn-down — added `HWC-EXCEPTION(Law 5)` annotation blocks (reason/justification/plan/revocable) to this domain's raw `oci-containers` module(s); infra-shaped containers are sanctioned exceptions to the mkContainer rule. Comments only, no behavior change.

- 2026-07-05: Dropped the `transcript-api-health` blackbox scrape (guarded on `youtube.legacyApi.enable`, which was removed from domains/media — the option was never true, so the job never rendered).
- 2026-06-04: Retired the duplicate script-based disk alerter (`alerts/` `sources.diskSpace`); Prometheus is now the sole disk-alert owner. Salvaged its critical-on-data-volumes logic into `HighDiskUsage` (95% P5), which now matches `/|/mnt/.*` instead of root-only — so a full `/mnt/media` or `/mnt/hot` raises P5, not just P4.
- 2026-06-04: Raised `ModerateDiskUsage` threshold 75% → 82% (`prometheus/parts/alerts.nix`). Root `/` baselines ~77%, so the 75% P3 alert fired permanently and Alertmanager re-sent it to Discord every 4h (repeat_interval) with no actionable signal — the dominant disk-alert spam. 82% sits above baseline, below the Elevated (85%) tier.
- 2026-06-04: Raised `PersonaDaemonReindexStale` threshold 1h → 7h (`prometheus/parts/alerts.nix`). The daemon only reindexes on content change with a 6h backstop reconcile (`persona-daemon/index.nix`, `OnUnitActiveSec=6h`), so the old 1h threshold fired on every quiet-vault period — a guaranteed false positive. 7h = 6h backstop + 1h margin.
- 2026-04-04: Added alerts/ subdir — alert sources, thresholds, severity mapping (from domains/alerts redistribution)
- 2026-03-27: Fixed alertmanager routing — default receiver was empty (alerts silently dropped). Now uses child routes with `continue: true` to fan out to all configured webhook receivers. Added ntfy-bridge as second receiver alongside n8n-webhook.
- 2026-03-04: Namespace migration hwc.server.native.monitoring.* → hwc.monitoring.*
- 2026-03-04: Moved from domains/server/native/monitoring/ (Phase 4 of DDD migration)
- 2026-03-27: Added Homepage (gethomepage) service dashboard and Uptime Kuma uptime monitor
