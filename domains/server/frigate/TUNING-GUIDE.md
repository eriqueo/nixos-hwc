# Frigate NVR Tuning Cheat Sheet

Quick reference for adjusting Frigate configuration for camera count, resolution, recording modes, and performance optimization.

---

## Table of Contents

1. [Adding/Removing Cameras](#addingremoving-cameras)
2. [Adjusting Resolution](#adjusting-resolution)
3. [Changing Detection FPS](#changing-detection-fps)
4. [Recording Modes](#recording-modes)
5. [Shared Memory Sizing](#shared-memory-sizing)
6. [Container Resource Limits](#container-resource-limits)
7. [Hardware Acceleration Quick Reference](#hardware-acceleration-quick-reference)
8. [Performance Tuning Matrix](#performance-tuning-matrix)

---

## Adding/Removing Cameras

### Current Setup

Cameras are dynamically generated from secrets. To modify:

1. **Update Camera IPs Secret**:
   ```bash
   # Decrypt the camera IPs file
   sudo agenix -e /path/to/secrets/frigate-camera-ips.age

   # Edit JSON (add/remove entries):
   {
     "cobra_cam_1": "192.168.1.10",
     "cobra_cam_2": "192.168.1.11",
     "cobra_cam_3": "192.168.1.12",
     "new_camera_4": "192.168.1.13"  # Add new camera
   }
   ```

2. **Update Container Config** (`domains/server/frigate/parts/container.nix`):
   ```nix
   # Add camera configuration block in the systemd service script
   new_camera_4:
     enabled: true
     ffmpeg:
       <<: *ffmpeg_defaults
       inputs:
         - path: rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$NEW_CAM_IP:554/ch01/0
           roles: [ detect, record ]
     detect:
       width: 1920
       height: 1080
       fps: 3
   ```

3. **Rebuild**:
   ```bash
   sudo nixos-rebuild switch
   ```

### Quick Camera Template

```yaml
camera_name:
  enabled: true
  ffmpeg:
    <<: *ffmpeg_defaults
    inputs:
      - path: rtsp://$RTSP_USER:$RTSP_PASS_ENCODED@$CAM_IP:554/ch01/0
        roles: [ detect, record ]  # or just [ detect ] for no recording
  detect:
    width: 1280      # Adjust to match stream
    height: 720
    fps: 1           # 1-5 recommended for low CPU usage
  record:
    enabled: true
    retain:
      days: 7        # How long to keep recordings
      mode: active_objects  # or "all" for continuous
```

---

## Adjusting Resolution

### Impact of Resolution Changes

| Resolution | Pixels | RAM/Camera | Detect CPU | Recording Storage (per day) |
|------------|--------|------------|------------|----------------------------|
| 320×240 | 76,800 | 2.5 MB | Minimal | ~500 MB |
| 640×360 | 230,400 | 6.9 MB | Low | ~1.5 GB |
| 1280×720 | 921,600 | 26.6 MB | Medium | ~5 GB |
| 1920×1080 | 2,073,600 | 59.8 MB | High | ~10 GB |
| 2560×1440 | 3,686,400 | 106.3 MB | Very High | ~18 GB |
| 3840×2160 (4K) | 8,294,400 | 239.2 MB | Extreme | ~40 GB |

### Best Practices

- **Detect stream**: Use 1280×720 or lower (detection works well at lower res)
- **Record stream**: Use native camera resolution for evidence quality
- **Dual-stream setup** (advanced):
  ```yaml
  ffmpeg:
    inputs:
      - path: rtsp://...high_res_stream
        roles: [ record ]
      - path: rtsp://...low_res_stream
        roles: [ detect ]
  ```

---

## Changing Detection FPS

### Current: 1 FPS (Very Conservative)

**Recommendation**: 1-3 FPS for most surveillance scenarios

| FPS | CPU Impact | Use Case |
|-----|------------|----------|
| 1 | Minimal | Parking lots, low-traffic areas, power efficiency |
| 3 | Low | General surveillance, residential |
| 5 | Medium | High-traffic areas, faster motion |
| 10+ | High | Active monitoring, sports, NOT recommended |

### Configuration

```yaml
detect:
  fps: 3  # Change this value (1-5 recommended)
```

### Impact Calculator

- **Current** (3 cameras @ 1fps): ~1-2% CPU per camera
- **3 FPS**: ~3-6% CPU per camera
- **5 FPS**: ~5-10% CPU per camera

---

## Recording Modes

### Mode Comparison

| Mode | Disk Usage | CPU Impact | Use Case |
|------|------------|------------|----------|
| `active_objects` | Low | Low | Only record when objects detected (**recommended**) |
| `all` | High | Medium | Continuous recording (24/7) |
| `motion` | Medium | Low | Record on any motion (not just objects) |

### Current Configuration

```nix
record:
  enabled: true
  retain:
    days: 7                # Keep recordings for 7 days
    mode: active_objects   # Only when objects detected
```

### Storage Impact Example (per camera)

| Mode | 720p | 1080p | 4K |
|------|------|-------|-----|
| `active_objects` (5% active) | ~350 MB/day | ~700 MB/day | ~2 GB/day |
| `motion` (20% active) | ~1.4 GB/day | ~2.8 GB/day | ~8 GB/day |
| `all` (100% active) | ~7 GB/day | ~14 GB/day | ~40 GB/day |

### Adjust Retention

```yaml
record:
  retain:
    days: 14  # Increase retention (check storage capacity)

    # Advanced: per-object retention
    objects:
      person: 30  # Keep person detections for 30 days
      car: 14     # Keep car detections for 14 days
      default: 7  # Everything else for 7 days
```

---

## Shared Memory Sizing

### Calculation Formula

```
shm_size = (cameras × resolution_bytes × 20 frames) + 40 MB logs
resolution_bytes = width × height × 1.5
```

### Quick Reference Table

| Cameras | 720p | 1080p | 1440p | 4K |
|---------|------|-------|-------|-----|
| 1 | 67 MB | 100 MB | 147 MB | 280 MB |
| 3 | 120 MB | 220 MB | 360 MB | 760 MB |
| 5 | 174 MB | 340 MB | 574 MB | 1240 MB |
| 10 | 308 MB | 640 MB | 1108 MB | 2440 MB |
| 15 | 442 MB | 940 MB | 1642 MB | 3640 MB |

### Current Setup

- **Cameras**: 3 (mixed: 720p, 360p, 240p)
- **Calculated Need**: ~76 MB
- **Current Setting**: 1 GB (13x headroom - excellent)

### When to Adjust

**Increase `resources.shmSize` if**:
- Adding cameras (use table above)
- Seeing "Bus error" in logs
- Increasing resolution to 4K

**Configuration**:
```nix
hwc.server.frigate.resources.shmSize = "2g";  # 2 GB for ~10-15 cameras at 1080p
```

---

## Container Resource Limits

### Current Limits

```nix
resources = {
  memory = "4g";    # 4 GB RAM limit
  cpus = "1.5";     # 1.5 CPU cores
  shmSize = "1g";   # 1 GB shared memory
};
```

### Scaling Guidelines

| Cameras | Resolution | RAM | CPUs | shm-size |
|---------|------------|-----|------|----------|
| 1-3 | 720p | 2-4 GB | 1-2 | 256 MB |
| 4-6 | 720p | 4-6 GB | 2-3 | 512 MB |
| 7-10 | 1080p | 6-8 GB | 3-4 | 1 GB |
| 11-15 | 1080p | 8-12 GB | 4-6 | 2 GB |
| 15+ | 1080p | 12+ GB | 6+ | 3+ GB |

### Adjust in Configuration

```nix
hwc.server.frigate.resources = {
  memory = "8g";    # Increase for more cameras
  cpus = "3";       # Increase for higher FPS or resolution
  shmSize = "2g";   # Increase if adding cameras
};
```

---

## Hardware Acceleration Quick Reference

### Current Options

```nix
hwaccel.type = "nvidia";  # Options:
  # "nvidia"     - NVIDIA GPU (nvdec) - high power, good performance
  # "vaapi"      - Intel VAAPI - recommended, auto H.264/H.265
  # "qsv-h264"   - Intel QuickSync H.264 only
  # "qsv-h265"   - Intel QuickSync H.265 only
  # "cpu"        - Software (no acceleration)
```

### Switch to Intel VAAPI (if available)

```nix
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "intel";  # Changed from "nvidia"
};

hwc.server.frigate.hwaccel = {
  type = "vaapi";
  device = "/dev/dri/renderD128";
  vaapiDriver = "iHD";  # or "i965" for older CPUs
};
```

### Troubleshooting Quick Checks

```bash
# Verify hardware acceleration device
ls -la /dev/dri/

# Check Frigate logs for hwaccel
sudo podman logs frigate | grep -i hwaccel

# Monitor GPU usage (Intel)
sudo intel_gpu_top

# Monitor GPU usage (NVIDIA)
watch -n 1 nvidia-smi
```

---

## Performance Tuning Matrix

### Scenario: Low CPU Usage Priority

```nix
hwc.server.frigate = {
  hwaccel.type = "vaapi";  # Use Intel iGPU if available

  # In container.nix, set cameras:
  detect.fps = 1;          # Minimal detection
  detect.width = 640;      # Lower resolution
  record.mode = "active_objects";  # Only when needed
};
```

**Expected**: <5% CPU per camera

---

### Scenario: High Detection Accuracy

```nix
hwc.server.frigate = {
  hwaccel.type = "vaapi";  # Offload decode to GPU

  detect.fps = 5;          # More frequent detection
  detect.width = 1280;     # Higher resolution

  gpu = {
    enable = true;
    detector = "onnx";     # NVIDIA or OpenVINO (Intel)
  };
};
```

**Expected**: Better detection, 10-15% CPU per camera

---

### Scenario: Maximum Storage Efficiency

```nix
record = {
  enabled = true;
  retain = {
    days = 7;
    mode = "active_objects";  # Only record detections
  };
};

# Use lower resolution for recording (if acceptable)
detect.width = 1280;
detect.height = 720;
```

**Expected**: ~5 GB/week per camera (vs ~50 GB for continuous)

---

### Scenario: Adding 10 More Cameras

```nix
resources = {
  memory = "8g";     # Up from 4g
  cpus = "4";        # Up from 1.5
  shmSize = "2g";    # Up from 1g (see calculation table)
};

storage.maxSizeGB = 5000;  # Up from 2000 (for more cameras)
```

**Recalculate shm-size**: Use formula or table above

---

## Quick Diagnostic Commands

```bash
# View Frigate logs
sudo podman logs -f frigate

# Check specific camera FFmpeg logs
sudo podman exec frigate cat /config/logs/frigate.log | grep cobra_cam_1

# Restart Frigate after config changes
sudo systemctl restart podman-frigate.service

# Check container resource usage
sudo podman stats frigate

# View generated config
cat /opt/surveillance/frigate/config/config.yaml

# Check available storage
df -h /mnt/media/surveillance/frigate/media

# Monitor Frigate via Web UI
# Navigate to: http://server-ip:5000
```

---

## Common Tuning Workflows

### Adding a New 4K Camera

1. **Update secrets** with new camera IP
2. **Add camera config** with dual-stream:
   ```yaml
   new_4k_camera:
     ffmpeg:
       inputs:
         - path: rtsp://...mainstream  # 4K
           roles: [ record ]
         - path: rtsp://...substream   # 720p
           roles: [ detect ]
   ```
3. **Increase shm-size**: Add ~240 MB for 4K camera
4. **Increase storage**: ~40 GB/day if recording continuously
5. **Rebuild**: `sudo nixos-rebuild switch`

---

### Reducing Power Consumption

1. **Switch to Intel VAAPI**: See Hardware Acceleration section
2. **Lower detection FPS**: Set to 1-2 fps
3. **Reduce resolution**: Use 720p or lower for detect
4. **Disable recording**: Set `record.enabled = false` for non-critical cameras
5. **Use CPU detector**: Disable GPU detection if Intel iGPU available

**Expected**: 25-50% power reduction (5-15W saved)

---

### Troubleshooting High CPU

1. **Check hwaccel is active**: `podman logs frigate | grep hwaccel`
2. **Reduce detection FPS**: Lower from 5 to 1-3
3. **Lower resolution**: Use 640x360 instead of 1080p for detect
4. **Disable unnecessary cameras**: Set `enabled: false`
5. **Check for codec issues**: Ensure cameras use H.264 or H.265

---

## Configuration File Locations

| File | Purpose | How to Edit |
|------|---------|-------------|
| `/machines/server/config.nix` | Main Frigate enable/settings | Edit via NixOS |
| `/domains/server/frigate/parts/container.nix` | Camera definitions | Edit via NixOS |
| `/run/agenix/frigate-camera-ips` | Camera IP addresses (secret) | `agenix -e` |
| `/opt/surveillance/frigate/config/config.yaml` | Generated runtime config | Auto-generated (view only) |

**Note**: After any NixOS configuration change, run:
```bash
sudo nixos-rebuild switch
```

---

## Performance Monitoring

### Frigate UI Metrics (http://server-ip:5000)

- **System**: CPU usage, GPU usage, memory
- **Cameras**: FPS, detection FPS, skipped frames
- **Storage**: Disk usage, retention stats

### Prometheus Metrics (if enabled)

- `frigate_storage_size_bytes`: Total storage used
- `frigate_cameras_healthy`: Number of healthy cameras
- `frigate_cameras_total`: Total camera count

### System Commands

```bash
# Container resource usage
sudo podman stats frigate

# Storage usage
du -sh /mnt/media/surveillance/frigate/media

# Camera health status (via watchdog)
systemctl status frigate-camera-watchdog

# View Prometheus metrics
cat /var/lib/node-exporter-textfile/frigate_*.prom
```

---

## Best Practices Summary

1. **Start conservative**: 720p @ 1fps, add resources as needed
2. **Use hardware acceleration**: Intel VAAPI or NVIDIA nvdec
3. **Monitor shm-size**: Ensure adequate shared memory (use formula)
4. **Optimize storage**: Use `active_objects` mode, adjust retention
5. **Scale incrementally**: Add cameras one at a time, test stability
6. **Enable monitoring**: Use watchdog and Prometheus for health checks

---

## Quick Reference Card

```
| Setting              | Conservative | Balanced | Performance |
|----------------------|--------------|----------|-------------|
| Resolution           | 640×360      | 1280×720 | 1920×1080   |
| Detection FPS        | 1            | 3        | 5           |
| Recording Mode       | active_obj   | active   | all         |
| Retention (days)     | 7            | 14       | 30          |
| Hardware Accel       | vaapi        | vaapi    | nvidia      |
| Container RAM        | 2-4 GB       | 4-6 GB   | 8+ GB       |
| Container CPUs       | 1-2          | 2-4      | 4+          |
| shm-size (per cam)   | ~30 MB       | ~70 MB   | ~150 MB     |
| Power (per system)   | 10-15W       | 15-25W   | 25-40W      |
| Storage (per cam/day)| ~1 GB        | ~5 GB    | ~15 GB      |
```

---

**For detailed hardware acceleration analysis, see**: [HARDWARE-ACCELERATION.md](./HARDWARE-ACCELERATION.md)
