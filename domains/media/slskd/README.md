# slskd - Soulseek Daemon

**Container Service**: Soulseek P2P file sharing client (music focus)

**Access**: https://hwc-server.ocelot-wahoo.ts.net:8443/ (port mode)

---

## Overview

slskd is a modern, web-based Soulseek client for peer-to-peer music sharing. This implementation uses containerized deployment with agenix-managed secrets for credential security.

### Key Features

- **Web UI**: Modern browser-based interface for searching and downloading music
- **Automatic Sharing**: Shares both downloaded music and existing library
- **Soularr Integration**: API key support for automated music management
- **Persistent Configuration**: All settings and credentials managed via agenix

---

## Architecture

### Service Type
- **Container**: Podman (via `virtualisation.oci-containers`)
- **Image**: `slskd/slskd:0.21.4` (pinned — see `VERSION.md`)
- **Network**: `vpn` by default — slskd lives in the netns of its **own** gluetun
  instance, `hwc.media.slskd.vpnInstance` (default `gluetun-slskd`). It does not share
  qBittorrent's tunnel: Proton forwards exactly one port per WireGuard session, and
  Soulseek without an inbound port loses uploads and degrades search/browse, which is
  what soularr depends on. `network.mode = "media"` is a **build failure** unless
  `hwc.media.slskd.allowClearnet = true`.
- **Routing**: Port mode (HTTPS port 8443) - slskd is subpath-hostile

### Directory Structure

```
/mnt/hot/downloads/
├── music/           → Complete downloads (shared as "Downloads")
└── incomplete/      → In-progress downloads

/mnt/media/music/    → Main library (93GB, shared as "Library")
```

### Configuration Management

**Runtime Secret Injection**:
1. `slskd-config-generator.service` runs after agenix, before container
2. Reads encrypted secrets from `/run/agenix/`
3. Generates `/etc/slskd/slskd.yml` with substituted values
4. Container mounts the generated config file

The generator is also the **sole producer of the Soulseek listen port**. It reads
`<gluetun.stateRoot>/<vpnInstance>/forwarded-port`, which the tunnel's port-sync writes
and which restarts this generator, and falls back to `hwc.media.slskd.listenPort`
(default 50300) off-VPN or before the first sync. One writer means Proton's rotating
NAT-PMP port cannot drift between two producers.

Directory creation is **not** done here — `domains/media/directories.nix` owns it.

**Why Runtime Generation?**

NixOS pure evaluation prevents reading `/run/agenix` at build time. The systemd service approach allows:
- Secrets remain encrypted in git
- Config generated at boot from decrypted secrets
- Changes to secrets only require rebuild (no manual config edits)
- Fully declarative and reproducible

---

## Credentials (Agenix-Managed)

All credentials are encrypted with age and stored in `domains/secrets/parts/server/`:

### Web UI Authentication
- **Username**: `slskd-admin` (secret: `slskd-web-username.age`)
- **Password**: Random 32-byte base64 (secret: `slskd-web-password.age`)
- **Location**: `/run/agenix/slskd-web-{username,password}`

### Soulseek Network
- **Username**: `eriqueok` (secret: `slskd-soulseek-username.age`)
- **Password**: User's Soulseek password (secret: `slskd-soulseek-password.age`)
- **Location**: `/run/agenix/slskd-soulseek-{username,password}`

### Soularr Integration
- **API Key**: Random key for Soularr (secret: `slskd-api-key.age`)
- **Location**: `/run/agenix/slskd-api-key`

### Rotating Credentials

To update any credential:

```bash
# 1. Get the age public key
sudo nix-shell -p age --run "age-keygen -y /etc/age/keys.txt"
# Output: age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne

# 2. Encrypt new value
echo "new-password" | nix-shell -p age --run \
  "age -r age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne" \
  | sudo tee domains/secrets/parts/server/slskd-web-password.age > /dev/null

# 3. Commit and rebuild
git add domains/secrets/parts/server/slskd-web-password.age
git commit -m "update slskd web password"
sudo nixos-rebuild switch --flake .#hwc-server
```

**Important**: Always backup old `.age` files before replacing them.

---

## Shares Configuration

### Current Shared Directories

slskd uses the `[alias]path` notation for shares:

```nix
shares = {
  directories = [
    "[Downloads]/downloads/music"  # New downloads (hot storage)
    "[Library]/music"              # Main collection (93GB, read-only)
  ];
};
```

**Statistics** (as of 2025-11-06):
- **619 directories** shared
- **6,246 music files** indexed
- Total size: ~93GB

### Adding New Shares

Edit `domains/media/slskd/parts/config.nix`:

```nix
shares = {
  directories = [
    "[Downloads]/downloads/music"
    "[Library]/music"
    "[NewShare]/path/to/new/directory"  # Add new share
  ];
};
```

Then rebuild:
```bash
git add domains/media/slskd/parts/config.nix
git commit -m "add new slskd share"
sudo nixos-rebuild switch --flake .#hwc-server
```

### Share Naming Requirements

From slskd documentation:
- Aliases must be unique and at least one character
- Cannot contain path separators (`\` or `/`)
- Without explicit alias, the folder name is used as the alias
- Paths must be absolute (begin with `/`, `X:\`, or `\\`)

---

## Networking

### Ports

**On the VPN (the default), slskd publishes nothing of its own.** It has no interface:
the web UI is published by the gluetun instance's `ports`, and the inbound Soulseek path
is the tunnel's forwarded port on the tunnel's interface.

Off-VPN only (`network.mode = "media"` + `allowClearnet = true`):

- **5031** (host) → **5030** (container): Web UI (HTTP, proxied via Caddy HTTPS 8443)
- **`listenPort`** (host) → same (container): Soulseek P2P (TCP), default 50300

### Firewall

```nix
networking.firewall.allowedTCPPorts =
  lib.optionals (cfg.network.mode != "vpn") [ cfg.listenPort 5031 ];
```

The host firewall is only meaningful off-VPN — it is not in the inbound path when slskd
sits inside the tunnel's namespace.

### Caddy Route

Port mode (subpath-hostile application):

```nix
{
  name = "slskd";
  mode = "port";
  port = 8443;  # External HTTPS port
  upstream = "http://127.0.0.1:5031";
}
```

**Why Port Mode?**

slskd doesn't support URL base configuration and hardcodes paths in JavaScript/assets. Port mode allows the app to run at root path without reverse proxy complications.

---

## Service Dependencies

On the VPN:

```
agenix.service
    ↓
slskd-config-generator.service (config + forwarded port from secrets/port file)
    ↓
podman-gluetun-slskd.service (the tunnel)
    ↓
podman-slskd.service (joins the tunnel's netns)
```

`podman-slskd` carries `bindsTo` + `partOf` on the tunnel unit (qBittorrent's shape), so a
container whose netns is gone goes away with it rather than lingering in an undefined
network state. The cost is an slskd restart whenever the tunnel restarts — an in-flight
transfer is worth less than a known egress. Off-VPN it orders after
`init-media-network.service` instead.

### Restart Behavior

```bash
# Full restart (regenerate config)
sudo systemctl restart slskd-config-generator
sudo systemctl restart podman-slskd

# Container only (uses existing config)
sudo systemctl restart podman-slskd

# Check status
systemctl status slskd-config-generator
systemctl status podman-slskd
```

---

## Troubleshooting

### Issue: Shares Show as Empty (0 files)

**Symptom**: slskd logs show "Found 0 shared directories and 0 files"

**Causes**:
1. Incorrect YAML format in shares.directories
2. Volume mounts not accessible to container
3. File permissions issues

**Solution**:
```bash
# Verify container can see mounts
sudo podman exec $(sudo podman ps -q --filter "name=slskd") ls /music
sudo podman exec $(sudo podman ps -q --filter "name=slskd") ls /downloads/music

# Check config format in container
sudo podman exec $(sudo podman ps -q --filter "name=slskd") cat /app/slskd.yml

# Verify shares use correct format
# CORRECT:   "[Downloads]/downloads/music"
# INCORRECT: "/downloads/music" or {path: "/downloads/music", alias: "Downloads"}
```

### Issue: Web UI Shows "Connection Refused"

**Check service status**:
```bash
systemctl status podman-slskd
journalctl -u podman-slskd -n 50
```

**Verify config generator ran**:
```bash
systemctl status slskd-config-generator
cat /etc/slskd/slskd.yml  # Should have actual credentials, not variable names
```

### Issue: Cannot Login to Web UI

**Retrieve credentials**:
```bash
# Username
sudo cat /run/agenix/slskd-web-username

# Password
sudo cat /run/agenix/slskd-web-password
```

**Reset password**:
```bash
# Generate new password
nix-shell -p openssl age --run \
  "openssl rand -base64 32 | age -r age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne" \
  | sudo tee domains/secrets/parts/server/slskd-web-password.age > /dev/null

# Rebuild and restart
sudo nixos-rebuild switch --flake .#hwc-server
sudo systemctl restart slskd-config-generator podman-slskd
```

### Issue: Not Connecting to Soulseek Network

**Check logs**:
```bash
journalctl -u podman-slskd -f | grep -i "soulseek\|connect\|login"
```

**Verify credentials**:
```bash
sudo cat /run/agenix/slskd-soulseek-username
sudo cat /run/agenix/slskd-soulseek-password
```

**Common causes**:
- Incorrect Soulseek password
- On the VPN: the tunnel is down, or no forwarded port has been synced yet (check
  `<gluetun.stateRoot>/<vpnInstance>/forwarded-port` and the instance's port-sync unit)
- Off-VPN: `listenPort` blocked by firewall
- Network connectivity issues

---

## Maintenance

### Updating Container Image

The image is **pinned** via `hwc.media.slskd.image` (default `slskd/slskd:0.21.4`), not
`:latest`. Bump the option default in `index.nix`, record it in `VERSION.md`, commit, then
rebuild — `podman pull` alone changes nothing, since the pinned tag is what the unit runs.

```bash
# After bumping the pin and rebuilding, confirm the version in logs
journalctl -u podman-slskd | grep -i "version"
```

### Monitoring Share Statistics

```bash
# Watch share scan in real-time
journalctl -u podman-slskd -f | grep -i "scan\|share"

# Get final statistics
journalctl -u podman-slskd --since "5 minutes ago" | grep "Sharing.*directories.*files"
```

### Clearing Download Cache

```bash
# Clear incomplete downloads
sudo rm -rf /mnt/hot/downloads/incomplete/*

# Clear completed downloads (be careful!)
sudo rm -rf /mnt/hot/downloads/music/*

# Restart to rescan
sudo systemctl restart podman-slskd
```

---

## Configuration Files

### Primary Configuration

```
domains/media/slskd/
├── index.nix          # hwc.media.slskd.* options + VPN assertions
├── sys.nix            # mkContainer wiring, conditional ports/firewall, unit ordering
├── parts/config.nix   # slskd.yml generator (secrets + forwarded port)
├── VERSION.md         # image pin tracking
└── README.md          # This file
```

There is no `options.nix` — options are declared inline in `index.nix`.

### Secret Declarations
- **Location**: `domains/secrets/declarations/server.nix`
- **Encrypted Files**: `domains/secrets/parts/server/slskd-*.age`

### Generated Runtime Files
- **Config**: `/etc/slskd/slskd.yml` (generated at boot)
- **Decrypted Secrets**: `/run/agenix/slskd-*` (ephemeral)

---

## Implementation Notes

### Lessons Learned

#### Share Configuration Format (2025-11-06)

**Problem**: Shares showing as empty despite correct mounts

**Root Cause**: Incorrect YAML format for shares.directories

**Solution**: Use `[alias]path` notation per slskd documentation:

```nix
# ❌ INCORRECT (object format)
shares.directories = [
  { path = "/downloads/music"; alias = "Downloads"; }
];

# ❌ INCORRECT (plain paths)
shares.directories = [
  "/downloads/music"
];

# ✅ CORRECT (bracket alias notation)
shares.directories = [
  "[Downloads]/downloads/music"
];
```

#### Secret Management (2025-11-06)

**Problem**: Cannot read `/run/agenix` secrets at build time

**Root Cause**: NixOS pure evaluation mode forbids absolute path access

**Solution**: Runtime config generation via systemd service:
1. `slskd-config-generator.service` runs after agenix
2. Shell script reads decrypted secrets from `/run/agenix/`
3. Generates `/etc/slskd/slskd.yml` with substituted values
4. Container mounts the generated file

**Advantages**:
- Secrets never in Nix store
- Fully declarative (no manual config files)
- Survives all rebuilds
- Easy credential rotation

---

## References

### Documentation
- **slskd GitHub**: https://github.com/slskd/slskd
- **slskd Config Docs**: https://github.com/slskd/slskd/blob/master/docs/config.md
- **Example Config**: https://github.com/slskd/slskd/blob/master/config/slskd.example.yml

### Related Services
- **Soularr**: Automated music requests (uses slskd API)
- **Lidarr**: Music collection manager
- **Navidrome**: Music streaming server

### HWC Documentation
- **Server Services**: `domains/server/SERVICES.md`
- **Container Guide**: `docs/projects/server-container-scaffolding.md`
- **Secrets Management**: `domains/secrets/README.md` (if exists)
- **HWC Charter**: `charter.md`

---

## Changelog

- 2026-09-10: `parts/config.nix` comment corrected — directory creation comes from
  `media/directories.nix`, not `_shared/directories.nix`. Part of making
  `/mnt/media/youtube` single-producer; no behavior change here.
- 2026-08-20: slskd moved into its **own** gluetun tunnel and can no longer leave it by
  accident. `network.mode` now defaults to `"vpn"` and `"media"` is a build failure unless
  the new `allowClearnet` is set — it had defaulted to `"media"` since the module was
  written, so slskd egressed on the house IP for six weeks (~29.4 GB out, 15.5 GB in) while
  every sibling downloader was tunnelled; the ordering line that looked like it wired slskd
  to gluetun lived in a module whose `enable` was never set. New options `vpnInstance`
  (default `gluetun-slskd`, its own Proton key — one forwarded port per WireGuard session)
  and `listenPort` (default 50300, the off-VPN/pre-sync fallback). The hand-copied
  "is gluetun enabled" assertion was replaced by `mkVpnAssertions`, which checks the
  **specific** tunnel the container joins. `sys.nix` publishes ports and opens the firewall
  only off-VPN, and `podman-slskd` gained `bindsTo`/`partOf` on the tunnel unit. The config
  generator became the sole writer of `listen_port`, taking the tunnel's forwarded port.

---

**Last Updated**: 2026-09-10
**Architecture Version**: HWC 6.0
**Module Version**: Container with runtime secret injection
