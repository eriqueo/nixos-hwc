# Frigate NVR - Comprehensive Optimization Plan

**Created**: 2025-12-06
**Target**: Complete security fixes, performance optimization, and monitoring integration
**Estimated Time**: 3-4 hours across 4 phases

---

## Executive Summary

Based on exploration of your Frigate configuration, here are the main areas requiring attention:

**Critical Issues**:
- 🔴 **Security**: Hardcoded RTSP credentials in config.yml (should use agenix secrets)
- 🟡 **Path Inconsistency**: Mixed use of "frigate" and "frigate-v2" in storage paths
- 🟡 **Outdated Scripts**: launch_frigate.sh references Docker instead of Podman

**Optimization Opportunities**:
- Camera detection zones need tuning
- GPU detector settings can be optimized
- Storage retention policies need review
- Performance monitoring needed

**Good News**:
- ✅ Charter v7.0 compliant
- ✅ GPU acceleration working (NVIDIA P1000)
- ✅ Proper containerization (Podman)
- ✅ Good documentation

---

## Current State Analysis

### Architecture
- **Type**: Containerized (Podman) with config-first pattern
- **Image**: `ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt`
- **GPU**: NVIDIA Quadro P1000 (ONNX detector, CUDA enabled)
- **Cameras**: 3 IP cameras configured (cobra_cam_1, cobra_cam_2, cobra_cam_3)
- **Storage**: 7-day recording retention, 10-day clips/alerts retention

### Current Issues

**Security** (Critical):
```yaml
# config.yml currently has:
rtsp://admin:il0wwlm%3F@192.168.1.101:554/stream1

# Should use:
rtsp://${FRIGATE_RTSP_USERNAME}:${FRIGATE_RTSP_PASSWORD}@${CAMERA_1_IP}:554/stream1
```

**Storage Paths** (Inconsistency):
```
Config:  /opt/surveillance/frigate/config          # "frigate"
Media:   /mnt/media/surveillance/frigate-v2/media  # "frigate-v2" ❌
Buffer:  /mnt/hot/surveillance/frigate/buffer      # "frigate"
```

**Performance**:
- Camera 1: 1280x720 @ 1fps (may be too low for motion)
- Camera 2: 640x360 @ 1fps
- Camera 3: 320x240 @ 1fps (very low resolution)
- Detection zones may be too broad
- No performance metrics exposed to Prometheus

---

## Phase A: Security Fixes & Path Standardization

**Priority**: 🔴 CRITICAL
**Time**: 30-45 minutes
**Goal**: Fix hardcoded credentials, standardize storage paths

### A.1: Fix RTSP Credential Templating

**Current Problem**: config.yml has hardcoded credentials, bypassing agenix secrets

**Files to Modify**:
1. `/home/eric/.nixos/domains/server/frigate/config/config.yml`
2. `/home/eric/.nixos/domains/server/frigate/index.nix` (verify envsubst logic)

**Changes**:

**config.yml** - Replace hardcoded URLs with template placeholders:

```yaml
cameras:
  cobra_cam_1:
    ffmpeg:
      inputs:
        - path: rtsp://${FRIGATE_RTSP_USERNAME}:${FRIGATE_RTSP_PASSWORD}@${CAMERA_1_IP}:554/stream1
          roles:
            - detect

  cobra_cam_2:
    ffmpeg:
      inputs:
        - path: rtsp://${FRIGATE_RTSP_USERNAME}:${FRIGATE_RTSP_PASSWORD}@${CAMERA_2_IP}:554/stream1
          roles:
            - detect

  cobra_cam_3:
    ffmpeg:
      inputs:
        - path: rtsp://${FRIGATE_RTSP_USERNAME}:${FRIGATE_RTSP_PASSWORD}@${CAMERA_3_IP}:554/stream1
          roles:
            - detect
```

**index.nix** - Verify environment variable substitution (should already exist):

```nix
# In preStart script (around line 180-200)
environment = {
  FRIGATE_RTSP_USERNAME = "$(cat ${config.age.secrets.frigate-rtsp-username.path})";
  FRIGATE_RTSP_PASSWORD = "$(cat ${config.age.secrets.frigate-rtsp-password.path})";

  # Camera IPs from secret
  CAMERA_1_IP = "\$(echo '${camera-ips}' | jq -r '.camera1')";
  CAMERA_2_IP = "\$(echo '${camera-ips}' | jq -r '.camera2')";
  CAMERA_3_IP = "\$(echo '${camera-ips}' | jq -r '.camera3')";
};

# Substitute in preStart
envsubst < ${configTemplate} > /opt/surveillance/frigate/config/config.yml
```

**Verification**:
```bash
# After rebuild, check config has no hardcoded credentials
sudo cat /opt/surveillance/frigate/config/config.yml | grep -E "rtsp://admin"
# Should return nothing

# Check secrets are substituted
sudo cat /opt/surveillance/frigate/config/config.yml | grep -E "rtsp://.*@192"
# Should show actual IPs (from secrets)
```

### A.2: Standardize Storage Paths

**Decision Needed**: Choose between "frigate" or "frigate-v2"

**Recommendation**: Use "frigate" (simpler, current standard)

**Migration Steps**:

```bash
# 1. Stop Frigate
sudo systemctl stop podman-frigate

# 2. Move frigate-v2 media to frigate
sudo mkdir -p /mnt/media/surveillance/frigate/media
sudo rsync -av --progress /mnt/media/surveillance/frigate-v2/media/ /mnt/media/surveillance/frigate/media/

# 3. Verify
sudo du -sh /mnt/media/surveillance/frigate/media
sudo du -sh /mnt/media/surveillance/frigate-v2/media

# 4. Update NixOS config (machines/server/config.nix)
hwc.server.frigate.storage.mediaPath = "/mnt/media/surveillance/frigate/media";

# 5. Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# 6. Cleanup old path (after verifying new path works)
sudo rm -rf /mnt/media/surveillance/frigate-v2
```

**Files to Update**:
- `machines/server/config.nix` - Update mediaPath
- `domains/server/frigate/index.nix` - Update cleanup script paths (line ~250)

### A.3: Remove/Update Outdated Scripts

**File to Remove or Update**: `/home/eric/.nixos/workspace/automation/media/launch_frigate.sh`

**Option 1: Delete** (recommended - replaced by NixOS config):
```bash
rm /home/eric/.nixos/workspace/automation/media/launch_frigate.sh
```

**Option 2: Update** (if you want to keep it for manual testing):
```bash
# Update to use Podman and current config
# Change references from docker → podman
# Use current image tag: 0.16.2-tensorrt
# Remove hardcoded credentials
```

**Recommendation**: Delete it - the NixOS module handles everything now.

### A.4: Validation

**Add assertion to index.nix**:

```nix
# In VALIDATION section
assertions = [
  # ... existing assertions

  # Phase A assertion - no hardcoded credentials
  {
    assertion = !(builtins.pathExists cfg.storage.configPath &&
                  builtins.match ".*admin:.*@.*" (builtins.readFile "${cfg.storage.configPath}/config.yml") != null);
    message = "Frigate config.yml must not contain hardcoded credentials - use agenix secrets";
  }
];
```

**Testing**:
```bash
# 1. Rebuild
sudo nixos-rebuild test --flake .#hwc-server

# 2. Check service status
systemctl status podman-frigate

# 3. Verify cameras connect
curl -s http://localhost:5001/api/stats | jq '.cameras'

# 4. Check logs for auth errors
sudo journalctl -u podman-frigate -n 50 | grep -i "auth\|401\|403"

# 5. Apply if successful
sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Phase B: Performance Optimization

**Priority**: 🟡 MEDIUM
**Time**: 1-1.5 hours
**Goal**: Optimize camera settings, detection zones, GPU utilization

### B.1: Camera Resolution & FPS Optimization

**Current Settings** (too low for good detection):
```yaml
cobra_cam_1: 1280x720 @ 1fps
cobra_cam_2: 640x360 @ 1fps
cobra_cam_3: 320x240 @ 1fps
```

**Recommended Settings** (balance quality vs performance):

**High-Priority Camera** (cobra_cam_1 - yard_gate):
```yaml
cobra_cam_1:
  ffmpeg:
    inputs:
      - path: rtsp://...
        input_args: preset-rtsp-generic
        roles:
          - detect
      - path: rtsp://...  # Higher res stream for recording
        input_args: preset-rtsp-generic
        roles:
          - record

  detect:
    width: 1280
    height: 720
    fps: 5  # Increase from 1 → 5 for better motion detection

  record:
    enabled: true
    retain:
      days: 7
      mode: motion  # Only record on motion (save space)
    events:
      retain:
        default: 10
        mode: active_objects
```

**Medium-Priority Cameras** (cobra_cam_2, cobra_cam_3):
```yaml
cobra_cam_2:
  detect:
    width: 640
    height: 360
    fps: 3  # Increase from 1 → 3

  # Same record config as cam_1

cobra_cam_3:
  detect:
    width: 640   # Increase from 320x240 → 640x480
    height: 480
    fps: 3  # Increase from 1 → 3
```

**Rationale**:
- 1fps is too low for motion detection (misses fast movement)
- 3-5fps is optimal balance (Frigate recommends 5fps for detect)
- Higher resolution for recording, lower for detection saves GPU

### B.2: Detection Zone Refinement

**Current Zones** (may be too broad):

```yaml
# cobra_cam_1 - yard_gate
zones:
  yard_gate:
    coordinates: 0,1080,1280,1080,1280,504,0,720  # Full bottom 2/3
```

**Optimization Strategy**:

1. **Reduce zone coverage** - only monitor critical areas
2. **Add motion masks** - exclude trees, sky, static objects
3. **Fine-tune object filters** - reduce false positives

**Example Optimized Zone**:

```yaml
cobra_cam_1:
  zones:
    yard_gate:
      coordinates: 200,900,1000,900,1000,600,200,600  # Narrower focus on gate
      objects:
        - person
        - dog
        - cat
      filters:
        person:
          min_area: 5000   # Filter out distant/small detections
          threshold: 0.7   # Higher confidence threshold

  motion:
    mask:
      - 0,0,1280,200      # Mask sky
      - 0,900,150,1080    # Mask left edge
      - 1130,900,1280,1080  # Mask right edge
```

**How to Determine Coordinates**:

1. Open Frigate UI: http://localhost:5001
2. Navigate to camera → Debug
3. Enable "Motion boxes" and "Object boxes"
4. Screenshot the view
5. Use coordinates to define zones (format: x1,y1,x2,y2,x3,y3,x4,y4)

**Tool to Help**: Create a zone helper script

### B.3: GPU Detector Tuning

**Current Config**:
```yaml
detectors:
  onnx:
    type: onnx
    device: '0'
    num_threads: 3
    execution_providers:
      - cuda
      - cpu
```

**Optimizations**:

**Option 1: Keep ONNX** (current, stable):
```yaml
detectors:
  onnx:
    type: onnx
    device: '0'
    num_threads: 4  # Increase from 3 → 4 (better CPU assist)
    execution_providers:
      - cuda
      - cpu

model:
  width: 320
  height: 320
  input_dtype: float
  path: /config/model_cache/tensorrt/yolov9-s-320.onnx
  input_pixel_format: rgb
  labelmap_path: /labelmap/coco-80.txt
```

**Option 2: Try TensorRT** (faster, but more GPU memory):
```yaml
detectors:
  tensorrt:
    type: tensorrt
    device: 0  # Integer for TensorRT

model:
  width: 320
  height: 320
  input_dtype: uint8  # TensorRT uses uint8
  path: /config/model_cache/tensorrt/yolov9-s-320.trt
```

**Recommendation**: Stick with ONNX for P1000 (more stable, less VRAM)

### B.4: Recording & Retention Optimization

**Current Settings**:
```yaml
record:
  retain:
    days: 7
    mode: all  # Records 24/7, uses lots of space
```

**Optimized Settings** (save storage):

```yaml
record:
  enabled: true
  retain:
    days: 7
    mode: motion  # Only record when motion detected

  events:
    pre_capture: 5   # Seconds before event
    post_capture: 5  # Seconds after event
    retain:
      default: 10    # Keep event clips for 10 days
      mode: active_objects  # Only when objects detected
      objects:
        person: 30   # Keep person detections for 30 days
        car: 14      # Keep car detections for 14 days
        dog: 10
        cat: 10

snapshots:
  enabled: true
  retain:
    default: 10
    objects:
      person: 30  # Keep person snapshots longer
```

**Estimated Storage Savings**:
- **Before**: ~50-100 GB/week (continuous recording, 3 cameras)
- **After**: ~10-20 GB/week (motion-only recording)

### B.5: Add NixOS Options for Tuning

**Create new options** in `options.nix`:

```nix
# domains/server/frigate/options.nix

performance = {
  detectorThreads = mkOption {
    type = types.int;
    default = 4;
    description = "Number of CPU threads for detector (3-6 recommended)";
  };

  recordingMode = mkOption {
    type = types.enum [ "all" "motion" "active_objects" ];
    default = "motion";
    description = ''
      Recording mode:
      - all: Continuous 24/7 recording
      - motion: Record only when motion detected
      - active_objects: Record only when objects detected
    '';
  };

  defaultFps = mkOption {
    type = types.int;
    default = 5;
    description = "Default FPS for camera detection (3-5 recommended)";
  };
};
```

**Use in config template** (index.nix):

```nix
# Generate config.yml dynamically
configTemplate = pkgs.writeText "frigate-config.yml" ''
  detectors:
    onnx:
      type: onnx
      device: '0'
      num_threads: ${toString cfg.performance.detectorThreads}

  record:
    retain:
      mode: ${cfg.performance.recordingMode}

  # ... rest of config
'';
```

### B.6: Testing & Benchmarking

**Performance Test Plan**:

```bash
# 1. Baseline metrics (before optimization)
# Check CPU usage
top -b -n 1 | grep frigate

# Check GPU usage
nvidia-smi dmon -s pucvmt -c 60

# Check detection inference speed
curl -s http://localhost:5001/api/stats | jq '.detectors.onnx.inference_speed'

# 2. Apply optimizations (rebuild with new config)
sudo nixos-rebuild switch --flake .#hwc-server

# 3. Monitor for 10 minutes
watch -n 5 'curl -s http://localhost:5001/api/stats | jq "{cpu: .cpu_usages, gpu: .gpu_usages, fps: .cameras | to_entries | map({(.key): .value.camera_fps})}"'

# 4. Compare metrics
# Target inference speed: <50ms
# Target CPU usage: <30%
# Target GPU utilization: 20-60%
# Target detection FPS: 5fps per camera
```

**Expected Improvements**:
- Detection accuracy: +30-50% (from higher FPS)
- False positives: -40-60% (from better zones/filters)
- Storage usage: -60-70% (from motion-only recording)
- Inference speed: Similar or better (better threading)

---

## Phase C: Monitoring & Metrics Integration

**Priority**: 🟢 NICE-TO-HAVE
**Time**: 45-60 minutes
**Goal**: Integrate Frigate with Prometheus/Grafana

### C.1: Prometheus Metrics Export

**Frigate API Endpoints**:
- `/api/stats` - Overall stats (CPU, GPU, detection speed)
- `/api/stats/cameras` - Per-camera stats

**Add Prometheus Exporter** (built into Frigate, just needs enabling):

**config.yml**:
```yaml
mqtt:
  enabled: false  # Keep disabled unless you have MQTT broker

telemetry:
  enabled: true  # Enable telemetry
  port: 9090     # Prometheus metrics port (internal to container)
```

**index.nix** - Expose metrics port:

```nix
# In virtualisation.oci-containers.containers.frigate
ports = [
  "5001:5000"   # Web UI
  "8554:8554"   # RTSP
  "8555:8555/tcp"  # WebRTC
  "8555:8555/udp"
  "9191:9090"   # Prometheus metrics (map to 9191 to avoid conflict)
];
```

**Add options.nix**:

```nix
observability = {
  metrics = {
    enable = mkEnableOption "Prometheus metrics" // { default = true; };

    port = mkOption {
      type = types.port;
      default = 9191;
      description = "Prometheus metrics port (external)";
    };
  };
};
```

### C.2: Prometheus Scrape Configuration

**Add to index.nix** (after container definition):

```nix
# Prometheus integration
hwc.services.prometheus.scrapeConfigs = lib.mkIf (cfg.enable && cfg.observability.metrics.enable) [
  {
    job_name = "frigate-nvr";
    static_configs = [{
      targets = [ "localhost:${toString cfg.observability.metrics.port}" ];
    }];
    scrape_interval = "30s";
    scrape_timeout = "10s";
    metrics_path = "/metrics";  # Frigate exposes on /metrics
  }
];
```

**Validation**:

```nix
# Add assertion
{
  assertion = !(cfg.enable && cfg.observability.metrics.enable) || config.hwc.services.prometheus.enable;
  message = "Frigate metrics require Prometheus to be enabled";
}
```

### C.3: Grafana Dashboard

**Create**: `/home/eric/.nixos/domains/server/frigate/FRIGATE-GRAFANA-DASHBOARD.json`

**Key Panels**:

1. **Camera Health**:
   - Detection FPS per camera
   - Camera uptime
   - RTSP connection status

2. **Detection Performance**:
   - Inference speed (ms)
   - Detection queue depth
   - Objects detected per hour

3. **Resource Usage**:
   - CPU utilization
   - GPU utilization (from nvidia-smi)
   - Memory usage
   - Disk I/O

4. **Storage Metrics**:
   - Recording storage used
   - Clips storage used
   - Recordings older than X days

**Minimal Dashboard Structure**:

```json
{
  "dashboard": {
    "title": "Frigate NVR Monitoring",
    "panels": [
      {
        "title": "Camera FPS",
        "targets": [{
          "expr": "frigate_camera_fps",
          "legendFormat": "{{camera}}"
        }]
      },
      {
        "title": "Detection Inference Speed",
        "targets": [{
          "expr": "frigate_detector_inference_speed_seconds",
          "legendFormat": "{{detector}}"
        }]
      },
      {
        "title": "GPU Utilization",
        "targets": [{
          "expr": "nvidia_gpu_utilization_percent{gpu='0'}",
          "legendFormat": "GPU 0"
        }]
      },
      {
        "title": "Objects Detected (Last Hour)",
        "targets": [{
          "expr": "increase(frigate_detections_total[1h])",
          "legendFormat": "{{label}}"
        }]
      }
    ]
  }
}
```

**Note**: Actual metric names may vary - discover using:
```bash
curl -s http://localhost:9191/metrics
```

### C.4: Alerting Rules (Optional)

**Create alert conditions**:

```nix
# In Prometheus configuration
services.prometheus.rules = [
  ''
    groups:
      - name: frigate_alerts
        interval: 30s
        rules:
          # Camera offline
          - alert: FrigateCameraOffline
            expr: frigate_camera_fps == 0
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Frigate camera {{ $labels.camera }} is offline"

          # High inference time
          - alert: FrigateSlowDetection
            expr: frigate_detector_inference_speed_seconds > 0.1
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Frigate detection slow (>100ms)"

          # GPU not being used
          - alert: FrigateGPUNotUsed
            expr: nvidia_gpu_utilization_percent{gpu="0"} < 5 and frigate_camera_fps > 0
            for: 10m
            labels:
              severity: critical
            annotations:
              summary: "Frigate GPU not being utilized"
  ''
];
```

### C.5: Testing Metrics

```bash
# 1. Verify metrics endpoint
curl http://localhost:9191/metrics | head -50

# 2. Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job == "frigate-nvr")'

# 3. Query metrics
curl -s 'http://localhost:9090/api/v1/query?query=frigate_camera_fps' | jq

# 4. Import Grafana dashboard
# Navigate to http://localhost:3000
# Administration → Dashboards → Import
# Upload FRIGATE-GRAFANA-DASHBOARD.json
```

---

## Phase D: Documentation & Cleanup

**Priority**: 🟢 MAINTENANCE
**Time**: 30 minutes
**Goal**: Update documentation, clean up old files, verify Charter compliance

### D.1: Update README.md

**Add new sections** to `/home/eric/.nixos/domains/server/frigate/README.md`:

1. **Performance Tuning** section:
   - Camera FPS recommendations
   - Detection zone best practices
   - Recording mode trade-offs
   - GPU optimization tips

2. **Monitoring & Metrics** section:
   - Prometheus integration
   - Grafana dashboard
   - Key metrics to watch
   - Alert configuration

3. **Troubleshooting** section:
   - Camera not detecting
   - High CPU/GPU usage
   - Storage filling up
   - Auth failures

4. **Configuration Reference** section:
   - All NixOS options documented
   - Example configurations
   - Migration notes

### D.2: Create Configuration Examples

**File**: `/home/eric/.nixos/domains/server/frigate/examples/`

**Create examples**:

1. `low-resource.yml` - Minimal config for low-end hardware
2. `high-quality.yml` - High FPS, high resolution for powerful systems
3. `balanced.yml` - Recommended settings (our target)
4. `zones-template.yml` - Detection zone examples

### D.3: Cleanup Old Files

**Files to remove**:
```bash
rm /home/eric/.nixos/workspace/automation/media/launch_frigate.sh  # Outdated Docker script
rm -rf /mnt/media/surveillance/frigate-v2  # After migration to frigate/
```

**Files to verify**:
- `/home/eric/.nixos/domains/server/frigate/scripts/verify-config.sh` - Still useful
- `/home/eric/.nixos/workspace/utilities/frigate-health.sh` - Still useful

### D.4: Add Implementation Status Tracking

**Add to README.md**:

```markdown
## Implementation Status

| Phase | Component | Status | Date |
|-------|-----------|--------|------|
| **A** | **Security & Paths** | - | - |
| A.1 | RTSP Secret Templating | ⏳ | - |
| A.2 | Storage Path Standardization | ⏳ | - |
| A.3 | Script Cleanup | ⏳ | - |
| **B** | **Performance** | - | - |
| B.1 | Camera FPS Optimization | ⏳ | - |
| B.2 | Detection Zones | ⏳ | - |
| B.3 | GPU Tuning | ⏳ | - |
| B.4 | Recording Optimization | ⏳ | - |
| **C** | **Monitoring** | - | - |
| C.1 | Prometheus Metrics | ⏳ | - |
| C.2 | Grafana Dashboard | ⏳ | - |
| **D** | **Documentation** | - | - |
| D.1 | README Updates | ⏳ | - |

**Legend**: ⏳ Planned | 🚧 In Progress | ✅ Complete
```

### D.5: Charter Compliance Verification

**Run linter**:
```bash
./workspace/utilities/lints/charter-lint.sh domains/server/frigate
```

**Verify**:
- ✅ Namespace: `hwc.server.frigate.*`
- ✅ Module structure: options.nix, index.nix, config/
- ✅ No cross-lane imports
- ✅ VALIDATION section present
- ✅ Secrets via agenix
- ✅ Config-first pattern (Charter v7.0 Section 19)

---

## Testing & Validation

### Pre-Implementation Baseline

**Capture current state**:

```bash
# 1. Export current config
cp /opt/surveillance/frigate/config/config.yml \
   ~/frigate-config-backup-$(date +%Y%m%d).yml

# 2. Capture performance metrics
curl -s http://localhost:5001/api/stats > ~/frigate-stats-before.json

# 3. Check storage usage
du -sh /mnt/media/surveillance/frigate* > ~/frigate-storage-before.txt

# 4. Test camera connectivity
for cam in 1 2 3; do
  ffprobe -v error rtsp://admin:PASSWORD@192.168.1.10$cam:554/stream1 2>&1 | head -5
done > ~/frigate-cameras-before.txt
```

### Post-Implementation Verification

**After each phase, verify**:

```bash
# 1. Service health
systemctl status podman-frigate
curl -s http://localhost:5001/api/stats | jq '.service.uptime'

# 2. Camera connectivity
curl -s http://localhost:5001/api/stats | jq '.cameras | to_entries | map({(.key): .value.camera_fps})'

# 3. GPU utilization
nvidia-smi --query-gpu=utilization.gpu,utilization.memory --format=csv,noheader

# 4. Detection performance
curl -s http://localhost:5001/api/stats | jq '.detectors.onnx.inference_speed'

# 5. Storage usage
du -sh /mnt/media/surveillance/frigate/media/
```

### Success Criteria

**Phase A**:
- ✅ No hardcoded credentials in config.yml
- ✅ All cameras connect successfully
- ✅ Consistent storage paths (all "frigate" or all "frigate-v2")
- ✅ No auth errors in logs

**Phase B**:
- ✅ Detection FPS: 5fps per camera (up from 1fps)
- ✅ Inference speed: <50ms
- ✅ False positives reduced by 40%+
- ✅ Storage usage reduced by 60%+ (with motion-only recording)

**Phase C**:
- ✅ Prometheus scraping Frigate metrics
- ✅ Grafana dashboard showing live data
- ✅ All panels populated with metrics

**Phase D**:
- ✅ README.md comprehensive and up-to-date
- ✅ Old files removed
- ✅ Charter compliance verified

---

## Rollback Plan

**If issues occur during implementation**:

### Quick Rollback

```bash
# 1. Restore previous config
sudo cp ~/frigate-config-backup-YYYYMMDD.yml /opt/surveillance/frigate/config/config.yml

# 2. Restart container
sudo systemctl restart podman-frigate

# 3. Verify
curl http://localhost:5001/api/stats
```

### Full Rollback via Git

```bash
# 1. Revert NixOS changes
cd /home/eric/.nixos
git diff domains/server/frigate/  # Review changes
git checkout domains/server/frigate/  # Revert if needed

# 2. Rebuild
sudo nixos-rebuild switch --flake .#hwc-server

# 3. Verify service
systemctl status podman-frigate
```

### Data Recovery

**If storage migration fails**:

```bash
# Original data is preserved in frigate-v2 until manually deleted
# Can always switch back:
sudo systemctl stop podman-frigate

# Update config to use frigate-v2 path
hwc.server.frigate.storage.mediaPath = "/mnt/media/surveillance/frigate-v2/media";

sudo nixos-rebuild switch --flake .#hwc-server
```

---

## Appendix A: Camera Zone Helper Script

**Create**: `/home/eric/.nixos/workspace/utilities/frigate-zone-helper.sh`

```bash
#!/usr/bin/env bash
# Frigate Zone Configuration Helper

echo "Frigate Zone Helper"
echo "==================="
echo ""
echo "1. Open Frigate UI: http://localhost:5001"
echo "2. Select camera from dropdown"
echo "3. Click 'Debug' tab"
echo "4. Enable 'Motion boxes' and 'Object boxes'"
echo "5. Take screenshot and note coordinates"
echo ""
echo "Zone coordinate format: x1,y1,x2,y2,x3,y3,x4,y4"
echo ""
echo "Example for 1280x720 camera:"
echo "  Top-left corner:     0,0"
echo "  Top-right corner:    1280,0"
echo "  Bottom-right corner: 1280,720"
echo "  Bottom-left corner:  0,720"
echo ""
echo "Recommended zones:"
echo "  - Cover 60-80% of frame (avoid edges)"
echo "  - Exclude sky, trees, static objects"
echo "  - Focus on entry/exit points"
echo ""
echo "Press Enter to continue..."
read
```

---

## Appendix B: Storage Estimation

**Current Usage** (7 days, 3 cameras, continuous):
```
Camera 1 (720p @ 1fps):  ~15 GB/week
Camera 2 (360p @ 1fps):  ~5 GB/week
Camera 3 (240p @ 1fps):  ~3 GB/week
Total:                   ~23 GB/week
```

**After Optimization** (7 days, motion-only):
```
Camera 1 (720p @ 5fps, motion): ~8 GB/week
Camera 2 (360p @ 3fps, motion): ~3 GB/week
Camera 3 (480p @ 3fps, motion): ~4 GB/week
Total:                          ~15 GB/week

Savings: ~35% (primarily from smarter recording, not continuous)
```

**With Event-Only Recording**:
```
Total: ~5-8 GB/week (60-70% savings)
```

---

## Appendix C: Useful Commands

**Configuration**:
```bash
# Validate config syntax
sudo podman exec frigate python -m frigate.config_validator

# View runtime config
curl -s http://localhost:5001/api/config | jq

# Test camera stream
ffprobe -v error rtsp://admin:PASS@IP:554/stream1
```

**Monitoring**:
```bash
# Watch live stats
watch -n 2 'curl -s http://localhost:5001/api/stats | jq'

# Check detection queue
curl -s http://localhost:5001/api/stats | jq '.detection_queue'

# View events
curl -s http://localhost:5001/api/events | jq '.[] | {camera, label, start_time}'
```

**Troubleshooting**:
```bash
# Container logs
sudo podman logs -f frigate

# Systemd service logs
sudo journalctl -u podman-frigate -f

# Check GPU access
sudo podman exec frigate nvidia-smi

# Test RTSP auth
ffmpeg -rtsp_transport tcp -i rtsp://USER:PASS@IP:554/stream1 -frames:v 1 test.jpg
```

---

**Next Steps**: Review this plan and let me know when you'd like to proceed with implementation. We can tackle phases sequentially or all at once.

**Estimated Total Time**: 3-4 hours for all phases
**Priority Order**: A (security) → B (performance) → C (monitoring) → D (docs)
