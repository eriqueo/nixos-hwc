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
- **Image**: `slskd/slskd:latest`
- **Network**: its own gluetun tunnel by default (`vpn`); `media-network` only with `allowClearnet` (see Networking)
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

Edit `domains/server/containers/slskd/parts/config.nix`:

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
git add domains/server/containers/slskd/parts/config.nix
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

### Mode (default `vpn`)

`network.mode` defaults to `"vpn"`: slskd runs inside its own gluetun instance
(`vpnInstance`, default `gluetun-slskd`), not qBittorrent's, because Proton
forwards one port per WireGuard session. `network.mode = "media"` fails the
build unless `allowClearnet = true` is set explicitly. The option defaulted to
`"media"` until 2026-08-20, and slskd egressed on the house IP for about six weeks.

### Ports

- VPN mode: slskd publishes no host ports and opens no host firewall ports. The
  tunnel instance publishes the web UI as `127.0.0.1:5031 → 5030` (set on the
  instance in `machines/home/config.nix`). The Soulseek listen port is the tunnel's
  NAT-PMP forwarded port, read by `slskd-config-generator` from
  `${hwc.networking.gluetun.stateRoot}/<vpnInstance>/forwarded-port`; before the
  first sync it falls back to `listenPort` (default 50300).
- Clearnet mode: **5031** (host) → **5030** (container) for the web UI, and
  `listenPort` (host) → `listenPort` (container) for Soulseek P2P; the firewall
  opens both.

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

```
agenix.service
    ↓
slskd-config-generator.service (generates config from secrets + forwarded port)
    ↓
podman-<vpnInstance>.service  (VPN mode; slskd bindsTo/partOf it)
  or init-media-network.service (clearnet mode)
    ↓
podman-slskd.service (starts container)
```

In VPN mode slskd restarts whenever its tunnel restarts.

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
- No forwarded port yet (VPN mode) or `listenPort` blocked by firewall (clearnet mode)
- Network connectivity issues

---

## Maintenance

### Updating Container Image

The module uses `slskd/slskd:latest` which can be updated:

```bash
# Pull latest image
sudo podman pull slskd/slskd:latest

# Restart container
sudo systemctl restart podman-slskd

# Check version in logs
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
- **Module**: `domains/media/slskd/`
- **Options**: `index.nix` (enable, image, network mode, vpnInstance, allowClearnet, listenPort; assertions)
- **System Integration**: `sys.nix` (podman backend)
- **Container Config**: `parts/config.nix` (main config generation)

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

**Last Updated**: 2025-11-06
**Architecture Version**: HWC 6.0
**Module Version**: Container with runtime secret injection

## Structure

```
slskd/
├── index.nix        # Options + assertions (VPN default, allowClearnet escape hatch)
├── sys.nix          # mkContainer wiring, conditional ports/firewall, tunnel dependencies
├── parts/config.nix # slskd-config-generator (secrets + forwarded listen port → slskd.yml)
├── VERSION.md
└── README.md
```

## Changelog

- 2026-09-10: Comment in `parts/config.nix` now points directory creation at
  `media/directories.nix` (ca49bf2b). No behavior change.
- 2026-08-20: slskd moved into its own gluetun tunnel (0f102aa4).
  `network.mode` defaults to `vpn`; new `vpnInstance` (default `gluetun-slskd`),
  `allowClearnet` and `listenPort` options. A clearnet mode without
  `allowClearnet` fails the build, and `mkVpnAssertions` checks the instance.
  In VPN mode host ports and firewall openings are dropped, the listen port
  follows the tunnel's forwarded-port file, and `podman-slskd` binds to and is
  part of `podman-<vpnInstance>.service`.
