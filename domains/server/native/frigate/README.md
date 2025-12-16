# Frigate NVR - Network Video Recorder

**Version**: 0.16.2-tensorrt
**Domain**: `hwc.server.frigate`
**Architecture**: Config-First Pattern (Charter v7.0 Section 19 Compliant)
**Status**: ✅ Production - Optimized (Sprint 1 Complete)

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Configuration](#configuration)
4. [GPU Acceleration](#gpu-acceleration)
5. [Storage Management](#storage-management)
6. [Camera Configuration](#camera-configuration)
7. [Recording & Retention](#recording--retention)
8. [Performance Optimization](#performance-optimization)
9. [Monitoring](#monitoring)
10. [Implementation Status](#implementation-status)
11. [Testing & Validation](#testing--validation)
12. [Troubleshooting](#troubleshooting)
13. [Architecture Details](#architecture-details)

---

## Overview

Frigate is a complete and local NVR designed for Home Assistant with AI object detection. This implementation uses:

- **Container**: Podman with GPU passthrough
- **Hardware**: NVIDIA Quadro P1000 with CUDA/NVDEC acceleration
- **Detection**: ONNX runtime with YOLOv9-s model
- **Cameras**: 3 Cobra RTSP cameras (cobra_cam_1, cobra_cam_2, cobra_cam_3)
- **Storage**: Motion-based recording with 7-day retention
- **Security**: Agenix-encrypted secrets for RTSP credentials

### Key Features

✅ GPU-accelerated object detection (28ms inference)
✅ Hardware video decoding (NVDEC)
✅ Motion-based recording (60-70% storage savings vs continuous)
✅ Configurable detection zones per camera
✅ Longer retention for persons and vehicles
✅ RTSP stream restreaming via go2rtc
✅ Secure credential management with agenix

---

## Quick Start

### Access Frigate

**Web UI**: `http://hwc-server:5001` or `http://localhost:5001` (on server)
**External**: `https://hwc.ocelot-wahoo.ts.net:5443` (via Caddy reverse proxy)
**Tailscale**: Restricted to `tailscale0` interface for external access

### Check Status

```bash
# Service status
systemctl status podman-frigate.service

# View logs
journalctl -u podman-frigate.service -f

# Check API
curl -s http://localhost:5001/api/stats | jq '.service.version, .cameras | keys'

# Check camera stats
curl -s http://localhost:5001/api/stats | jq '.cameras | to_entries[] | {camera: .key, fps: .value.camera_fps, detection_fps: .value.detection_fps}'

# Check detector performance
curl -s http://localhost:5001/api/stats | jq '.detectors'
```

### Verify GPU Usage

```bash
# Check NVIDIA GPU (should show <30ms inference in API stats)
nvidia-smi

# Check detector inference speed
curl -s http://localhost:5001/api/stats | jq '.detectors.onnx.inference_speed'
# Expected: ~28ms (GPU-accelerated)
```

---

## Configuration

### NixOS Options

All configuration via `hwc.server.frigate.*` namespace:

```nix
hwc.server.frigate = {
  enable = true;
  image = "ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt";
  port = 5001;

  # GPU acceleration
  gpu = {
    enable = true;
    device = 0;  # NVIDIA GPU index
  };

  # Storage paths
  storage = {
    configPath = "/opt/surveillance/frigate/config";
    mediaPath = "/mnt/media/surveillance/frigate/media";
    bufferPath = "/mnt/hot/surveillance/frigate/buffer";
  };

  # Resource limits
  resources = {
    memory = "4g";
    cpus = "4.0";
    shmSize = "512m";
  };

  # Firewall
  firewall.tailscaleOnly = true;  # Restrict to Tailscale
};
```

### Config File Structure

**Template**: `domains/server/frigate/config/config.yml` (version-controlled)
**Runtime**: `/opt/surveillance/frigate/config/config.yaml` (generated with secrets)

The config template uses environment variable substitution for secrets:

- `${RTSP_USER}` - RTSP username
- `${RTSP_PASS_ENCODED}` - URL-encoded RTSP password
- `${CAM1_IP}`, `${CAM2_IP}`, `${CAM3_IP}` - Camera IP addresses

**Key Sections**:

1. **Detectors**: ONNX with CUDA acceleration
2. **Model**: YOLOv9-s-320 for fast inference
3. **FFmpeg**: NVDEC hardware decoding
4. **Record**: Motion-based with 7-day retention
5. **Snapshots**: Event snapshots with retention
6. **Objects**: Detection filters per object type
7. **Cameras**: Per-camera configuration with zones

---

## GPU Acceleration

### Hardware Setup

**GPU**: NVIDIA Quadro P1000
**Driver**: Proprietary NVIDIA drivers via `hwc.infrastructure.hardware.gpu.enable`
**Compute**: CUDA 12.x
**Video Decode**: NVDEC

### Detector Configuration

```yaml
detectors:
  onnx:
    type: onnx
    device: '0'
    num_threads: 4
    execution_providers:
      - cuda
      - cpu  # Fallback
```

**Model**: YOLOv9-s-320
- **Location**: `/opt/surveillance/frigate/config/models/yolov9-s-320.onnx`
- **Input**: 320x320 BGR
- **Inference Speed**: ~28ms (GPU-accelerated)

### Video Decode Acceleration

```yaml
ffmpeg: &ffmpeg_defaults
  hwaccel_args:
    - -hwaccel
    - nvdec           # NVIDIA hardware decoder
    - -hwaccel_device
    - '0'             # GPU index
    - -hwaccel_output_format
    - yuv420p
```

**Benefits**:
- Reduced CPU usage for video decoding
- Lower latency for detection
- More efficient multi-camera handling

### Validation

```bash
# Check inference speed (should be <30ms)
curl -s http://localhost:5001/api/stats | jq '.detectors.onnx.inference_speed'

# Expected: 25-30ms (GPU) vs 100-200ms (CPU)
```

---

## Storage Management

### Directory Structure

```
/mnt/media/surveillance/frigate/
└── media/                      # Recordings and snapshots
    ├── cobra_cam_1/
    ├── cobra_cam_2/
    └── cobra_cam_3/

/mnt/hot/surveillance/frigate/
└── buffer/                     # Temporary buffer (high-speed storage)

/opt/surveillance/frigate/
└── config/
    ├── config.yaml             # Runtime config (generated)
    ├── models/
    │   └── yolov9-s-320.onnx
    └── labelmap/
        └── coco-80.txt
```

### Storage Requirements

**Motion Recording** (current):
- **Per Camera**: ~3-5 GB/week (varies by motion)
- **Total (3 cameras)**: ~8-15 GB/week
- **7-day retention**: ~25-50 GB total

**Continuous Recording** (for comparison):
- Would be ~23 GB/week per camera (~69 GB total)
- Motion mode saves **60-70% storage**

### Cleanup

Frigate automatically manages retention based on configuration:

```yaml
record:
  retain:
    days: 7
    mode: motion  # Only record when motion detected

snapshots:
  retain:
    default: 10      # Default 10 days
    objects:
      person: 30     # Keep person snapshots 30 days
      car: 14
      truck: 14
```

---

## Camera Configuration

### Camera Overview

| Camera | Resolution | FPS | Purpose | Zone |
|--------|-----------|-----|---------|------|
| cobra_cam_1 | 1280x720 | 5 | Yard/Gate | `yard_gate` |
| cobra_cam_2 | 640x360 | 3 | Porch | `porch_area` |
| cobra_cam_3 | 640x480 | 3 | Driveway/Sidewalk | `driveway_truck`, `sidewalk_front` |

### Per-Camera Settings

#### cobra_cam_1 (High Priority - Yard)

```yaml
detect:
  width: 1280
  height: 720
  fps: 5          # Higher FPS for better motion detection

motion:
  mask:
    - 0,0,1280,100         # Exclude sky
    - 0,620,200,720        # Exclude left edge
    - 1080,620,1280,720    # Exclude right edge

zones:
  yard_gate:
    coordinates: 200,700,1000,700,1000,500,200,500
    objects: [person, dog, cat]
    filters:
      person:
        min_area: 5000     # Larger threshold for distance
        threshold: 0.75    # Higher confidence
```

#### cobra_cam_2 (Porch)

```yaml
detect:
  width: 640
  height: 360
  fps: 3          # Moderate FPS for close-range

motion:
  mask:
    - 0,0,640,60          # Exclude sky

zones:
  porch_area:
    coordinates: 50,340,590,340,590,200,50,200
    objects: [person, dog, cat]
```

#### cobra_cam_3 (Driveway/Sidewalk)

```yaml
detect:
  width: 640
  height: 480
  fps: 3

objects:
  track: [person, car, truck, dog, cat]
  filters:
    car:
      min_score: 0.7
      threshold: 0.75
      min_area: 10000     # Large for driveway
    truck:
      min_score: 0.7
      threshold: 0.75
      min_area: 12000

zones:
  driveway_truck:
    coordinates: 50,450,400,450,400,350,50,350
    objects: [person, car, truck]

  sidewalk_front:
    coordinates: 50,300,590,300,590,360,50,360
    objects: [person, dog, cat]
```

### Detection Tuning

**Global Object Filters**:

```yaml
objects:
  track: [person, dog, cat, car, truck]
  filters:
    person:
      min_score: 0.65     # Detection confidence
      threshold: 0.7      # Tracking threshold
      min_area: 3000      # Minimum pixel area

    dog:
      min_score: 0.6
      threshold: 0.7
      min_area: 2000

    cat:
      min_score: 0.6
      threshold: 0.7
      min_area: 2000
```

**Parameters**:
- `min_score`: Initial detection confidence (0.0-1.0)
- `threshold`: Tracking continuation threshold
- `min_area`: Minimum bounding box area in pixels

---

## Recording & Retention

### Motion-Based Recording

**Configuration**:

```yaml
record:
  enabled: true
  retain:
    days: 7
    mode: motion    # Only record motion events
```

**Benefits**:
- 60-70% storage savings vs continuous
- Focus storage on important events
- Longer retention possible with same storage

### Snapshot Retention

**Per-Object Retention**:

```yaml
snapshots:
  enabled: true
  retain:
    default: 10      # 10 days default
    objects:
      person: 30     # Keep persons 30 days
      car: 14        # Vehicles 14 days
      truck: 14
```

---

## Performance Optimization

### Implemented Optimizations

#### ✅ Phase A: Security & Path Standardization

1. **RTSP Credentials**: Moved to agenix secrets with URL encoding
2. **Path Standardization**: All paths use `frigate` (not `frigate-v2`)
3. **Config Template**: Environment variable substitution for secrets

#### ✅ Phase B: Camera & GPU Optimization

1. **Increased FPS**:
   - cobra_cam_1: 1→5 fps (high priority)
   - cobra_cam_2/3: 1→3 fps

2. **Resolution Upgrade**: cobra_cam_3: 320x240→640x480

3. **Motion Masks**: Exclude sky and edges to reduce false positives

4. **Detection Zones**: Tighter zone coordinates for focused detection

5. **GPU Tuning**: Increased detector threads (3→4)

6. **Recording Mode**: Switched from continuous (`all`) to `motion`
   - **Storage Savings**: 60-70% reduction
   - **Impact**: ~23GB/week → ~8-15GB/week

#### ✅ Phase C: Monitoring

1. **Port Mapping**: Added port 9191:9090 for future Prometheus integration
2. **Validation**: Added Prometheus dependency assertion

**Note**: Prometheus telemetry configuration was removed due to Frigate 0.16.2 API changes. Monitoring is available via API stats endpoint.

### Current Performance Metrics

```bash
# Check current stats
curl -s http://localhost:5001/api/stats | jq '{
  version: .service.version,
  detector_speed_ms: .detectors.onnx.inference_speed,
  cameras: (.cameras | to_entries | map({
    name: .key,
    fps: .value.camera_fps,
    detection_fps: .value.detection_fps
  }))
}'
```

**Expected Output**:
```json
{
  "version": "0.16.2-4d58206",
  "detector_speed_ms": 28.0,
  "cameras": [
    {"name": "cobra_cam_1", "fps": 5.0, "detection_fps": 3.7},
    {"name": "cobra_cam_2", "fps": 2.8, "detection_fps": 0.8},
    {"name": "cobra_cam_3", "fps": 3.0, "detection_fps": 0.3}
  ]
}
```

---

## Monitoring

### Health Checks

The container includes HTTP health checks:

```bash
# Check container health
curl -fsS http://localhost:5001/api/stats || echo "UNHEALTHY"
```

### API Monitoring

**Stats Endpoint**: `http://localhost:5001/api/stats`

**Key Metrics**:
- `service.version` - Frigate version
- `detectors.onnx.inference_speed` - Detection speed (ms)
- `cameras.{name}.camera_fps` - Camera frame rate
- `cameras.{name}.detection_fps` - Detection processing rate
- `cameras.{name}.process_fps` - Processing pipeline rate

### Systemd Integration

```bash
# Service status
systemctl status podman-frigate.service

# View recent logs
journalctl -u podman-frigate.service -n 100

# Follow logs in real-time
journalctl -u podman-frigate.service -f
```

---

## Implementation Status

### ✅ Completed (Sprint 1 - Optimization)

| Phase | Task | Status |
|-------|------|--------|
| A.1 | Fix RTSP credential templating | ✅ Completed |
| A.2 | Update machine config paths | ✅ Completed |
| A.3 | Remove outdated launch script | ✅ Completed |
| B.1 | Increase camera FPS | ✅ Completed |
| B.2 | Optimize resolutions | ✅ Completed |
| B.3 | Refine detection zones | ✅ Completed |
| B.4 | Switch to motion recording | ✅ Completed |
| B.5 | GPU detector tuning | ✅ Completed |
| C.1 | Add Prometheus port mapping | ✅ Completed |
| C.2 | Add Prometheus dependency validation | ✅ Completed |
| D | Create comprehensive documentation | ✅ Completed |

### Deferred Items

- **Prometheus Telemetry**: Removed due to Frigate 0.16.2 API incompatibility
  - Alternative: Use API stats endpoint for monitoring
  - Future: Evaluate Frigate 0.17+ for native Prometheus support

---

## Testing & Validation

### Pre-Deployment Checklist

```bash
# 1. Validate NixOS configuration
nix flake check

# 2. Build test (no activation)
sudo nixos-rebuild test --flake .#hwc-server

# 3. Check config generation
sudo systemctl status frigate-config.service
sudo cat /opt/surveillance/frigate/config/config.yaml | head -50

# 4. Verify secrets substitution
sudo cat /opt/surveillance/frigate/config/config.yaml | rg "RTSP_USER|admin:il0wwlm"
# Should show: rtsp://admin:<encoded-password>@192.168.1.xxx
# Should NOT show: ${RTSP_USER} or hardcoded credentials

# 5. Check GPU availability
nvidia-smi

# 6. Verify storage paths exist
ls -la /mnt/media/surveillance/frigate/media
ls -la /mnt/hot/surveillance/frigate/buffer
```

### Post-Deployment Validation

```bash
# 1. Service is running
systemctl is-active podman-frigate.service
# Expected: active

# 2. API responds
curl -s http://localhost:5001/api/stats | jq '.service.version'
# Expected: "0.16.2-4d58206"

# 3. All cameras connected
curl -s http://localhost:5001/api/stats | jq '.cameras | keys'
# Expected: ["cobra_cam_1", "cobra_cam_2", "cobra_cam_3"]

# 4. GPU acceleration working
curl -s http://localhost:5001/api/stats | jq '.detectors.onnx.inference_speed'
# Expected: 25-35ms (GPU) vs 100-200ms (CPU)

# 5. Cameras streaming at correct FPS
curl -s http://localhost:5001/api/stats | jq '.cameras | to_entries[] | {camera: .key, fps: .value.camera_fps}'
# Expected: cam1=5.0, cam2/3=~3.0

# 6. No config errors in logs
journalctl -u podman-frigate.service --since "5 minutes ago" | rg "error|validation"
# Expected: No validation errors
```

### Performance Benchmarks

| Metric | Target | Current |
|--------|--------|---------|
| Detector inference | <50ms | ~28ms ✅ |
| Camera FPS (cam1) | 5.0 | 5.0 ✅ |
| Camera FPS (cam2/3) | 3.0 | ~3.0 ✅ |
| Storage (motion mode) | <20GB/week | ~8-15GB/week ✅ |

---

## Troubleshooting

### Container Won't Start

**Symptom**: `podman-frigate.service` fails or restarts continuously

**Debug Steps**:

```bash
# Check service status
systemctl status podman-frigate.service

# View detailed logs
journalctl -u podman-frigate.service -n 200 --no-pager

# Check for config validation errors
journalctl -u podman-frigate.service | rg "validation|error"

# Verify config file was generated
ls -la /opt/surveillance/frigate/config/config.yaml

# Check for syntax errors
sudo cat /opt/surveillance/frigate/config/config.yaml | head -100
```

**Common Causes**:

1. **Config Validation Errors**:
   - Check logs for `Extra inputs are not permitted`
   - Frigate 0.16.2 doesn't support `telemetry` or nested `events` sections
   - Solution: Ensure config template matches 0.16.2 schema

2. **Storage Path Missing**:
   - Error: `no such file or directory: /mnt/media/surveillance/frigate/media`
   - Solution: `sudo mkdir -p /mnt/media/surveillance/frigate/media && sudo chown eric:users /mnt/media/surveillance/frigate/media`

3. **Secrets Not Available**:
   - Error: `RTSP connection failed`
   - Solution: Check `age.secrets.frigate-*` are decrypted in `/run/agenix/`

### Config Not Updating

**Symptom**: Changes to `config.yml` not reflected in Frigate

**Cause**: Runtime config `/opt/surveillance/frigate/config/config.yaml` is generated from Nix store template

**Solution**:

```bash
# Rebuild NixOS to update template in Nix store
sudo nixos-rebuild switch --flake .#hwc-server

# Force config regeneration
sudo systemctl stop podman-frigate.service
sudo rm /opt/surveillance/frigate/config/config.yaml
sudo systemctl restart frigate-config.service
sudo systemctl start podman-frigate.service
```

---

## Architecture Details

### Config-First Pattern

**Philosophy**: Configuration lives in version-controlled YAML, Nix handles infrastructure

**Template**: `domains/server/frigate/config/config.yml`
- Version controlled
- Uses environment variables for secrets
- Single source of truth for Frigate config

**Generation**: `systemd.services.frigate-config`
- Reads secrets from agenix (`/run/agenix/frigate-*`)
- URL-encodes RTSP password
- Substitutes variables using `envsubst`
- Outputs to `/opt/surveillance/frigate/config/config.yaml`

**Container**: Mounts generated config as read-only volume

### Directory Management

**Nix tmpfiles.rules**: Create directories early in boot

```nix
systemd.tmpfiles.rules = [
  "d /opt/surveillance/frigate/config 0755 eric users -"
  "d /opt/surveillance/frigate/config/models 0755 eric users -"
  "d /opt/surveillance/frigate/config/labelmap 0755 eric users -"
  "d /mnt/media/surveillance/frigate/media 0755 eric users -"
  "d /mnt/hot/surveillance/frigate/buffer 0755 eric users -"
];
```

### Container Configuration

**Image**: `ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt`

**Key Options**:
- `--privileged`: Required for GPU access
- `--device=nvidia.com/gpu=0`: GPU passthrough (when GPU enabled)
- `--shm-size=512m`: Shared memory for video processing
- `--memory=4g`: Memory limit
- `--cpus=4.0`: CPU limit
- `--tmpfs=/tmp/cache:size=1g`: Temporary cache

**Health Check**:
```bash
curl -fsS http://127.0.0.1:5000/api/stats || exit 1
```
- Interval: 30s
- Timeout: 5s
- Retries: 3

---

## References

- **Frigate Documentation**: https://docs.frigate.video/
- **NixOS Podman**: https://nixos.org/manual/nixos/stable/index.html#ch-containers
- **Agenix**: https://github.com/ryantm/agenix
- **Charter v7.0**: `/home/eric/.nixos/CHARTER.md`
- **Optimization Plan**: `./FRIGATE-OPTIMIZATION-PLAN.md` (reference)

---

**Created**: 2025-11-23
**Last Updated**: 2025-12-07
**Maintainer**: Eric
**Status**: Production ✅ Optimized (Sprint 1 Complete)
