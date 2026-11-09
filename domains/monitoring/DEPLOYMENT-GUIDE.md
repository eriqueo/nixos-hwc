# Monitoring deployment and inspection

The monitoring role in `profiles/monitoring/sys.nix` enables the central stack
on hwc-work. The server role enables host agents. Alertmanager sends alerts to
hwc-notify; notifications owns channel delivery.

Use the system release lane documented in [CLAUDE.md](../../CLAUDE.md). Commit
changes in a worktree, then run the supported release runner from the target
host's primary main checkout. The runner checks the candidate, builds that
host's assembly, fast-forwards main and switches. Repeat it on each host whose
running configuration changes. A successful build alone does not activate it.

After activation, inspect the serving host with read-only requests:

```bash
ssh hwc-work 'systemctl is-active prometheus grafana alertmanager'
ssh hwc-work 'curl -fsS http://127.0.0.1:9090/-/ready'
ssh hwc-work 'curl -fsS http://127.0.0.1:9090/api/v1/targets'
ssh hwc-work 'curl -fsS http://127.0.0.1:9090/api/v1/rules'
ssh hwc-work 'curl -fsS http://127.0.0.1:9090/api/v1/alertmanagers'
```

These URLs use the default Prometheus port. If its port changes, use the
configured value. Grafana is at `https://grafana.hwc.iheartwoodcraft.com`.
Its provisioned datasource and dashboards require no manual setup. The
`auth.anonymous` policy in `grafana/index.nix` grants Admin on the private
vhost; use that module to inspect the current access policy.

The release runner owns verification. Focused checks in `verification/checks.nix`
cover tier exclusivity, PromQL parsing, failure-unit wiring, fleet map ownership,
website security, calculator intake and non-default monitoring configuration.
Their local fixtures exercise failure states without sending alerts to people.

For a failed unit, inspect `journalctl -u <unit> -n 50` on its owning host.
Inspect failed probe labels in Prometheus before changing its service or URL.
Change thresholds in `prometheus/parts/alerts.nix`, dashboards in
`grafana/dashboards/`, and receiver configuration through the monitoring role.
Use the secret-provision workflow for credential rotation; keep plaintext out
of shell arguments and logs.
