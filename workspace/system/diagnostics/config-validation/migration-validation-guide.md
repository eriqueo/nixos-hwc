# NixOS Configuration Migration Validation Guide

This guide helps validate that your refactored NixOS configuration maintains 100% functional parity with the original monolithic setup.

## Quick Reference

```bash
# 1. Capture current state
sudo ./system-distiller.py > current-system.json

# 2. Build and compare new config  
cd /path/to/new-repo
nixos-rebuild build --flake .#hwc-server
sudo ./system-distiller.py > new-system.json

# 3. Compare configurations
./config-differ.sh current-system.json new-system.json

# 4. Focus on critical areas
./config-differ.sh current-system.json new-system.json --section=containers
```

## Critical Items to Verify

### ✅ Container Volume Mounts
These must be preserved exactly:

**SABnzbd Events Mount (Critical Fix from 2025-09-28):**
```
/mnt/hot/events:/mnt/hot/events:rw
```

**SABnzbd Script Access:**
```
/opt/downloads/scripts:/config/scripts:ro
```

**All Media Storage Mounts:**
- Hot storage: `/mnt/hot/downloads:/downloads`
- Cache: `/mnt/hot/cache:/incomplete-downloads` 
- Config: `/opt/downloads/SERVICE:/config`

### ✅ Network Dependencies
Verify these container dependency chains:

1. **VPN Chain**: `gluetun` → `qbittorrent` + `sabnzbd`
2. **Media Chain**: Downloads → *arr apps → Soularr
3. **Events Chain**: Downloads → `sab-finished.py` → `media-orchestrator`

### ✅ Environment Variables
Check these are consistent:
- `PUID=1000`, `PGID=1000`
- `TZ=America/Denver`
- GPU environment variables
- API keys and secrets paths

### ✅ Port Mappings
Verify all services are accessible:
- Direct ports: qBittorrent (8080), SABnzbd (8081)
- *arr apps: Sonarr (8989), Radarr (7878), Lidarr (8686), Prowlarr (9696)
- Media: Jellyfin (8096), Navidrome (4533)

## Validation Workflow

### 1. System Distillation
```bash
# Current system
sudo ./system-distiller.py > current-system.json

# New system (after building)
sudo ./system-distiller.py > new-system.json
```

### 2. Container Comparison
```bash
# Check all containers
./config-differ.sh current-system.json new-system.json --section=containers

# Specifically check SABnzbd
jq '.containers.sabnzbd.volumes' current-system.json
jq '.containers.sabnzbd.volumes' new-system.json
```

### 3. Service Comparison  
```bash
# Check systemd services
./config-differ.sh current-system.json new-system.json --section=services

# Look for missing or changed services
```

### 4. Network Validation
```bash
# Check listening ports
./config-differ.sh current-system.json new-system.json --section=networking

# Verify reverse proxy routes
curl -I https://hwc.ocelot-wahoo.ts.net/sonarr
```

## Expected Differences (OK to ignore)

These differences are expected and safe:

- **File paths**: Old uses `/etc/nixos/hosts/server/modules/`, new uses `/home/eric/.nixos/domains/`
- **Module structure**: Different import paths but same functionality
- **Build hashes**: Nix store paths will be different
- **Service ordering**: May differ but dependencies preserved

## Red Flags (Must Fix)

Stop and fix these issues immediately:

- ❌ Missing container volumes (especially `/mnt/hot/events`)
- ❌ Changed container images or versions
- ❌ Missing environment variables or API keys
- ❌ Broken network dependencies (VPN isolation)
- ❌ Missing systemd services
- ❌ Changed port bindings

## Critical Services Checklist

After comparison, manually verify these work:

- [ ] **Downloads**: qBittorrent and SABnzbd accessible via Caddy
- [ ] ***arr Apps**: All accessible via `/sonarr`, `/radarr`, etc.
- [ ] **Media Orchestrator**: Events flowing from downloads to *arr rescans
- [ ] **GPU Acceleration**: Container GPU access for transcoding/AI
- [ ] **Secrets**: All SOPS secrets accessible and mounted correctly
- [ ] **Storage**: Hot/cold storage mounts and migration working

## Testing SABnzbd Events Fix

This is the most critical recent fix to verify:

```bash
# 1. Check volume mount exists
jq '.containers.sabnzbd.volumes[] | select(contains("/mnt/hot/events"))' new-system.json

# 2. After deployment, test script execution
sudo podman exec sabnzbd ls -la /mnt/hot/events/
sudo podman exec sabnzbd python3 /config/scripts/sab-finished.py

# 3. Verify media orchestrator processes events
cat /var/lib/node_exporter/textfile_collector/media_orchestrator.prom
```

## Recovery Plan

If issues found:

1. **Don't switch the server** - stay on current config
2. **Fix issues in new repo** based on distiller output
3. **Re-run comparison** until clean
4. **Test incrementally** - build → compare → fix → repeat

## Final Validation

Before switching server configuration:

```bash
# 1. Clean comparison
./config-differ.sh current-system.json new-system.json
# Should show minimal/expected differences only

# 2. Test build succeeds
nixos-rebuild build --flake .#hwc-server

# 3. All critical services present
jq '.containers | keys' new-system.json
# Should list: gluetun, qbittorrent, sabnzbd, sonarr, radarr, lidarr, prowlarr, etc.

# 4. SABnzbd events mount verified
jq '.containers.sabnzbd.volumes[] | select(contains("events"))' new-system.json
```

Only switch when this guide shows green across all checks.