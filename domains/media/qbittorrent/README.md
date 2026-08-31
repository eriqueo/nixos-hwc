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

## Privacy hardening (`privacy.*`, master switch default `true`)

qBittorrent runs inside gluetun's network namespace, so **the tunnel is the
privacy boundary** — every packet the client sends already egresses from the VPN
exit IP. The toggles below tune peer discovery on top of that; they are not what
keeps the host IP off the wire.

When `privacy.enable = true`, the enforce script pins these under `[BitTorrent]`:

```ini
Session\AnonymousModeEnabled=true    # privacy.anonymousMode
Session\DHTEnabled=true              # privacy.dht
Session\PeXEnabled=true              # privacy.pex
Session\LSDEnabled=false             # privacy.lsd
```

| Option | Default | Why |
|---|---|---|
| `anonymousMode` | `true` | Strips the client fingerprint from announces. Free — no effect on discovery. |
| `dht` | `true` | **Required for magnet links.** A magnet carries no metadata; without a peer source the torrent parks in `metaDL` at 0% forever. |
| `pex` | `true` | Second discovery path when a magnet's trackers are dead. |
| `lsd` | `false` | Multicast LAN discovery. Useless in a container namespace, and the one mechanism that could address a non-tunnelled interface. |

### Why DHT and PeX are on (changed 2026-08-01)

They were originally all off, on the reasoning that discovery protocols "don't
respect the VPN boundary." That reasoning does not survive contact with how the
container is wired: DHT/PeX traffic leaves through `tun0` like everything else,
so the address exposed to the swarm is the VPN exit, not the host.

The cost was concrete — six magnets sat at 0% in `metaDL` with every tracker in
their announce list dead (rarbg, coppersurfer, leechers-paradise et al. are all
defunct), surfacing in Radarr/Sonarr as:

> `qBittorrent cannot resolve magnet link with DHT disabled`

**Private trackers are unaffected either way.** Torrents carrying the BEP-27
`private` flag have DHT/PeX/LSD disabled *per-torrent* by libtorrent regardless
of the global setting, so turning these on cannot violate a private tracker's
rules.

To disable the hardening entirely (e.g. if ever run outside a VPN):

```nix
hwc.media.qbittorrent.privacy.enable = false;
```

The script then leaves qBittorrent's own defaults untouched. Individual toggles
can also be flipped without disabling the whole block, e.g.
`hwc.media.qbittorrent.privacy.dht = false;`.

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

- **2026-08-20**: Gluetun went multi-instance
  (`hwc.networking.gluetun.instances.<name>.*` replaces the flat singleton).
  The hand-copied `cfg.network.mode != "vpn" || gluetun.enable` assertion in
  `parts/config.nix` is now `helpers.mkVpnAssertions`, which checks the
  *specific* tunnel this container joins is declared and enabled — with more
  than one tunnel, "is some tunnel on" was worse than no check at all. The
  remaining path assertions are unchanged. qBittorrent keeps the forwarded port
  on the original `gluetun` instance; slskd is what needed the second tunnel
  (`0f102aa4`).
- **2026-08-01**: Split `privacy.enable` into per-protocol toggles
  (`anonymousMode`/`dht`/`pex`/`lsd`) and turned **DHT + PeX back on** by
  default. The blanket-off posture was redundant with the gluetun tunnel (the
  actual privacy boundary) while costing magnet-link support outright — six
  torrents were stranded in `metaDL` at 0%. Private torrents are governed
  per-torrent by libtorrent's `private` flag, so private trackers are not
  implicated. The enforced conf keys now derive from the options rather than a
  hardcoded set, so a toggle and its key cannot drift.
- **2026-07-03**: Made the DHT/LSD/PeX-off + anonymous-mode privacy hardening
  declarative via `privacy.enable` + a `qbittorrent-enforce-privacy` ExecStartPre
  script, and documented the rationale + magnet-link trade-off. Previously the
  settings lived only in the container's `qBittorrent.conf` (UI-set, undocumented,
  and vulnerable to a config-volume reset).
