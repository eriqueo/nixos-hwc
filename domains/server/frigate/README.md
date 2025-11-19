# Frigate NVR Module - Setup & Troubleshooting Guide

**Charter v6.0 Compliant Module**
**Namespace**: `hwc.server.frigate.*`
**Location**: `domains/server/frigate/`

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Configuration](#configuration)
4. [Hardware Acceleration](#hardware-acceleration)
5. [Secrets Management](#secrets-management)
6. [Common Operations](#common-operations)
7. [Troubleshooting](#troubleshooting)
8. [Migration History](#migration-history)
9. [Additional Documentation](#additional-documentation)

---

## Overview

Frigate is a Network Video Recorder (NVR) that provides real-time object detection, recording, and surveillance monitoring for RTSP cameras. This implementation uses:

- **Container**: Podman OCI container (not Docker)
- **GPU**: NVIDIA Quadro P1000 with TensorRT acceleration
- **Cameras**: 4 Cobra cameras (3 active, 1 disabled)
- **Storage**: Two-tier (SSD buffer + HDD media)
- **Events**: MQTT integration via Mosquitto
- **Monitoring**: Camera health watchdog + Prometheus metrics

---

## Architecture

### Module Structure

```
domains/server/frigate/
├── index.nix              # Main entry point with validation
├── options.nix            # Complete API declarations
├── parts/
│   ├── mqtt.nix          # Mosquitto MQTT broker
│   ├── container.nix     # OCI container + config generation
│   ├── storage.nix       # Automated storage pruning
│   └── watchdog.nix      # Camera health monitoring
└── README.md             # This file
```

### Dependencies

```nix
hwc.infrastructure.hardware.gpu     # GPU acceleration (required for TensorRT)
hwc.secrets                          # Agenix secrets (RTSP credentials)
virtualisation.oci-containers        # Podman backend
```

### Secrets (in infrastructure domain)

```
/run/agenix/frigate-rtsp-username    # Camera RTSP username
/run/agenix/frigate-rtsp-password    # Camera RTSP password
/run/agenix/frigate-camera-ips       # JSON map of camera IPs
```

### Storage Layout

```
/opt/surveillance/frigate/config/           # Configuration files
  └── config.yaml                           # Generated from secrets
/mnt/media/surveillance/frigate/media/      # Recordings (cold storage, 2TB cap)
  └── YYYY-MM-DD/                           # Organized by date
/mnt/hot/surveillance/buffer/               # Temporary cache (hot storage)
/tmp/cache/                                 # Container tmpfs (1GB)
```

### Network Ports (Tailscale only)

```
5000/TCP    # Web UI
8554/TCP    # RTSP streaming
8555/TCP    # Internal RTSP
8555/UDP    # Internal RTSP
1883/TCP    # MQTT broker (if enabled)
```

---

## Configuration

### Basic Setup

```nix
# machines/server/config.nix
hwc.server.frigate = {
  enable = true;

  gpu = {
    enable = true;
    detector = "tensorrt";
    useFP16 = false;  # IMPORTANT: P1000 (Pascal) requires FP16 disabled
  };

  mqtt.enable = true;

  monitoring = {
    watchdog.enable = true;
    prometheus.enable = true;
  };

  storage = {
    maxSizeGB = 2000;
    pruneSchedule = "hourly";
  };

  firewall.tailscaleOnly = true;
};
```

### Advanced Configuration

```nix
hwc.server.frigate = {
  enable = true;

  # Container image
  image = "ghcr.io/blakeblackshear/frigate:stable-tensorrt";

  # Network settings
  settings = {
    host = "0.0.0.0";
    port = 5000;
    timezone = "America/Denver";
  };

  # Storage configuration
  storage = {
    configPath = "/opt/surveillance/frigate/config";
    mediaPath = "/mnt/media/surveillance/frigate/media";
    bufferPath = "/mnt/hot/surveillance/buffer";
    maxSizeGB = 2000;
    pruneSchedule = "hourly";  # or "daily", "weekly", etc.
  };

  # GPU acceleration
  gpu = {
    enable = true;
    device = 0;  # GPU number
    detector = "tensorrt";  # or "cpu"
    useFP16 = false;  # Set to true for newer GPUs (Volta+)
  };

  # MQTT broker
  mqtt = {
    enable = true;
    host = "127.0.0.1";
    port = 1883;
  };

  # Monitoring
  monitoring = {
    watchdog = {
      enable = true;
      schedule = "*:0/30";  # Every 30 minutes
    };
    prometheus = {
      enable = true;
      textfilePath = "/var/lib/node-exporter-textfile";
    };
  };

  # Container resource limits
  resources = {
    memory = "4g";
    cpus = "1.5";
    shmSize = "1g";
  };

  # Firewall
  firewall.tailscaleOnly = true;
};
```

### Camera Configuration

Camera configuration is generated dynamically from secrets. The current setup includes:

- **cobra_cam_1**: 192.168.1.101 (1280x720, 1fps, detect+record)
- **cobra_cam_2**: 192.168.1.102 (640x360, 1fps, detect+record)
- **cobra_cam_3**: 192.168.1.103 (320x240, 1fps, detect+record+zones)
- **cobra_cam_4**: 192.168.1.104 (disabled - unreachable)

To modify cameras, update the `frigate-camera-ips` secret (see [Secrets Management](#secrets-management)).

**For detailed tuning instructions (resolution, FPS, recording modes)**: See [TUNING-GUIDE.md](./TUNING-GUIDE.md)

---

## Hardware Acceleration

Frigate supports multiple hardware acceleration types for video decoding (FFmpeg) and object detection.

### Quick Configuration

```nix
hwc.server.frigate = {
  # Hardware acceleration for video decoding (FFmpeg)
  hwaccel = {
    type = "nvidia";  # Options: "nvidia" | "vaapi" | "qsv-h264" | "qsv-h265" | "cpu"
    device = "0";     # NVIDIA: device number | Intel: /dev/dri/renderD128
    vaapiDriver = "iHD";  # Only for Intel: "iHD" (modern) or "i965" (legacy)
  };

  # GPU acceleration for object detection (separate from video decoding)
  gpu = {
    enable = true;
    detector = "onnx";  # Options: "cpu" | "onnx" | "tensorrt" | "openvino"
    useFP16 = false;    # Disable for Pascal GPUs (e.g., P1000)
  };
};
```

### Supported Acceleration Types

| Type | Hardware | Power | Performance | Use Case |
|------|----------|-------|-------------|----------|
| **nvidia** | NVIDIA GPU (nvdec) | High (15-25W) | Excellent | Current setup, discrete GPU |
| **vaapi** | Intel iGPU (VAAPI) | Low (5-10W) | Excellent | **Recommended**, auto H.264/H.265 |
| **qsv-h264** | Intel QuickSync | Low (5-10W) | Excellent | H.264 streams only |
| **qsv-h265** | Intel QuickSync | Low (5-10W) | Excellent | H.265 streams only |
| **cpu** | Software decoding | Minimal | Poor | Fallback only |

### Migrating from NVIDIA to Intel VAAPI

**Benefits**: 50% CPU reduction, 25-60% power savings (5-15W), equivalent latency

**Steps**:

1. Enable Intel GPU in `machines/server/config.nix`:
   ```nix
   hwc.infrastructure.hardware.gpu = {
     enable = true;
     type = "intel";  # Changed from "nvidia"
   };
   ```

2. Update Frigate hwaccel configuration:
   ```nix
   hwc.server.frigate.hwaccel = {
     type = "vaapi";  # Changed from "nvidia"
     device = "/dev/dri/renderD128";  # Changed from "0"
     vaapiDriver = "iHD";  # Modern Intel (6th gen+)
   };
   ```

3. Rebuild and verify:
   ```bash
   sudo nixos-rebuild switch
   podman logs frigate | grep -i vaapi
   # Should show: "Automatically detected vaapi hwaccel"
   ```

**For comprehensive analysis and migration strategies**: See [HARDWARE-ACCELERATION.md](./HARDWARE-ACCELERATION.md)

---

## Secrets Management

### Secret Locations

All Frigate secrets are in the **infrastructure domain** (not server):

```
domains/secrets/parts/infrastructure/
├── frigate-rtsp-username.age
├── frigate-rtsp-password.age
└── frigate-camera-ips.age
```

Declared in: `domains/secrets/declarations/infrastructure.nix`

### Viewing Current Secrets

```bash
# RTSP username
sudo cat /run/agenix/frigate-rtsp-username

# RTSP password
sudo cat /run/agenix/frigate-rtsp-password

# Camera IPs (JSON)
sudo cat /run/agenix/frigate-camera-ips | jq
```

### Updating Secrets

#### 1. Get Age Public Key

```bash
sudo age-keygen -y /etc/age/keys.txt
# Output: age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne
```

#### 2. Update RTSP Credentials

```bash
cd ~/.nixos/domains/secrets/parts/infrastructure/

# Update username
echo "new-username" | sudo nix-shell -p age --run "age -r age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne" | sudo tee frigate-rtsp-username.age > /dev/null

# Update password
echo "new-password" | sudo nix-shell -p age --run "age -r age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne" | sudo tee frigate-rtsp-password.age > /dev/null
```

#### 3. Update Camera IPs

```bash
# Create new camera IP map
cat > /tmp/camera-ips.json <<'EOF'
{
  "cobra_cam_1": "192.168.1.101",
  "cobra_cam_2": "192.168.1.102",
  "cobra_cam_3": "192.168.1.103",
  "cobra_cam_4": "192.168.1.104"
}
EOF

# Encrypt and save
cat /tmp/camera-ips.json | sudo nix-shell -p age --run "age -r age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne" | sudo tee domains/secrets/parts/infrastructure/frigate-camera-ips.age > /dev/null

rm /tmp/camera-ips.json
```

#### 4. Verify Decryption

```bash
# Test that secrets decrypt correctly
sudo nix-shell -p age --run "age -d -i /etc/age/keys.txt domains/secrets/parts/infrastructure/frigate-rtsp-username.age"
sudo nix-shell -p age --run "age -d -i /etc/age/keys.txt domains/secrets/parts/infrastructure/frigate-rtsp-password.age"
sudo nix-shell -p age --run "age -d -i /etc/age/keys.txt domains/secrets/parts/infrastructure/frigate-camera-ips.age" | jq
```

#### 5. Rebuild Configuration

```bash
cd ~/.nixos
git add domains/secrets/parts/infrastructure/frigate-*.age
git commit -m "secrets: update Frigate camera credentials"
sudo nixos-rebuild switch --flake .#hwc-server
```

#### 6. Regenerate Config and Restart

```bash
# Regenerate config with new credentials
sudo systemctl restart frigate-config.service

# Restart Frigate container
sudo systemctl restart podman-frigate.service

# Check logs
podman logs frigate | tail -50
```

---

## Common Operations

### Starting/Stopping Frigate

```bash
# Stop Frigate
sudo systemctl stop podman-frigate.service

# Start Frigate
sudo systemctl start podman-frigate.service

# Restart Frigate
sudo systemctl restart podman-frigate.service

# Check status
sudo systemctl status podman-frigate.service
```

### Viewing Logs

```bash
# Frigate container logs
podman logs frigate
podman logs frigate --tail 100
podman logs frigate --follow

# Config generation logs
journalctl -u frigate-config.service -n 50

# MQTT broker logs
journalctl -u mosquitto.service -n 50

# Storage pruning logs
journalctl -u frigate-storage-prune.service -n 50

# Camera watchdog logs
journalctl -u frigate-camera-watchdog.service -n 50
```

### Accessing the Web UI

```bash
# Via Tailscale (recommended)
https://hwc.ocelot-wahoo.ts.net:5000

# Or direct IP (if on local network)
http://192.168.1.13:5000
```

### Viewing Generated Config

```bash
cat /opt/surveillance/frigate/config/config.yaml
```

### Manual Service Triggers

```bash
# Manually run storage pruning
sudo systemctl start frigate-storage-prune.service
journalctl -u frigate-storage-prune.service -f

# Manually run camera health check
sudo systemctl start frigate-camera-watchdog.service
journalctl -u frigate-camera-watchdog.service -f
```

### Checking Storage Usage

```bash
# Check media storage size
du -sh /mnt/media/surveillance/frigate/media/

# Check buffer storage
du -sh /mnt/hot/surveillance/buffer/

# List recent recordings
ls -lh /mnt/media/surveillance/frigate/media/ | tail -20

# Count recording directories
find /mnt/media/surveillance/frigate/media/ -type d -name "????-??-??" | wc -l
```

### GPU Monitoring

```bash
# Check GPU usage (while Frigate is running)
nvidia-smi

# Watch GPU usage
watch -n 1 nvidia-smi

# Check GPU in container
podman exec frigate nvidia-smi
```

### Prometheus Metrics

```bash
# Storage metrics
cat /var/lib/node-exporter-textfile/frigate_storage.prom

# Camera health metrics
cat /var/lib/node-exporter-textfile/frigate_cameras.prom
```

---

## Troubleshooting

### Container Won't Start

**Symptom**: `podman-frigate.service` fails to start

**Check**:

```bash
# View detailed error
systemctl status podman-frigate.service -l

# Check if config was generated
ls -la /opt/surveillance/frigate/config/config.yaml

# Check config generation service
systemctl status frigate-config.service -l

# View podman container status
podman ps -a | grep frigate
```

**Solutions**:

1. **Config not generated**:
   ```bash
   sudo systemctl restart frigate-config.service
   journalctl -u frigate-config.service -n 50
   ```

2. **Secret permissions**:
   ```bash
   ls -la /run/agenix/frigate-*
   # Should be owned by root:root with mode 0400
   ```

3. **Container image pull failed**:
   ```bash
   podman pull ghcr.io/blakeblackshear/frigate:stable-tensorrt
   ```

4. **Port conflict**:
   ```bash
   sudo ss -tulpn | grep :5000
   # If port 5000 is in use, change hwc.server.frigate.settings.port
   ```

---

### RTSP Authentication Failures

**Symptom**: Cameras show "authentication failed" in Frigate logs

**Check**:

```bash
# View Frigate logs for auth errors
podman logs frigate | grep -i auth

# Check generated config has URL-encoded password
cat /opt/surveillance/frigate/config/config.yaml | grep rtsp://

# Verify secrets
sudo cat /run/agenix/frigate-rtsp-username
sudo cat /run/agenix/frigate-rtsp-password
```

**Solutions**:

1. **Password contains special characters**:
   - Config generation automatically URL-encodes passwords
   - Check that `?` becomes `%3F` in config.yaml
   - Example: `il0wwlm?` → `il0wwlm%3F`

2. **Test camera directly**:
   ```bash
   # Test RTSP stream with ffmpeg
   ffmpeg -rtsp_transport tcp -i "rtsp://admin:il0wwlm%3F@192.168.1.101:554/ch01/0" -frames:v 1 test.jpg
   ```

3. **Regenerate config with correct credentials**:
   ```bash
   sudo systemctl restart frigate-config.service
   sudo systemctl restart podman-frigate.service
   ```

---

### GPU Not Detected

**Symptom**: Frigate logs show "No GPU detected" or "falling back to CPU"

**Check**:

```bash
# Verify GPU module is enabled
nix eval --json .#nixosConfigurations.hwc-server.config.hwc.infrastructure.hardware.gpu.enable
# Should output: true

# Check NVIDIA driver loaded
nvidia-smi

# Check GPU in container
podman exec frigate nvidia-smi
```

**Solutions**:

1. **NVIDIA container toolkit not configured**:
   ```bash
   podman info | grep -i nvidia
   # Should show nvidia runtime
   ```

2. **GPU not passed to container**:
   - Check that `hwc.server.frigate.gpu.enable = true`
   - Container should have `--device=nvidia.com/gpu=0`

3. **Wrong detector config**:
   ```bash
   # For CPU detection
   hwc.server.frigate.gpu.detector = "cpu";

   # For GPU detection
   hwc.server.frigate.gpu.detector = "tensorrt";
   ```

4. **P1000 (Pascal) specific issue**:
   - MUST have `hwc.server.frigate.gpu.useFP16 = false;`
   - Pascal GPUs don't support FP16 precision

---

### Camera Offline / No Video

**Symptom**: Camera appears offline or no video feed

**Check**:

```bash
# Check Frigate API for camera status
curl -s http://localhost:5000/api/stats | jq '.cameras'

# Test camera connectivity
ping 192.168.1.101

# Test RTSP stream
ffprobe -rtsp_transport tcp "rtsp://admin:il0wwlm%3F@192.168.1.101:554/ch01/0"
```

**Solutions**:

1. **Camera unreachable**:
   - Check network connectivity
   - Verify camera IP in secret: `sudo cat /run/agenix/frigate-camera-ips | jq`
   - Power cycle camera

2. **Wrong RTSP path**:
   - Verify camera RTSP URL format: `rtsp://user:pass@IP:554/ch01/0`
   - Check camera documentation for correct path

3. **Disable camera temporarily**:
   - Edit camera config to set `enabled: false`
   - Or comment out camera in `parts/container.nix`

4. **View camera-specific logs**:
   ```bash
   podman logs frigate | grep cobra_cam_1
   ```

---

### Storage Pruning Not Working

**Symptom**: Storage exceeds 2TB cap, old recordings not deleted

**Check**:

```bash
# Check current storage usage
du -sh /mnt/media/surveillance/frigate/media/

# Check when pruning last ran
systemctl status frigate-storage-prune.service

# View pruning schedule
systemctl list-timers | grep frigate-storage

# View pruning logs
journalctl -u frigate-storage-prune.service -n 100
```

**Solutions**:

1. **Manually trigger pruning**:
   ```bash
   sudo systemctl start frigate-storage-prune.service
   journalctl -u frigate-storage-prune.service -f
   ```

2. **Adjust pruning schedule**:
   ```nix
   hwc.server.frigate.storage.pruneSchedule = "daily";  # or "hourly", "*:0/30", etc.
   ```

3. **Adjust storage cap**:
   ```nix
   hwc.server.frigate.storage.maxSizeGB = 3000;  # Increase cap
   ```

4. **Check for dated directories**:
   ```bash
   find /mnt/media/surveillance/frigate/media/ -type d -name "????-??-??" | head -20
   ```

---

### MQTT Not Working

**Symptom**: No events, notifications, or integrations working

**Check**:

```bash
# Check Mosquitto status
systemctl status mosquitto.service

# Test MQTT broker
mosquitto_sub -h 127.0.0.1 -p 1883 -t "frigate/#" -v

# Check Frigate MQTT connection
podman logs frigate | grep -i mqtt
```

**Solutions**:

1. **Mosquitto not running**:
   ```bash
   sudo systemctl start mosquitto.service
   sudo systemctl enable mosquitto.service
   ```

2. **MQTT disabled in config**:
   ```nix
   hwc.server.frigate.mqtt.enable = true;  # Must be enabled
   ```

3. **Port conflict**:
   ```bash
   sudo ss -tulpn | grep :1883
   ```

4. **Test MQTT publish**:
   ```bash
   mosquitto_pub -h 127.0.0.1 -p 1883 -t "test" -m "hello"
   mosquitto_sub -h 127.0.0.1 -p 1883 -t "test"
   ```

---

### Config Not Regenerating

**Symptom**: Changes to secrets not reflected in config.yaml

**Check**:

```bash
# Check when config was last generated
ls -lah /opt/surveillance/frigate/config/config.yaml

# Check config service status
systemctl status frigate-config.service
```

**Solutions**:

1. **Manually regenerate config**:
   ```bash
   sudo systemctl restart frigate-config.service
   journalctl -u frigate-config.service -f
   ```

2. **Check secret paths**:
   ```bash
   ls -la /run/agenix/frigate-*
   ```

3. **Restart entire stack**:
   ```bash
   sudo systemctl stop podman-frigate.service
   sudo systemctl restart frigate-config.service
   sudo systemctl start podman-frigate.service
   ```

4. **View config generation script**:
   ```bash
   systemctl cat frigate-config.service
   ```

---

### Assertions Failing During Build

**Symptom**: Build fails with assertion errors

**Common Assertions**:

```bash
# GPU required but not enabled
hwc.infrastructure.hardware.gpu.enable = true;

# TensorRT requires GPU
hwc.server.frigate.gpu.enable = true;  # if using detector = "tensorrt"

# MQTT required for Frigate
hwc.server.frigate.mqtt.enable = true;

# Secrets required
hwc.secrets.enable = true;

# Podman backend required
virtualisation.oci-containers.backend = "podman";
```

**Check Assertions**:

```bash
# View all assertions
nix eval --json .#nixosConfigurations.hwc-server.config.assertions | jq

# Build with full trace
sudo nixos-rebuild build --flake .#hwc-server --show-trace
```

---

### High CPU/Memory Usage

**Symptom**: Frigate consuming excessive resources

**Check**:

```bash
# View container resource usage
podman stats frigate

# Check current limits
podman inspect frigate | jq '.[].HostConfig.Memory'
podman inspect frigate | jq '.[].HostConfig.NanoCpus'
```

**Solutions**:

1. **Adjust resource limits**:
   ```nix
   hwc.server.frigate.resources = {
     memory = "6g";  # Increase from 4g
     cpus = "2.0";   # Increase from 1.5
     shmSize = "2g"; # Increase shared memory
   };
   ```

2. **Reduce camera resolution/FPS**:
   - Edit camera config in `parts/container.nix`
   - Lower resolution or fps reduces processing load

3. **Disable features**:
   - Disable object tracking for some cameras
   - Reduce detection areas with zones
   - Lower recording quality

---

### Web UI Not Accessible

**Symptom**: Cannot access Frigate web UI

**Check**:

```bash
# Test locally
curl http://localhost:5000

# Check Tailscale connectivity
tailscale status

# Verify firewall rules
sudo iptables -L -n | grep 5000
```

**Solutions**:

1. **Firewall blocking access**:
   ```bash
   # Check Tailscale interface exists
   ip addr show tailscale0

   # Verify Frigate ports on Tailscale
   sudo iptables -L INPUT -n -v | grep tailscale0
   ```

2. **Access from correct interface**:
   - ✅ Via Tailscale: `https://hwc.ocelot-wahoo.ts.net:5000`
   - ❌ Via WAN IP (firewall blocks non-Tailscale)

3. **Container not exposing port**:
   ```bash
   podman port frigate
   # Should show: 5000/tcp -> 0.0.0.0:5000
   ```

---

## Migration History

### From /etc/nixos to HWC (November 2025)

**Original Location**: `/etc/nixos/hosts/server/modules/surveillance.nix`

**Migration Completed**: 2025-11-01

**Changes Made**:

1. **Module Structure**:
   - Created `domains/server/frigate/` with Charter v6.0 compliance
   - Split into `options.nix` + `parts/` modules
   - Namespace: `hwc.server.frigate.*`

2. **Secrets Management**:
   - Migrated from SOPS to agenix
   - Moved secrets to infrastructure domain
   - Path: `domains/secrets/parts/infrastructure/frigate-*.age`
   - Runtime access via `/run/agenix/`

3. **Configuration**:
   - Dynamic config generation from secrets
   - URL-encoded RTSP passwords
   - Systemd service dependencies

4. **Feature Parity**:
   - ✅ All 4 cameras configured (3 active, 1 disabled)
   - ✅ GPU acceleration (TensorRT)
   - ✅ MQTT integration
   - ✅ Storage pruning (hourly, 2TB cap)
   - ✅ Camera health watchdog (30min intervals)
   - ✅ Prometheus metrics export
   - ✅ Hot/cold storage tiers

5. **Improvements**:
   - Charter-compliant validation assertions
   - Proper domain boundaries
   - Options-based configuration (no hardcoded values)
   - Namespace follows folder structure for debugging

**Legacy Config Archived**: `/etc/nixos/archive/frigate-migration-20251101/`

**Rollback Procedure** (if needed):

```bash
# Disable HWC Frigate
hwc.server.frigate.enable = false;

# Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# Re-enable legacy config
cd /etc/nixos
# Uncomment surveillance module
sudo nixos-rebuild switch
```

---

## Charter Compliance Summary

✅ **§3 Domain Boundaries**: Server domain, no HM configs
✅ **§4 Mandatory options.nix**: All options in dedicated file
✅ **§11 Namespace Rules**: `hwc.server.frigate.*` follows folder structure
✅ **§18 Validation**: 7 assertions for dependencies
✅ **§0 Preserve-First**: 100% feature parity with `/etc/nixos`
✅ **Secrets**: Via agenix stable API (`/run/agenix/`)
✅ **Parts**: Pure helper modules, no side effects
✅ **Documentation**: This comprehensive guide

---

## Additional Documentation

- **[HARDWARE-ACCELERATION.md](./HARDWARE-ACCELERATION.md)**: Comprehensive analysis of current vs Intel VAAPI/QuickSync setups
  - Performance & power comparison
  - Migration strategies (Full Intel, Hybrid, CPU fallback)
  - Verification & troubleshooting guides
  - Power cost analysis

- **[TUNING-GUIDE.md](./TUNING-GUIDE.md)**: Quick reference for configuration adjustments
  - Adding/removing cameras
  - Adjusting resolution and FPS
  - Recording modes and storage optimization
  - Shared memory sizing
  - Container resource limits
  - Performance tuning matrix

---

## Support & References

- **Frigate Documentation**: https://docs.frigate.video/
- **TensorRT Models**: https://docs.frigate.video/configuration/object_detectors#nvidia-tensorrt-detector
- **Go2RTC Streams**: https://docs.frigate.video/configuration/go2rtc
- **HWC Charter**: `/home/eric/.nixos/CHARTER.md`
- **Agenix Secrets**: `/home/eric/.nixos/domains/secrets/`

---

**Last Updated**: 2025-11-19
**Module Version**: 2.0.0 (Hardware Acceleration Refactor)
**Charter Version**: v6.0
