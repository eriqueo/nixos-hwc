# Frigate Migration to Config-First Pattern

**Status**: 📋 PLANNING (not yet executed)
**Target**: Separate `frigate-v2` module following Charter v7.0 Section 19
**Current Module**: `domains/server/frigate/` (Nix-generated config, stays running)
**New Module**: `domains/server/frigate-v2/` (config-first pattern)

---

## Overview

This document outlines the migration from the current Nix-generated Frigate configuration to the config-first pattern established in Charter v7.0 Section 19.

**Strategy**: Build a **separate new module** (`frigate-v2`) rather than modifying the existing one, allowing:
- ✅ Current Frigate keeps running (zero downtime)
- ✅ New module can be developed and tested independently
- ✅ Easy comparison between old and new
- ✅ Simple rollback if needed (just switch imports)
- ✅ Clean migration with explicit cutover point

---

## Phase 1: Extract Current Runtime Config (Documentation Only)

### Goal

Capture the exact YAML that Frigate is currently using as the baseline for the new module.

### Steps (To Be Executed When Ready)

#### 1. Extract Runtime Config

The current Frigate generates its config via `frigate-config.service`. Extract the actual running configuration:

```bash
# Find the generated config
sudo cat /opt/surveillance/frigate/config/config.yaml

# Or from inside the container
sudo podman exec frigate cat /config/config.yaml
```

**Expected Output**: Full Frigate YAML with:
- MQTT configuration
- Detector configuration (ONNX or TensorRT)
- Camera definitions (cobra_cam_1, cobra_cam_2, cobra_cam_3)
- FFmpeg settings
- go2rtc streams
- Object tracking config

#### 2. Save as Baseline

```bash
# Create config directory in new module (will be created in later phase)
mkdir -p domains/server/frigate-v2/config

# Save extracted config
sudo podman exec frigate cat /config/config.yaml > domains/server/frigate-v2/config/config.baseline.yml

# Review the config
cat domains/server/frigate-v2/config/config.baseline.yml
```

**Important**: This baseline captures:
- ✅ URL-encoded RTSP passwords
- ✅ Camera IP addresses (from secrets)
- ✅ Current detector configuration
- ✅ FFmpeg hardware acceleration settings

#### 3. Identify Secret Placeholders

The baseline config will have secrets embedded (from `/run/agenix/`). Identify what needs to be templated:

```yaml
# Example from current config:
cameras:
  cobra_cam_1:
    ffmpeg:
      inputs:
        - path: rtsp://admin:il0wwlm%3F@192.168.1.101:554/ch01/0  # Secret embedded!
```

**Action Items**:
- [ ] List all secret values in baseline
- [ ] Decide on substitution strategy:
  - Option A: Environment variables (e.g., `${RTSP_USER}`)
  - Option B: Nix-generated config stub (minimal, just substituting secrets)
  - Option C: Keep secrets in separate file mounted to container

#### 4. Document Current Behavior

Before changing anything, document what's working:

```bash
# Test that current Frigate is working
curl -s http://localhost:5000/api/stats | jq '.cameras'

# Verify ONNX detector status
sudo podman logs frigate | grep -i onnx | tail -20

# Check GPU usage
nvidia-smi
```

**Checklist**:
- [ ] All 3 cameras online
- [ ] ONNX detector loaded successfully
- [ ] No dtype errors in logs
- [ ] GPU is being used for detection
- [ ] Recordings are working
- [ ] MQTT events are publishing

---

## Current vs Target Architecture

### Current (domains/server/frigate/)

```
domains/server/frigate/
├── options.nix                    # All Frigate options (detector, hwaccel, cameras, etc.)
├── index.nix                      # Module aggregator
├── parts/
│   ├── container.nix              # Generates YAML + starts container ❌
│   ├── mqtt.nix                   # MQTT broker
│   ├── storage.nix                # Storage pruning
│   └── watchdog.nix               # Camera health monitoring
├── README.md
├── HARDWARE-ACCELERATION.md
├── TUNING-GUIDE.md
└── CONFIGURATION-RETROSPECTIVE.md
```

**Problems**:
- ❌ YAML structure hidden in Nix string interpolation
- ❌ Config generated at runtime, not version-controlled
- ❌ Debugging requires inspecting generated files
- ❌ Not portable outside NixOS

### Target (domains/server/frigate-v2/)

```
domains/server/frigate-v2/
├── options.nix                    # Infrastructure options ONLY (image, ports, GPU)
├── index.nix                      # Container definition (no YAML generation)
├── config/
│   ├── config.yml                 # ✅ CANONICAL CONFIG (version-controlled)
│   ├── config.template.yml        # Template for secret substitution (if needed)
│   └── README.md                  # Config documentation
├── scripts/
│   ├── verify-config.sh           # Validation script
│   └── extract-runtime-config.sh  # Helper to extract from running container
├── README.md
├── MIGRATION.md                   # This file
└── docs/                          # Inherited from frigate/ (symlinks or copies)
    ├── HARDWARE-ACCELERATION.md
    ├── TUNING-GUIDE.md
    └── CONFIGURATION-RETROSPECTIVE.md
```

**Benefits**:
- ✅ Config file is visible and debuggable
- ✅ Version-controlled YAML
- ✅ Portable (can run with Docker Compose)
- ✅ Upstream Frigate docs directly applicable
- ✅ Nix handles infrastructure only

---

## Secret Handling Strategy

### Current Approach (Nix-Generated)

Secrets are injected during config generation:
```nix
# parts/container.nix generates:
RTSP_USER=$(cat /run/agenix/frigate-rtsp-username)
RTSP_PASS=$(cat /run/agenix/frigate-rtsp-password)
RTSP_PASS_ENCODED=$(echo "$RTSP_PASS" | python3 -c "...")
# Then embeds in YAML
```

### Target Approach (Config-First)

**Option A: Environment Variable Substitution** (Recommended)

1. **Config file uses placeholders**:
   ```yaml
   # config/config.template.yml
   cameras:
     cobra_cam_1:
       ffmpeg:
         inputs:
           - path: rtsp://${RTSP_USER}:${RTSP_PASS_ENCODED}@${CAM1_IP}:554/ch01/0
   ```

2. **Nix provides environment variables**:
   ```nix
   # index.nix
   environment = {
     RTSP_USER = builtins.readFile /run/agenix/frigate-rtsp-username;
     RTSP_PASS_ENCODED = /* URL-encoded password */;
     CAM1_IP = /* from frigate-camera-ips secret */;
   };
   ```

3. **Frigate or entrypoint script does substitution** (if Frigate supports it)

**Option B: Separate Secrets File**

1. **Main config references secret file**:
   ```yaml
   # config/config.yml
   cameras:
     cobra_cam_1:
       ffmpeg:
         inputs:
           - path: rtsp://admin:PASSWORD_PLACEHOLDER@192.168.1.101:554/ch01/0
   ```

2. **Nix generates minimal secrets.yml**:
   ```yaml
   # Generated at runtime from agenix
   rtsp:
     username: admin
     password: "il0wwlm?"
   cameras:
     cobra_cam_1:
       ip: "192.168.1.101"
   ```

3. **Entrypoint script merges** before starting Frigate

**Option C: Pre-Generated Config with Secrets**

1. **Nix generates final config** (minimal templating):
   ```nix
   # Only substitute secrets, rest is from config.yml
   environment.etc."frigate/config.yml".text =
     builtins.replaceStrings
       ["RTSP_USER" "RTSP_PASS" "CAM1_IP"]
       [rtspUser rtspPassEncoded cam1Ip]
       (builtins.readFile ./config/config.template.yml);
   ```

**Decision**: TBD based on Frigate's native support for env var substitution

---

## Module Comparison

### What Stays the Same

Both modules will share:
- ✅ Same secrets (no need to duplicate agenix entries)
- ✅ Same storage paths (`/opt/surveillance/frigate/`, `/mnt/media/`, `/mnt/hot/`)
- ✅ Same GPU passthrough logic
- ✅ Same MQTT broker
- ✅ Same cameras (IPs, credentials)
- ✅ Same documentation (can symlink or copy)

### What Changes

| Aspect | Current (frigate) | New (frigate-v2) |
|--------|-------------------|------------------|
| **Config Source** | Generated by Nix | `config/config.yml` file |
| **Debugging** | Inspect `/opt/.../config.yaml` | Edit `config/config.yml`, restart |
| **Options** | 50+ Nix options for Frigate config | 10-15 options for infrastructure only |
| **Portability** | NixOS-only | Works with Docker Compose |
| **Validation** | Build-time Nix assertions | `frigate config validate` + script |
| **Frigate Version** | 0.15.1-tensorrt | 0.16.2 (explicit pin) |
| **Detector** | ONNX (working) | ONNX + GPU (modernized config) |

---

## Migration Phases

### Phase 1: Extract & Document (This Phase)
- [x] Document extraction process
- [ ] Extract runtime config when ready
- [ ] Save as baseline
- [ ] Identify secret placeholders

### Phase 2: Build frigate-v2 Module
- [ ] Create module structure
- [ ] Create minimal `options.nix` (infrastructure only)
- [ ] Create `config/config.yml` from baseline
- [ ] Implement container definition in `index.nix`
- [ ] Handle secrets (choose strategy A/B/C)
- [ ] Create verification scripts

### Phase 3: Test frigate-v2 (Parallel to frigate)
- [ ] Import both modules (different services)
- [ ] Start frigate-v2 on different port (e.g., 5001)
- [ ] Verify frigate-v2 works identically
- [ ] Compare logs, metrics, performance
- [ ] Test GPU usage, ONNX detector, cameras

### Phase 4: Cutover
- [ ] Stop old frigate
- [ ] Switch frigate-v2 to port 5000
- [ ] Update machine config to use frigate-v2
- [ ] Remove old frigate module from imports
- [ ] Monitor for 24-48 hours

### Phase 5: Cleanup
- [ ] Archive old frigate module
- [ ] Update documentation
- [ ] Commit migration completion

---

## Rollback Plan

If frigate-v2 has issues:

1. **Immediate Rollback** (within same session):
   ```bash
   sudo systemctl stop podman-frigate-v2.service
   sudo systemctl start podman-frigate.service
   ```

2. **Nix Rollback** (change in config):
   ```nix
   # machines/server/config.nix
   imports = [
     # ../../profiles/server.nix  # Contains frigate-v2
     ../../domains/server/frigate  # Direct import of old module
   ];
   hwc.server.frigate.enable = true;  # Old module
   ```

3. **Git Rollback**:
   ```bash
   git revert <migration-commit>
   sudo nixos-rebuild switch
   ```

**Safety Net**: Old module stays in repo until frigate-v2 is proven stable (30+ days)

---

## Success Criteria

Frigate-v2 is considered successful when:

- [ ] All 3 cameras online and recording
- [ ] ONNX detector working without dtype errors
- [ ] GPU acceleration confirmed (nvidia-smi shows usage)
- [ ] No regressions in:
  - [ ] Detection accuracy
  - [ ] Recording retention
  - [ ] MQTT events
  - [ ] Web UI accessibility
  - [ ] Timeline/clips functionality
- [ ] Config file is:
  - [ ] Human-readable
  - [ ] Version-controlled
  - [ ] Debuggable (can edit directly)
  - [ ] Portable (could run on Docker)
- [ ] Documentation updated
- [ ] No errors in logs for 48+ hours

---

## Next Steps

1. **Read and approve** this migration plan
2. **Decide on secret handling strategy** (A, B, or C)
3. **Execute Phase 1** (extract runtime config) when ready
4. **Build frigate-v2 module** following Charter v7.0 Section 19
5. **Test in parallel** with current frigate
6. **Cutover** when confident

---

**Created**: 2025-11-23
**Status**: Planning phase
**Charter Reference**: Section 19 - Complex Service Configuration Pattern
**Related**: CONFIGURATION-RETROSPECTIVE.md
