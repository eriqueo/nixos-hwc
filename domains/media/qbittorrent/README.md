# qBittorrent - Torrent Download Client

**Container Service**: BitTorrent client for the *arr stack, routed through the Gluetun VPN.

**Access**: https://hwc-server.ocelot-wahoo.ts.net/qbt (subpath mode, strips prefix)

---

## Overview

qBittorrent is the torrent download client for Sonarr/Radarr/Lidarr/Readarr. It
runs inside the Gluetun VPN network namespace so all peer traffic egresses through
the VPN, never the host's real IP.

- **Network**: `vpn` mode by default — shares Gluetun's netns; the arrs reach it at `gluetun:8080`.
- **Routing**: Caddy subpath `/qbt` (prefix stripped; qBittorrent runs at root).
- **Config**: `${hwc.paths.apps.root}/qbittorrent/config` → `/config` in the container.

---

## Structure

```
qbittorrent/
├── index.nix          # Options (enable, image, network.mode, webPort, privacy, categories)
├── sys.nix            # System wiring
├── parts/
│   └── config.nix     # Container def + ExecStartPre enforce scripts
└── README.md
```

### Declaratively enforced config

Two `ExecStartPre` scripts run (as root) before the container starts and rewrite
files under `config/qBittorrent/`, so UI-made drift can't outlive a restart:

| Script                         | File               | Purpose                                    |
|--------------------------------|--------------------|--------------------------------------------|
| `qbittorrent-enforce-categories` | `categories.json` | Download categories from `cfg.categories`  |
| `qbittorrent-enforce-privacy`    | `qBittorrent.conf` | Privacy hardening keys (see below)          |

qBittorrent rewrites `qBittorrent.conf` on exit, so enforcement on every start is
what keeps these settings pinned. Only the managed keys are touched; all other
lines are preserved verbatim.

---

## Privacy hardening (`privacy.enable`, default `true`)

Because qBittorrent runs behind the VPN, peer **discovery** is deliberately
disabled so it can't announce to or find peers outside the tunnel. When
`privacy.enable = true`, the enforce script pins these under `[BitTorrent]`:

```ini
Session\AnonymousModeEnabled=true
Session\DHTEnabled=false
Session\LSDEnabled=false
Session\PeXEnabled=false
```

- **DHT** (distributed hash table), **LSD** (local service discovery) and **PeX**
  (peer exchange) are all off — none of them respect the VPN boundary cleanly.
- **Anonymous mode** on — strips the client fingerprint from announces.

**Trade-off (important):** DHT-only *magnet* links cannot bootstrap and surface in
Sonarr/Radarr queues as:

> `qBittorrent cannot resolve magnet link with DHT disabled`

This is expected, not a bug. Tracker-backed torrents (with working trackers) and
usenet (via SABnzbd) are unaffected. Prefer indexers that provide `.torrent`
files or well-trackered magnets; steer clear of DHT-only sources.

To disable the hardening (e.g. if ever run outside a VPN):

```nix
hwc.media.qbittorrent.privacy.enable = false;
```

The script then leaves qBittorrent's own defaults untouched.

---

## Common tasks

```bash
# Reapply enforced config + restart
sudo systemctl restart podman-qbittorrent

# Inspect the live privacy keys
sudo grep -E 'DHTEnabled|LSDEnabled|PeXEnabled|AnonymousMode' \
  /opt/qbittorrent/config/qBittorrent/qBittorrent.conf

# Logs
journalctl -u podman-qbittorrent -f
```

---

## Changelog

- **2026-07-03**: Made the DHT/LSD/PeX-off + anonymous-mode privacy hardening
  declarative via `privacy.enable` + a `qbittorrent-enforce-privacy` ExecStartPre
  script, and documented the rationale + magnet-link trade-off. Previously the
  settings lived only in the container's `qBittorrent.conf` (UI-set, undocumented,
  and vulnerable to a config-volume reset).
