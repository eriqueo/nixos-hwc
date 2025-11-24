# Frigate NVR - Config-First Pattern (v2)

**Charter v7.0 Section 19 Compliant**
**Namespace**: `hwc.server.frigate.*`
**Status**: 🚧 Under Development (not yet deployed)

---

## Overview

This is the **next-generation Frigate module** built following the **config-first, Nix-second** pattern established in Charter v7.0 Section 19.

**Key Differences from `domains/server/frigate/`**:
- ✅ Configuration in version-controlled `config/config.yml` (not Nix-generated)
- ✅ Portable (works with Docker/Podman/k8s)
- ✅ Debuggable (edit config directly, restart service)
- ✅ Modern Frigate 0.16.2 (pinned)
- ✅ Nix handles infrastructure only (image, GPU, ports, volumes)

---

## Architecture

### Config-First Pattern

**Nix Responsibilities** (`options.nix`, `index.nix`):
- Container image/version
- GPU/device passthrough
- Port mappings
- Volume mounts
- Resource limits
- Environment variables

**Config File Responsibilities** (`config/config.yml`):
- Camera definitions
- Detector configuration
- Recording settings
- Object tracking
- Zones/masks
- All Frigate-specific settings

### Directory Structure

```
domains/server/frigate/
├── options.nix                 # Infrastructure options (image, GPU, ports)
├── index.nix                   # Container definition (no YAML generation!)
├── config/
│   ├── config.yml              # CANONICAL CONFIG (version-controlled)
│   ├── config.baseline.yml     # Snapshot from old module (reference)
│   └── README.md               # Config documentation
├── scripts/
│   └── verify-config.sh        # Config validation script
├── docs/                       # Inherited documentation
│   ├── HARDWARE-ACCELERATION.md  # (symlink to ../frigate/)
│   ├── TUNING-GUIDE.md          # (symlink to ../frigate/)
│   └── CONFIGURATION-RETROSPECTIVE.md  # (symlink to ../frigate/)
├── MIGRATION-TO-CONFIG-FIRST.md  # Migration plan
└── README.md                   # This file
```

---

## Configuration

### Machine Setup

```nix
# machines/server/config.nix
hwc.server.frigate = {
  enable = true;  # Enable the new module

  image = "ghcr.io/blakeblackshear/frigate:0.16.2";  # Explicit version

  gpu = {
    enable = true;  # GPU acceleration for object detection
    device = 0;     # NVIDIA GPU 0
  };

  # Storage paths (defaults shown)
  storage = {
    configPath = "/opt/surveillance/frigate/config";
    mediaPath = "/mnt/media/surveillance/frigate/media";
    bufferPath = "/mnt/hot/surveillance/buffer";
  };

  # Container resources
  resources = {
    memory = "4g";
    cpus = "1.5";
    shmSize = "1g";
  };

  # Firewall (restrict to Tailscale)
  firewall.tailscaleOnly = true;
};
```

### Frigate Configuration

**Primary config file**: `config/config.yml`

**To modify Frigate behavior**:
1. Edit `config/config.yml`
2. Validate: `./scripts/verify-config.sh`
3. Restart: `sudo systemctl restart podman-frigate.service`
4. Commit when stable

See [`config/README.md`](config/README.md) for detailed config documentation.

---

## Dependencies

**Required**:
- `hwc.infrastructure.hardware.gpu.enable = true` (for GPU acceleration)
- `hwc.secrets.enable = true` (for RTSP credentials)
- `virtualisation.oci-containers.backend = "podman"`

**Validated at build time** - will fail with clear error if missing.

---

## Migration Status

### Current State: 🚧 Development

**Completed**:
- [x] Charter v7.0 Section 19 added (config-first pattern)
- [x] Module structure created
- [x] Infrastructure-only options defined
- [x] Container definition (config-first)
- [x] Verification script
- [x] Documentation

**In Progress**:
- [ ] Extract runtime config from current Frigate
- [ ] Populate `config/config.yml` with real cameras
- [ ] Handle secrets (environment vars or templating)
- [ ] Test in parallel with current Frigate module
- [ ] Validate GPU acceleration
- [ ] 48-hour stability test

**Not Started**:
- [ ] Cutover from old module
- [ ] Archive old module
- [ ] Update server profile to use frigate

See [`MIGRATION-TO-CONFIG-FIRST.md`](../frigate/MIGRATION-TO-CONFIG-FIRST.md) for full migration plan.

---

## Usage

### Starting/Stopping

```bash
# Stop service
sudo systemctl stop podman-frigate.service

# Start service
sudo systemctl start podman-frigate.service

# Restart (after config changes)
sudo systemctl restart podman-frigate.service

# Check status
sudo systemctl status podman-frigate.service
```

### Viewing Logs

```bash
# Container logs
podman logs frigate
podman logs frigate --tail 100
podman logs frigate --follow

# Systemd service logs
journalctl -u podman-frigate.service -f
```

### Inspecting Config

```bash
# View config as Frigate sees it
podman exec frigate cat /config/config.yml

# Compare with our source
diff domains/server/frigate/config/config.yml \
     <(podman exec frigate cat /config/config.yml)
```

### Validation

```bash
# Verify config structure
./domains/server/frigate/scripts/verify-config.sh

# Check that model block is top-level
grep -A 10 "^model:" config/config.yml

# Check for input_dtype field
grep "input_dtype:" config/config.yml
```

---

## Troubleshooting

### Service Won't Start

```bash
# Check assertions (Nix validation)
sudo nixos-rebuild build --flake .#hwc-server --show-trace

# Check container logs for errors
podman logs frigate --tail 50
```

### Config Changes Not Applying

```bash
# 1. Verify config.yml in container matches your local file
podman exec frigate cat /config/config.yml | diff - config/config.yml

# 2. If different, rebuild NixOS
sudo nixos-rebuild switch --flake .#hwc-server

# 3. Restart container
sudo systemctl restart podman-frigate.service
```

### ONNX Dtype Errors

If you see:
```
Unexpected input data type. Actual: (tensor(uint8)), expected: (tensor(float))
```

**Fix**:
1. Check that `model` block is **top-level** (not nested under `detectors`)
2. Ensure `input_dtype: float` is present
3. Validate: `./scripts/verify-config.sh`

See [CONFIGURATION-RETROSPECTIVE.md](../frigate/CONFIGURATION-RETROSPECTIVE.md) for detailed analysis.

---

## Comparison with Old Module

| Aspect | Old (frigate) | New (frigate) |
|--------|---------------|------------------|
| **Config Source** | Nix-generated YAML | `config/config.yml` file |
| **Debugging** | Edit Nix → rebuild → inspect generated YAML | Edit config.yml → restart |
| **Portability** | NixOS-only | Works with Docker/Podman/k8s |
| **Version** | 0.15.1-tensorrt (implicit) | 0.16.2 (explicit pin) |
| **Nix Options** | 50+ options for Frigate config | 15 options for infrastructure only |
| **Documentation** | Comprehensive (inherited) | Config-first focused |
| **Validation** | Build-time Nix assertions | Config validation script + assertions |

---

## References

- **Charter v7.0 Section 19**: Complex Service Configuration Pattern
- **Migration Plan**: [MIGRATION-TO-CONFIG-FIRST.md](../frigate/MIGRATION-TO-CONFIG-FIRST.md)
- **Retrospective**: [CONFIGURATION-RETROSPECTIVE.md](../frigate/CONFIGURATION-RETROSPECTIVE.md)
- **Frigate Docs**: https://docs.frigate.video/
- **Hardware Acceleration**: [docs/HARDWARE-ACCELERATION.md](docs/HARDWARE-ACCELERATION.md)

---

## Development Roadmap

**Phase 1**: Setup (Complete ✅)
- Module structure
- Config-first pattern
- Documentation

**Phase 2**: Config Extraction (Next)
- Extract runtime config from current Frigate
- Populate `config/config.yml`
- Handle secrets

**Phase 3**: Testing
- Parallel deployment with current Frigate
- GPU validation
- Stability testing (48+ hours)

**Phase 4**: Cutover
- Switch server profile to frigate
- Archive old module
- Update documentation

---

**Created**: 2025-11-23
**Charter Version**: v7.0
**Module Version**: 1.0.0 (config-first)
**Status**: Development
