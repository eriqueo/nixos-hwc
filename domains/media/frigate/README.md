# Frigate NVR - Network Video Recorder

**Version**: 0.16.2-tensorrt
**Domain**: `hwc.media.frigate`
**Architecture**: Config-First Pattern (Charter v11.1)
**Status**: ✅ Production
**Last Updated**: 2026-04-07

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [AI Detection & GPU Acceleration](#ai-detection--gpu-acceleration)
4. [Storage & Retention](#storage--retention)
5. [Camera Configuration](#camera-configuration)
6. [Stream Architecture](#stream-architecture)
7. [Backup & Recovery](#backup--recovery)
8. [Monitoring](#monitoring)
9. [Troubleshooting](#troubleshooting)
10. [Configuration Reference](#configuration-reference)

---

## Overview

Frigate is a complete local NVR with AI-powered object detection. This implementation uses:

- **Container**: Podman with GPU passthrough
- **Hardware**: NVIDIA GPU with CUDA/NVDEC acceleration
- **Detection**: ONNX runtime with YOLOv9-s model (~24ms inference)
- **Cameras**: 4 cameras (3 Cobra PoE + 1 Reolink)
- **Storage**: Motion-based recording with tiered retention (3d motion, 14d alerts/detections)
- **Streaming**: go2rtc restream for WebRTC and stability
- **Security**: Agenix-encrypted secrets for RTSP credentials

### Key Features

| Feature | Status | Details |
|---------|--------|---------|
| GPU Object Detection | ✅ | ONNX + CUDA, ~24ms inference |
| Hardware Video Decode | ✅ | CUDA hwaccel (not NVDEC - better IR handling) |
| Motion-Based Recording | ✅ | 60-70% storage savings vs continuous |
| Substream Detection | ✅ | 720p detect, 4K record (fixes green tint) |
| go2rtc Restreaming | ✅ | WebRTC live view, stream stability |
| Detection Zones | ✅ | Per-camera zones with required_zones enforcement |
| Tiered Retention | ✅ | 3d motion, 14d alerts/detections, 30d person snapshots |
| Automated Cleanup | ✅ | Frigate native + systemd backup timer |

---

## Quick Start

### Access Frigate

| Access Method | URL |
|---------------|-----|
| Local | http://localhost:5000 |
| Server | http://hwc-server:5000 |
| Tailscale | http://hwc.ocelot-wahoo.ts.net:5000 |

### Quick Health Check

```bash
# One-liner status check
curl -s http://localhost:5000/api/stats | jq '{
  version: .service.version,
  detector_ms: .detectors.onnx.inference_speed,
  cameras: [.cameras | to_entries[] | {name: .key, fps: .value.camera_fps}]
}'

# Expected output:
# {
#   "version": "0.16.2-4d58206",
#   "detector_ms": 24,
#   "cameras": [
#     {"name": "cobra_cam_1", "fps": 5.0},
#     {"name": "cobra_cam_2", "fps": 5.0},
#     {"name": "cobra_cam_3", "fps": 5.0},
#     {"name": "reolink", "fps": 5.0}
#   ]
# }
```

### Service Management

```bash
# Check status
systemctl status podman-frigate.service

# View logs
journalctl -u podman-frigate.service -f

# Restart after config changes
sudo nixos-rebuild switch --flake .#hwc-server
sudo systemctl restart podman-frigate.service
```

---

## AI Detection & GPU Acceleration

### Current Status (Live)

```
Detector:     ONNX + CUDA
Model:        YOLOv9-s-320 (29MB)
Inference:    ~24ms (GPU-accelerated)
Fallback:     CPU if CUDA unavailable
```

### Hardware Configuration

| Component | Value |
|-----------|-------|
| GPU | NVIDIA (CUDA-capable) |
| Hwaccel | CUDA (not NVDEC - better color handling) |
| Detector | ONNX with CUDA execution provider |
| Model Input | 320x320 BGR, float32 |

### Detector Configuration

```yaml
detectors:
  onnx:
    type: onnx
    device: '0'
    num_threads: 4
    execution_providers:
      - cuda      # Primary - GPU acceleration
      - cpu       # Fallback

model:
  path: /config/models/yolov9-s-320.onnx
  model_type: yolo-generic
  input_tensor: nchw
  input_pixel_format: bgr
  input_dtype: float
  width: 320
  height: 320
```

### Video Decode (FFmpeg)

```yaml
ffmpeg:
  hwaccel_args:
    - -hwaccel
    - cuda            # CUDA hwaccel (not nvdec)
    - -hwaccel_device
    - '0'
  # NOTE: No hwaccel_output_format - prevents green tint during IR transitions
```

**Why CUDA instead of NVDEC?**
- NVDEC with forced `yuv420p` output causes green tint during IR mode switches
- CUDA hwaccel lets FFmpeg auto-select pixel format
- Better handling of day/night transitions

### Validation Commands

```bash
# Check detector inference speed (should be <30ms for GPU)
curl -s http://localhost:5000/api/stats | jq '.detectors.onnx.inference_speed'

# Check all camera detection rates
curl -s http://localhost:5000/api/stats | jq '.cameras | to_entries[] | {name: .key, detect_fps: .value.detection_fps}'
```

---

## Storage & Retention

### Current Storage Status

| Mount | Total | Used | Free | Purpose |
|-------|-------|------|------|---------|
| /mnt/media | 7.3 TB | 4.2 TB (61%) | 2.7 TB | Recordings & clips |
| /mnt/hot | 916 GB | 174 GB (20%) | 696 GB | Buffer/cache |
| Frigate Total | - | ~43 GB | - | All surveillance data |

### Directory Structure

```
/mnt/media/surveillance/frigate/
└── media/                      # Recordings and snapshots (~43GB)
    ├── cobra_cam_1/
    ├── cobra_cam_2/
    ├── cobra_cam_3/
    └── reolink/

/mnt/hot/surveillance/frigate/
└── buffer/                     # Temporary processing buffer

/opt/surveillance/frigate/
└── config/
    ├── config.yaml             # Runtime config (generated from Nix)
    ├── models/
    │   └── yolov9-s-320.onnx   # 29MB AI model
    └── labelmap/
        └── coco-80.txt         # COCO 80-class labels
```

### Retention Policies

#### Recordings (Video)

```yaml
record:
  enabled: true
  retain:
    days: 3           # General motion recordings: 3 days
    mode: motion      # Only record when motion detected
  alerts:
    retain:
      days: 14        # Alert clips: 14 days
      mode: motion
  detections:
    retain:
      days: 14        # Detection clips: 14 days
      mode: active_objects
```

Note: cobra_cam_1 has recording fully disabled (detect-only) — no 4K stream pulled.

#### Snapshots (Images)

```yaml
snapshots:
  enabled: true
  bounding_box: true
  crop: false
  quality: 70
  retain:
    default: 10       # Default: 10 days
    objects:
      person: 30      # People: 30 days (security priority)
      car: 7          # Vehicles: 7 days
      truck: 7
```

### Automated Cleanup

**1. Frigate Native Cleanup** (Primary)
- Runs automatically based on `retain.days` settings
- Deletes recordings older than retention period
- Manages database and clips

**2. Systemd Backup Timer** (Secondary)
- File: `machines/server/config.nix` → `frigate-cleanup.service`
- Schedule: Daily with 1-hour random delay
- Actions:
  - Delete recordings >7 days old
  - Delete clips >10 days old
  - Remove empty directories

```bash
# Check cleanup timer status
systemctl status frigate-cleanup.timer

# View last cleanup run
journalctl -u frigate-cleanup.service --since "24 hours ago"
```

---

## Camera Configuration

### Camera Overview

| Camera | Location | Detect Stream | Record Stream | FPS | Zone | required_zones |
|--------|----------|---------------|---------------|-----|------|----------------|
| cobra_cam_1 | Carport | 1280×720 (sub) | disabled | 3 | carport | Yes |
| cobra_cam_2 | Side yard | 1280×720 (sub) | 3840×2160 (main) | 5 | (TODO — offline) | No |
| cobra_cam_3 | Front porch | 1280×720 (sub) | 3840×2160 (main) | 3 | front_yard | Yes |
| reolink | Front yard | 480×270 (sub) | 3840×2160 (main) | 2 | property | Yes |

**IP Addresses**: Stored in agenix secrets (`frigate-camera-ips`)
- Cobra cameras: 192.168.0.201-203
- Reolink: 192.168.0.204

### Detection Objects

**Global defaults** (overridden per-camera where zones exist):
```yaml
objects:
  track: [person, dog, cat]
  filters:
    person: { min_score: 0.75, threshold: 0.80, min_area: 5000 }
    dog:    { min_score: 0.70, threshold: 0.75, min_area: 3000 }
    cat:    { min_score: 0.70, threshold: 0.75, min_area: 3000 }
```

### Per-Camera Zones and Noise Reduction

All cameras with zones use `required_zones` — Frigate won't create events unless
the object enters the named zone. This eliminates street traffic, passing pedestrians,
and neighbor activity from generating events.

**cobra_cam_1 (Carport)** — road at top of frame, driveway/yard below
- Motion mask: timestamp, bright light, road (top 40%)
- Zone: `carport` — everything below the road line
- required_zones on person/dog/cat

**cobra_cam_2 (Side yard)** — currently offline
- Motion mask: timestamp, street/warehouse (top third), green bin corner
- TODO: Add zones when camera is back online (similar to cobra_cam_1)

**cobra_cam_3 (Front porch)** — looking through porch railing at fenced yard
- Motion mask: timestamp, street beyond fence, neighbor areas, porch deck foreground
- Zone: `front_yard` — yard inside the fence
- required_zones on person/dog/cat

**reolink (Front yard)** — corner view of fenced yard + driveway
- Motion mask: timestamp, neighbor's area, far right edge
- Zone: `property` — yard inside fence + driveway
- required_zones on person/dog/cat/car/truck
- Tracks vehicles (car/truck) in addition to person/dog/cat

---

## Stream Architecture

### Dual-Stream Design

Each camera uses **two separate streams** to optimize for both detection and recording:

```
Camera Hardware
    │
    ├─► Main Stream (4K @ 15fps) ─► go2rtc ─► Frigate Record
    │   - High quality for recordings
    │   - H.264 (Cobra) / HEVC (Reolink)
    │   - cobra_cam_1 has no record stream (detect-only)
    │
    └─► Sub Stream ─► go2rtc ─► Frigate Detect
        - Cobra: 720p @ 3fps, Reolink: 480×270 @ 2fps
        - Prevents green tint from resolution mismatch
```

### go2rtc Restreaming

All streams flow through go2rtc for:
- **WebRTC live view** - Low latency browser streaming
- **Stream stability** - Reconnection handling
- **Video passthrough** - No transcoding (`#video=copy`)

```yaml
go2rtc:
  streams:
    cobra_cam_1:     [rtsp://...@192.168.0.201:554/ch01/0#video=copy]  # 4K main
    cobra_cam_1_sub: [rtsp://...@192.168.0.201:554/ch01/1#video=copy]  # 720p sub
    reolink:         [rtsp://...@192.168.0.204:554/main#video=copy]    # 4K HEVC
    reolink_sub:     [rtsp://...@192.168.0.204:554/sub#video=copy]     # 640x360
    reolink_record:  [rtsp://...@192.168.0.204:554/main#video=copy]    # 4K passthrough
    # reolink_record was previously a 1080p ffmpeg transcode but this destabilized
    # go2rtc (i/o timeouts, corrupt segments). Passthrough until driver is aligned.
```

### Why This Architecture?

**Problem Solved**: Green tint during IR mode transitions

**Root Cause**: When detect resolution doesn't match input stream, FFmpeg/NVDEC color space conversion fails during IR mode switches.

**Solution**:
1. Use camera's native substream for detection (720p)
2. Set `detect.width/height` to exactly match substream
3. Use CUDA hwaccel without forcing output format
4. Pass video through go2rtc with `#video=copy`

---

## Backup & Recovery

### What's Backed Up

| Data | Location | Backed Up? | Method |
|------|----------|------------|--------|
| Configuration | Nix files in repo | ✅ Yes | Git |
| AI Model | `/opt/.../models/` | ✅ Yes | Downloadable |
| Secrets | agenix encrypted | ✅ Yes | Git (encrypted) |
| Recordings | `/mnt/media/.../media/` | ⚠️ Optional | Manual/Borg |
| Database | `/mnt/media/.../frigate.db` | ⚠️ Optional | With recordings |

### Recovery Procedure

**Full System Recovery** (from NixOS rebuild):
```bash
# 1. Rebuild NixOS (creates all config, directories, services)
sudo nixos-rebuild switch --flake .#hwc-server

# 2. AI model is downloaded automatically or copy from backup
# Model location: /opt/surveillance/frigate/config/models/yolov9-s-320.onnx

# 3. Frigate will start with empty recordings (config is generated from Nix)
```

**Recording Recovery** (if backed up):
```bash
# Restore recordings from backup to:
/mnt/media/surveillance/frigate/media/

# Frigate will index existing recordings on startup
```

### Backup Recommendations

**Critical (already backed up via Git)**:
- Nix configuration files
- Agenix encrypted secrets

**Recommended**:
- Export important clips via Frigate UI before deletion
- Consider Borg backup for `/mnt/media/surveillance/frigate/` if needed

**Not Critical**:
- Recordings are ephemeral by design (7-day retention)
- Can be regenerated by cameras

---

## Monitoring

### Quick Status Check

```bash
# Service status
systemctl status podman-frigate.service

# Camera stats
curl -s http://localhost:5000/api/stats | jq '.cameras | to_entries[] | {
  name: .key,
  fps: .value.camera_fps,
  detect_fps: .value.detection_fps
}'

# Detector performance
curl -s http://localhost:5000/api/stats | jq '.detectors.onnx.inference_speed'
```

### Current Performance (Live)

```bash
curl -s http://localhost:5000/api/stats | jq '{
  version: .service.version,
  uptime_sec: .service.uptime,
  detector_ms: .detectors.onnx.inference_speed,
  cameras: (.cameras | to_entries | map({(.key): {fps: .value.camera_fps, detect: .value.detection_fps}}))
}'
```

**Expected Output**:
```json
{
  "version": "0.16.2-4d58206",
  "detector_ms": 24,
  "cameras": [
    {"cobra_cam_1": {"fps": 5.0, "detect": 4.0}},
    {"cobra_cam_2": {"fps": 5.0, "detect": 4.0}},
    {"cobra_cam_3": {"fps": 5.0, "detect": 8.0}},
    {"reolink": {"fps": 5.0, "detect": 9.0}}
  ]
}
```

### Health Indicators

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| Inference speed | <30ms | 30-50ms | >50ms |
| Camera FPS | ~5.0 | <4.0 | 0 |
| Detection FPS | >0 | Intermittent | 0 |
| Storage free | >20% | 10-20% | <10% |

### Web UI Access

- **Local**: http://localhost:5000
- **Tailscale**: http://hwc.ocelot-wahoo.ts.net:5000

---

## Troubleshooting

### Common Issues

#### Green Tint on Live View

**Symptom**: Green tint, especially during IR mode transitions (day/night)

**Cause**: Resolution mismatch between input stream and detect dimensions, or forced pixel format

**Solution** (already implemented):
1. Use substreams for detection (match detect resolution exactly)
2. Use CUDA hwaccel without `hwaccel_output_format`
3. Use `#video=copy` in go2rtc streams

#### Cameras Show 0 FPS

**Debug**:
```bash
# Check FFmpeg errors
journalctl -u podman-frigate.service --since "5 min ago" | rg -i "error|ffmpeg"

# Check go2rtc streams
curl -s http://localhost:1984/api/streams | jq 'keys'

# Verify camera connectivity
ffprobe -v error rtsp://127.0.0.1:8554/cobra_cam_1_sub
```

**Common Causes**:
- Camera offline or IP changed
- go2rtc stream not connecting
- FFmpeg hwaccel incompatibility

#### Container Won't Start

```bash
# Check service status
systemctl status podman-frigate.service

# View detailed logs
journalctl -u podman-frigate.service -n 200 --no-pager

# Check config validation
journalctl -u podman-frigate.service | rg "validation|error"
```

#### Stale NVIDIA CDI Spec (cannot stat /nix/store/...nvidia...)

**Symptom**: `crun: cannot stat /nix/store/...-nvidia-x11-...: No such file or directory`

**Cause**: The CDI spec in `/run/cdi/nvidia-container-toolkit.json` hardcodes nix
store paths. If those paths get garbage collected, the container can't start.

**Fix**: Regenerate the CDI spec:
```bash
sudo systemctl restart nvidia-container-toolkit-cdi-generator.service
sudo systemctl restart podman-frigate.service
```

**Prevention**: `podman-frigate` has `requires = nvidia-container-toolkit-cdi-generator.service`
so the CDI spec is regenerated on every boot/activation. If this breaks again, check
that the dependency is still in `index.nix`.

#### Dashboard Loads Then Crashes / Live Streams Cut Out

**Symptom**: Frigate UI loads briefly then goes blank. All cameras affected.

**Cause**: A failing go2rtc stream (e.g. reolink transcode) can poison the entire
go2rtc process, killing all camera live streams. Check for repeated `error=EOF` or
`i/o timeout` warnings in logs.

**Debug**:
```bash
journalctl -u podman-frigate.service --since "5 min ago" | rg "WRN|EOF|timeout"
```

**Fix**: Identify the failing stream and switch it to passthrough (`#video=copy`)
or disable the camera. The reolink ffmpeg transcode (`#hardware` or software) is
a known problem when the nvidia driver doesn't match the running kernel.

#### Config Not Updating

**Cause**: Config is generated from Nix, not edited directly

**Solution**:
```bash
# 1. Edit Nix config
vim domains/media/frigate/parts/config.nix

# 2. Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# 3. Restart Frigate
sudo systemctl restart podman-frigate.service
```

### Useful Debug Commands

```bash
# Check all go2rtc streams
curl -s http://localhost:1984/api/streams | jq 'to_entries[] | {name: .key, producers: .value.producers | length}'

# View generated config
cat /opt/surveillance/frigate/config/config.yaml

# Check storage usage
du -sh /mnt/media/surveillance/frigate/*

# Monitor in real-time
journalctl -u podman-frigate.service -f
```

---

## Configuration Reference

### NixOS Options

```nix
hwc.media.frigate = {
  enable = true;
  image = "ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt";
  port = 5001;

  gpu = {
    enable = true;
    device = 0;
  };

  storage = {
    configPath = "/opt/surveillance/frigate/config";
    mediaPath = "/mnt/media/surveillance/frigate/media";
    bufferPath = "/mnt/hot/surveillance/frigate/buffer";
  };

  resources = {
    memory = "4g";
    cpus = "1.5";
    shmSize = "1g";
  };

  firewall.tailscaleOnly = true;
};
```

### File Locations

| File | Purpose |
|------|---------|
| `domains/media/frigate/index.nix` | Main module, container config |
| `domains/media/frigate/parts/config.nix` | Frigate YAML config (Nix-native) |
| `domains/media/frigate/exporter/index.nix` | Prometheus exporter (if enabled) |
| `/opt/surveillance/frigate/config/config.yaml` | Generated runtime config |
| `/opt/surveillance/frigate/config/models/` | AI model files |
| `machines/server/config.nix` | Storage paths, cleanup timer |

### Secrets (Agenix)

| Secret | Path | Purpose |
|--------|------|---------|
| frigate-rtsp-username | `/run/agenix/frigate-rtsp-username` | Cobra camera user |
| frigate-rtsp-password | `/run/agenix/frigate-rtsp-password` | Cobra camera pass |
| frigate-reolink-username | `/run/agenix/frigate-reolink-username` | Reolink user |
| frigate-reolink-password | `/run/agenix/frigate-reolink-password` | Reolink pass |
| frigate-camera-ips | `/run/agenix/frigate-camera-ips` | JSON with IPs |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Nix Configuration                         │
│  domains/media/frigate/parts/config.nix                         │
│  (Declarative, version-controlled)                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    frigate-config.service                        │
│  - Reads secrets from /run/agenix/                              │
│  - Substitutes ${VARIABLES} with envsubst                       │
│  - Writes to /opt/surveillance/frigate/config/config.yaml       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    podman-frigate.service                        │
│  - Mounts config, models, media volumes                         │
│  - GPU passthrough (CUDA)                                       │
│  - Network: host mode                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
         ┌────────┐     ┌─────────┐     ┌──────────┐
         │ go2rtc │     │ Frigate │     │  ONNX    │
         │        │────▶│ Detect  │────▶│ Detector │
         │ RTSP   │     │ Record  │     │  (CUDA)  │
         └────────┘     └─────────┘     └──────────┘
              ▲               │
              │               ▼
         ┌────────┐     ┌─────────────┐
         │Cameras │     │ /mnt/media/ │
         │ (4x)   │     │ recordings  │
         └────────┘     └─────────────┘
```

---

## Changelog
- 2026-04-12: Reduce detection load — drop FPS (5→3 cobra, 3→2 reolink), disable cobra_cam_1 4K record stream (detect-only), lower reolink detect resolution (640×360→480×270). GPU temp 74°C→61°C.
- 2026-04-07: Switch reolink_record from ffmpeg transcode to 4K passthrough — transcode (both hardware and software) destabilized go2rtc, killing all live streams. Re-enable after reboot aligns nvidia driver.
- 2026-04-07: Disable cobra_cam_2 while physically offline — retry storm every 10s was generating constant errors.
- 2026-04-07: Add review.alerts/detections.required_zones on cobra_cam_1 (carport), cobra_cam_3 (front_yard), reolink (property). Eliminates street/neighbor noise at the source. Update camera comments to match actual locations.
- 2026-04-07: Add CDI generator dependency to podman-frigate — prevents stale nvidia store path crashes after GC.
- 2026-03-27: Removed broken port 9191:9090 mapping and frigate-nvr scrape config (ignored with --network=host, caused false ServiceDown alerts). Enabled frigate-exporter for proper Prometheus metrics.
- 2026-03-18: Integrate MQTT support for event publishing, enabling n8n workflows.
- **2026-03-09**: Fixed green tint with substream detection, CUDA hwaccel, go2rtc video=copy
- **2026-03-09**: Added Reolink camera (4th camera)
- **2026-03-09**: Updated all Cobra cameras to use 720p substreams for detection
- **2025-12-07**: Initial optimization sprint complete
- **2025-11-23**: Initial documentation created

---

## References

- [Frigate Documentation](https://docs.frigate.video/)
- [go2rtc Documentation](https://github.com/AlexxIT/go2rtc)
- [ONNX Runtime](https://onnxruntime.ai/)
- [Agenix Secrets](https://github.com/ryantm/agenix)

---

**Last Updated**: 2026-04-07
**Maintainer**: Eric
**Status**: Production ✅
