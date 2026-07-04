# mousehole - MyAnonamouse Seedbox IP Updater

**Container Service**: Keeps the MyAnonamouse (MAM) session pinned to the VPN's
current public IP so the seedbox session doesn't get invalidated when the tunnel
rotates its exit IP.

**Access**: No public/tailnet route — headless background service. Web UI bound to
`127.0.0.1:5010` inside the gluetun network namespace only.

---

## Overview

[mousehole](https://github.com/tmmrtn/mousehole) polls MyAnonamouse on a fixed
interval and, whenever the observed public IP no longer matches the IP MAM has on
file for the session, submits an update so the session stays valid. Because the
seedbox traffic egresses through the VPN, the service runs **inside gluetun's
network namespace** — it observes and reports the same IP the torrent client uses.

### Key Behaviour

- **Idle most of the time**: on each tick it logs `No update needed, current state
  is ok` and schedules the next check.
- **Acts only on IP change / stale response**: submits a MAM update when the IP
  drifts or the cached response ages past `staleResponseSeconds`.
- **No secrets in this module**: the MAM session credential is held in the
  container's persistent data dir, not agenix (see [Data](#data--persistence)).

---

## Architecture

### Service Type
- **Container**: Podman (via the shared `mkContainer` helper)
- **Image**: `tmmrtn/mousehole:latest`
- **Network**: `vpn` — shares gluetun's network namespace (no own ports on host)
- **Routing**: None — not reverse-proxied; UI reachable only from within the
  gluetun namespace on `:5010`

### Resource Limits

Deliberately light (it does almost nothing most of the time):

```nix
memory     = "256m";
memorySwap = "512m";
cpus       = "0.25";
```

### Data / Persistence

```
${hwc.paths.apps.root}/mousehole/data   →  /srv/mousehole   (MOUSEHOLE_STATE_DIR_PATH)
```

The data dir is created and `chown 1000:100`-ed by the `ensure-mousehole-config`
ExecStartPre script before the container starts. The MAM session state lives here.

### Environment

| Variable | Source | Default |
|---|---|---|
| `MOUSEHOLE_PORT` | `cfg.port` | `5010` |
| `MOUSEHOLE_STATE_DIR_PATH` | fixed | `/srv/mousehole` |
| `MOUSEHOLE_CHECK_INTERVAL_SECONDS` | `cfg.checkInterval` | `300` |
| `MOUSEHOLE_STALE_RESPONSE_SECONDS` | `cfg.staleResponseSeconds` | `86400` |

---

## Options

Namespace: `hwc.media.mousehole.*`

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the mousehole container |
| `image` | str | `tmmrtn/mousehole:latest` | Container image |
| `port` | int | `5010` | Web UI port (inside the VPN namespace) |
| `checkInterval` | int | `300` | Seconds between IP checks |
| `staleResponseSeconds` | int | `86400` | How long a MAM response is considered valid |

Enabled on hwc-server via `hwc.media.mousehole.enable = lib.mkDefault true`
(`machines/server/config.nix`).

---

## Service Dependencies

mousehole is hard-bound to gluetun — it has no network of its own and must not
outlive the tunnel:

```
podman-gluetun.service
    ↓  after / requires / bindsTo / partOf
podman-mousehole.service
```

- **`requires` + `after`** `podman-gluetun.service` — won't start without the tunnel.
- **`bindsTo` + `partOf`** `podman-gluetun.service` — stops/restarts in lockstep with
  gluetun, so it can never run (and leak an update with the wrong IP) outside the VPN.

### Validation

An assertion (`index.nix`) fails the build if gluetun is disabled:

```
mousehole requires gluetun to be enabled (runs inside VPN tunnel)
```

---

## Operations

### Status

```bash
systemctl status podman-mousehole
sudo podman ps --filter name=mousehole
```

### Logs

```bash
# Steady state: "No update needed, current state is ok" every checkInterval
journalctl -u podman-mousehole -f

# Find actual IP updates / errors only
journalctl -u podman-mousehole | grep -iv "No update needed"
```

### Restart

```bash
# mousehole only
sudo systemctl restart podman-mousehole

# Note: restarting gluetun will restart mousehole too (bindsTo/partOf)
sudo systemctl restart podman-gluetun
```

---

## Troubleshooting

### Service won't start

First check gluetun — mousehole is bound to it and cannot start on its own:

```bash
systemctl status podman-gluetun
journalctl -u podman-mousehole -n 50
```

### MAM session keeps getting invalidated

Confirm mousehole actually sees the **VPN** IP, not the host IP:

```bash
# IP as seen from inside the gluetun namespace (what mousehole reports)
sudo podman exec gluetun wget -qO- https://api.ipify.org; echo
```

If that matches the IP MAM expects but the session still drops, the cached session
state in `${hwc.paths.apps.root}/mousehole/data` may be stale — check the logs for
update attempts and inspect the data dir.

### Verify it's checking on schedule

```bash
journalctl -u podman-mousehole --since "30 min ago" | grep "Next automatic update"
```

Cadence should match `checkInterval` (default 5 min).

---

## Configuration Files

- **Module**: `domains/media/mousehole/`
  - `index.nix` — options + enable + gluetun assertion
  - `sys.nix` — container definition via `mkContainer` (vpn network, resource limits, env, volumes)
  - `parts/config.nix` — `ensure-mousehole-config` ExecStartPre + gluetun systemd binding

---

## References

- **mousehole GitHub**: https://github.com/tmmrtn/mousehole
- **MyAnonamouse**: https://www.myanonamouse.net/
- **gluetun module**: `domains/networking/gluetun/`
- **HWC Charter**: `CHARTER.md`

---

## Changelog

- **2026-06-29**: Initial README. Service has been live and healthy on hwc-server
  since 2026-06-11 (5-min IP checks, idle steady state).
