# Frigate NVR - Config-First Pattern

**Charter v7.0 Section 19 Compliant**
**Namespace**: `hwc.server.frigate.*`
**Status**: ✅ Production - Active

---

## Overview

Frigate NVR implementation following the **config-first, Nix-second** pattern established in Charter v7.0 Section 19.

**Key Features**:
- ✅ Configuration in version-controlled `config/config.yml` (not Nix-generated)
- ✅ Portable (works with Docker/Podman/k8s)
- ✅ Debuggable (edit config directly, restart service)
- ✅ Frigate 0.16.2-tensorrt (pinned with GPU support)
- ✅ Nix handles infrastructure only (image, GPU, ports, volumes)
- ✅ GPU-accelerated object detection (TensorRT + CUDA on NVIDIA P1000)
- ✅ External access via Caddy reverse proxy

**Access**: https://hwc.ocelot-wahoo.ts.net:5443

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
│   ├── config.baseline.yml     # Snapshot for reference
│   └── README.md               # Config documentation
├── scripts/
│   └── verify-config.sh        # Config validation script
└── README.md                   # This file
```

---

## Configuration

### Machine Setup

```nix
# machines/server/config.nix
hwc.server.frigate = {
  enable = true;

  # Internal port 5001 (exposed as 5443 via Caddy)
  port = 5001;

  # GPU acceleration for ONNX object detection (TensorRT + CUDA)
  gpu = {
    enable = true;
    device = 0;  # NVIDIA P1000
  };

  # Storage paths
  storage = {
    configPath = "/opt/surveillance/frigate-v2/config";
    mediaPath = "/mnt/media/surveillance/frigate-v2/media";
    bufferPath = "/mnt/hot/surveillance/frigate-v2/buffer";
  };

  # Firewall (restrict to Tailscale)
  firewall.tailscaleOnly = true;
};
```

**Note**: Storage paths currently use "frigate-v2" directories (preserving existing data). These can be renamed to "frigate" when ready.

### Frigate Configuration

**Primary config file**: `config/config.yml`

**To modify Frigate behavior**:
1. Edit `config/config.yml`
2. Validate: `./scripts/verify-config.sh`
3. Restart: `sudo systemctl restart podman-frigate.service`
4. Commit when stable

See [`config/README.md`](config/README.md) for detailed config documentation.

### External Access

Frigate is exposed externally via Caddy reverse proxy:

- **Internal**: `http://localhost:5001` (container port)
- **External**: `https://hwc.ocelot-wahoo.ts.net:5443` (Caddy via Tailscale)

**Configuration**: `domains/server/routes.nix`
```nix
{
  name = "frigate";
  mode = "port";
  port = 5443;
  upstream = "http://127.0.0.1:5001";
}
```

The reverse proxy is configured in port mode (not subpath) because Frigate's web UI doesn't work well with subpath routing.

---

## Dependencies

**Required**:
- `hwc.infrastructure.hardware.gpu.enable = true` (for GPU acceleration)
- `hwc.secrets.enable = true` (for RTSP credentials)
- `virtualisation.oci-containers.backend = "podman"`

**Validated at build time** - will fail with clear error if missing.

---

## Deployment Status

### Current State: ✅ Production

**Deployed**:
- ✅ Charter v7.0 Section 19 compliant (config-first pattern)
- ✅ Module structure created and active
- ✅ Infrastructure-only options defined
- ✅ Container running (frigate:0.16.2-tensorrt)
- ✅ GPU acceleration validated (TensorRT + CUDA)
- ✅ Config validation script
- ✅ External access via Caddy (https://hwc.ocelot-wahoo.ts.net:5443)
- ✅ Old module removed (no ambiguity)
- ✅ All references renamed from frigate-v2 to frigate

**Service Details**:
- **Service**: `podman-frigate.service`
- **Container**: `frigate`
- **Image**: `ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt`
- **Status**: Active (running)
- **GPU**: NVIDIA Quadro P1000 with TensorRT support

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

---

## References

- **Charter v7.0 Section 19**: Complex Service Configuration Pattern
- **Frigate Documentation**: https://docs.frigate.video/
- **Config Documentation**: [config/README.md](config/README.md)
- **Validation Script**: [scripts/verify-config.sh](scripts/verify-config.sh)

---

**Created**: 2025-11-23
**Last Updated**: 2025-11-24
**Charter Version**: v7.0
**Module Version**: 1.0.0 (config-first)
**Status**: Production
