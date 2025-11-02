# GPU Acceleration Guide - NVIDIA Quadro P1000

**Last Updated**: 2025-11-01
**Hardware**: NVIDIA Quadro P1000 (Pascal architecture, 4GB VRAM)
**Driver**: NVIDIA Legacy 470.256.02
**CUDA Version**: 11.4

---

## Table of Contents

1. [Hardware Overview](#hardware-overview)
2. [Driver Configuration](#driver-configuration)
3. [Services Using GPU](#services-using-gpu)
4. [Services That Cannot Use GPU](#services-that-cannot-use-gpu)
5. [GPU Configuration Patterns](#gpu-configuration-patterns)
6. [Troubleshooting](#troubleshooting)
7. [Monitoring](#monitoring)
8. [Adding GPU to New Services](#adding-gpu-to-new-services)

---

## Hardware Overview

**GPU Details**:
- **Model**: NVIDIA Quadro P1000
- **PCI ID**: 10de:1cb1
- **PCI Address**: 0000:01:00.0
- **Architecture**: Pascal (Compute Capability 6.1)
- **VRAM**: 4GB GDDR5
- **CUDA Cores**: 640
- **Max Power**: ~47W

**Driver Requirements**:
- P1000 is **legacy hardware** (released 2017)
- Requires **NVIDIA Legacy 470 driver** (not supported by modern 580+ drivers)
- Driver configured machine-specifically in `machines/server/config.nix`

**Key Capabilities**:
- ✅ CUDA 11.4 support
- ✅ Video encoding/decoding (NVENC/NVDEC)
- ✅ Machine learning inference (PyTorch, TensorFlow)
- ✅ Image processing (OpenCV with CUDA)
- ❌ Ray tracing (not supported on Pascal)
- ❌ Tensor cores (not available on P1000)

---

## Driver Configuration

**Location**: `/home/eric/.nixos/machines/server/config.nix`

```nix
# Machine-specific GPU override for Quadro P1000 (legacy driver required)
hwc.infrastructure.hardware.gpu = {
  enable = lib.mkForce true;
  type = "nvidia";
  nvidia = {
    driver = "stable";  # Use stable as base, override package below
    containerRuntime = true;
    enableMonitoring = true;
  };
};

# P1000 requires legacy driver - override the NVIDIA package and disable modern features
hardware.nvidia = {
  package = lib.mkForce config.boot.kernelPackages.nvidiaPackages.legacy_470;
  open = lib.mkForce false;  # Legacy driver doesn't support open-source modules
  gsp.enable = lib.mkForce false;  # Legacy driver doesn't support GSP firmware
};
```

**License Acceptance** (in `flake.nix`):
```nix
pkgs = import nixpkgs {
  inherit system;
  config = {
    allowUnfree = true;
    nvidia.acceptLicense = true;  # Required for legacy driver
  };
};
```

**Verification Commands**:
```bash
# Check driver version (must use legacy driver nvidia-smi)
sudo /nix/store/*-nvidia-x11-470.256.02-*/bin/nvidia-smi

# Check loaded kernel modules
lsmod | grep nvidia

# Check GPU PCI device
lspci | grep -i nvidia
```

---

## Services Using GPU

### 1. Immich Machine Learning ✅ CONFIGURED

**Purpose**: Photo/video analysis, face detection, object recognition, CLIP embeddings

**Configuration**: `/home/eric/.nixos/domains/server/immich/index.nix` + `/home/eric/.nixos/machines/server/config.nix`

```nix
systemd.services.immich-machine-learning = {
  serviceConfig = {
    # GPU device access
    DeviceAllow = [
      "/dev/nvidia0 rw"
      "/dev/nvidiactl rw"
      "/dev/nvidia-modeset rw"
      "/dev/nvidia-uvm rw"
      "/dev/nvidia-uvm-tools rw"
      "/dev/dri/card0 rw"
      "/dev/dri/renderD128 rw"
    ];
    SupplementaryGroups = [ "video" "render" ];
  };
  environment = {
    # NVIDIA environment variables
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

    # PyTorch CUDA configuration for Pascal (6.1)
    CUDA_VISIBLE_DEVICES = "0";
    TORCH_CUDA_ARCH_LIST = "6.1";

    # Cache directories
    MPLCONFIGDIR = "/var/cache/immich-machine-learning";
    TRANSFORMERS_CACHE = "/var/cache/immich-machine-learning";
  };
};
```

**Also configured for `immich-server`** (machines/server/config.nix): Same DeviceAllow + SupplementaryGroups for photo/video processing

**GPU Usage Pattern**:
- Idle when no ML jobs running
- Spikes to 50-100% during face detection, smart search indexing
- Memory usage: 500MB-2GB depending on model

**Monitoring**:
```bash
# Watch GPU usage during ML processing
sudo watch -n 1 /nix/store/*-nvidia-x11-470.256.02-*/bin/nvidia-smi

# Check service logs
sudo journalctl -u immich-machine-learning -f
```

---

### 2. Jellyfin Media Server ⚠️ TODO - NEEDS GPU CONFIGURATION

**Purpose**: Video transcoding, hardware-accelerated playback

**Status**: ⚠️ **NOT YET CONFIGURED FOR GPU**

**Current State**: Native Jellyfin service without GPU access

**Location to Add Configuration**: `/home/eric/.nixos/domains/server/jellyfin/index.nix`

**Required Configuration**:
```nix
# Add to domains/server/jellyfin/index.nix
systemd.services.jellyfin = {
  serviceConfig = {
    DeviceAllow = [
      "/dev/nvidia0 rw"
      "/dev/nvidiactl rw"
      "/dev/nvidia-modeset rw"
      "/dev/nvidia-uvm rw"
      "/dev/nvidia-uvm-tools rw"
      "/dev/dri/renderD128 rw"
    ];
    SupplementaryGroups = [ "video" "render" ];
  };
  environment = {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
  };
};
```

**Jellyfin UI Configuration** (after systemd config):
1. Dashboard → Playback → Transcoding
2. Hardware acceleration: **NVIDIA NVENC**
3. Enable hardware decoding for: H264, HEVC, VP9
4. Enable hardware encoding for: H264, HEVC

**Expected Performance**:
- 4K HEVC → 1080p H264: ~120-150 FPS (vs ~30 FPS CPU)
- Multiple concurrent transcodes supported

**Action Required**: Add GPU configuration to Jellyfin module and test transcoding

---

### 3. Ollama (AI/LLM Service) - DISABLED

**Purpose**: Local LLM inference

**Status**: Disabled (`enable = false` in server profile)

**Configuration** (when enabled):
```nix
services.ollama = {
  enable = false;  # Currently disabled
  acceleration = "cuda";  # CUDA acceleration for P1000
  environmentVariables = {
    CUDA_VISIBLE_DEVICES = "0";
  };
};
```

**Notes**:
- P1000's 4GB VRAM limits model size (max ~7B parameters with quantization)
- Suitable for: llama3:8b-q4, codellama:7b-q4
- Not suitable for: 13B+ models, high-precision models

---

## Services That Cannot Use GPU

### Why Some Services Don't Benefit

| Service | Reason Cannot Use GPU | Notes |
|---------|----------------------|-------|
| **Navidrome** | Audio streaming - no GPU-accelerated audio codecs | CPU handles MP3/FLAC/AAC efficiently |
| **Sonarr/Radarr/Lidarr** | Metadata management, no compute workload | Database + API calls only |
| **Prowlarr** | Indexer aggregation, network I/O bound | No computational workload |
| **SABnzbd** | Download client, I/O + decompression | CPU decompression is sufficient |
| **PostgreSQL** | Database - no GPU support in standard PostgreSQL | Would need pgGPU extension (not worth overhead) |
| **Redis** | In-memory cache, optimized for CPU | GPU overhead would slow it down |
| **Caddy** | Reverse proxy, network I/O | TLS handled efficiently by CPU |
| **CouchDB** | Document database | No GPU support |
| **Tailscale** | VPN mesh network | Network encryption on CPU is efficient |

---

## GPU Configuration Patterns

### Pattern 1: Systemd Service Override (Recommended)

**Use for**: Native NixOS services (Immich, Jellyfin, etc.)

```nix
systemd.services.<service-name> = {
  serviceConfig = {
    # Grant access to GPU devices
    DeviceAllow = [
      "/dev/nvidia0 rw"
      "/dev/nvidiactl rw"
      "/dev/nvidia-modeset rw"
      "/dev/nvidia-uvm rw"
      "/dev/nvidia-uvm-tools rw"
      "/dev/dri/card0 rw"           # DRM device
      "/dev/dri/renderD128 rw"      # Render node
    ];

    # Add user to GPU access groups
    SupplementaryGroups = [ "video" "render" ];
  };

  environment = {
    # Make GPU visible to application
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";

    # CRITICAL: Library path for CUDA libraries
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

    # Specify GPU to use (0 = first GPU)
    CUDA_VISIBLE_DEVICES = "0";

    # PyTorch: Specify CUDA architecture (6.1 for Pascal P1000)
    TORCH_CUDA_ARCH_LIST = "6.1";
  };
};
```

### Pattern 2: Container GPU Access (If Needed)

**Use for**: Podman/Docker containers

Available via `hwc.infrastructure.hardware.gpu.containerOptions`:

```nix
virtualisation.oci-containers.containers.<container> = {
  extraOptions = config.hwc.infrastructure.hardware.gpu.containerOptions;
  # Automatically adds: --device=/dev/nvidia0, --device=/dev/nvidiactl, etc.

  environment = config.hwc.infrastructure.hardware.gpu.containerEnvironment;
  # Automatically sets: NVIDIA_VISIBLE_DEVICES=all, NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
};
```

### Pattern 3: Read-Only Library Access

**Use for**: Services that only need to read GPU libraries (no compute)

```nix
systemd.services.<service> = {
  serviceConfig = {
    ReadOnlyPaths = [
      "/run/opengl-driver"
      "/run/opengl-driver-32"
    ];
  };
};
```

---

## Critical Configuration Elements

### Must-Have for GPU Access

1. **DeviceAllow**: Grants systemd service permission to access GPU device files
2. **SupplementaryGroups**: Adds service user to `video` and `render` groups
3. **LD_LIBRARY_PATH**: Points to NVIDIA CUDA runtime libraries in `/run/opengl-driver`
4. **NVIDIA_VISIBLE_DEVICES**: Makes GPU visible to CUDA runtime
5. **CUDA_VISIBLE_DEVICES**: Tells application which GPU to use (0-indexed)

### Application-Specific Variables

| Variable | Purpose | Value for P1000 |
|----------|---------|-----------------|
| `TORCH_CUDA_ARCH_LIST` | PyTorch CUDA architecture target | `6.1` (Pascal) |
| `CUDA_VISIBLE_DEVICES` | Which GPU(s) to use | `0` |
| `NVIDIA_DRIVER_CAPABILITIES` | What GPU features to enable | `compute,video,utility` |

---

## Troubleshooting

### GPU Not Detected by Application

**Symptoms**: Application logs show "CUDA not available" or "No GPU found"

**Debug Steps**:

1. **Verify driver loaded**:
   ```bash
   lsmod | grep nvidia
   # Should show: nvidia, nvidia_drm, nvidia_modeset, nvidia_uvm
   ```

2. **Check device files exist**:
   ```bash
   ls -la /dev/nvidia*
   # Should show: nvidia0, nvidiactl, nvidia-modeset, nvidia-uvm, nvidia-uvm-tools
   ```

3. **Verify service has DeviceAllow**:
   ```bash
   sudo systemctl show <service-name> | grep DeviceAllow
   # Should show all /dev/nvidia* devices
   ```

4. **Check LD_LIBRARY_PATH in running process**:
   ```bash
   sudo cat /proc/$(pgrep <service>)/environ | tr '\0' '\n' | grep LD_LIBRARY
   # Should include /run/opengl-driver paths
   ```

5. **Test CUDA from service context**:
   ```bash
   # Run as service user with same environment
   sudo -u <service-user> env LD_LIBRARY_PATH=/run/opengl-driver/lib python3 -c "import torch; print(torch.cuda.is_available())"
   ```

### Driver Version Mismatch

**Symptoms**: `nvidia-smi` shows "Driver/library version mismatch"

**Cause**: System PATH has newer nvidia-smi binary (580.x) but kernel has legacy driver (470.x)

**Solution**: Use nvidia-smi from nix store:
```bash
/nix/store/*-nvidia-x11-470.256.02-*/bin/nvidia-smi
```

### Legacy Driver Build Failures

**Error**: "This version of NVIDIA driver does not provide a GSP firmware"

**Solution**: Disable GSP in machine config:
```nix
hardware.nvidia.gsp.enable = lib.mkForce false;
```

**Error**: "Use of NVIDIA Software requires license acceptance"

**Solution**: Add to `flake.nix` pkgs config:
```nix
config.nvidia.acceptLicense = true;
```

---

## Monitoring

### Real-Time GPU Usage

```bash
# Basic monitoring (refresh every 1 second)
sudo watch -n 1 /nix/store/*-nvidia-x11-470.256.02-*/bin/nvidia-smi

# Detailed monitoring with process list
sudo watch -n 1 '/nix/store/*-nvidia-x11-470.256.02-*/bin/nvidia-smi dmon -s pucvmet'
```

### GPU Metrics to Monitor

| Metric | Command | Healthy Range |
|--------|---------|---------------|
| **Temperature** | `nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader` | 35-70°C |
| **Power Draw** | `nvidia-smi --query-gpu=power.draw --format=csv,noheader` | 5-45W |
| **GPU Utilization** | `nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader` | 0-100% (varies by workload) |
| **Memory Used** | `nvidia-smi --query-gpu=memory.used --format=csv,noheader` | 0-4096 MiB |
| **Memory Free** | `nvidia-smi --query-gpu=memory.free --format=csv,noheader` | Should not hit 0 |

### Service-Specific Monitoring

**Immich ML**:
```bash
# Check if GPU is being used during ML jobs
sudo journalctl -u immich-machine-learning -f | grep -i cuda

# Watch GPU processes during photo processing
sudo watch 'nvidia-smi --query-compute-apps=pid,name,used_memory --format=csv'
```

**Jellyfin** (when GPU enabled):
```bash
# Check transcoding logs
sudo journalctl -u jellyfin -f | grep -i nvenc

# Monitor video encode/decode usage
nvidia-smi dmon -s u
```

---

## Adding GPU to New Services

### Checklist for Enabling GPU

- [ ] Service supports CUDA/NVENC/NVDEC
- [ ] Service benefits from GPU acceleration (verify benchmark exists)
- [ ] Add `DeviceAllow` for all `/dev/nvidia*` and `/dev/dri/*` devices
- [ ] Add `SupplementaryGroups = [ "video" "render" ]`
- [ ] Set `LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib"`
- [ ] Set `NVIDIA_VISIBLE_DEVICES = "all"`
- [ ] Set `CUDA_VISIBLE_DEVICES = "0"`
- [ ] Set architecture-specific variables (e.g., `TORCH_CUDA_ARCH_LIST = "6.1"`)
- [ ] Test GPU detection: check service logs for CUDA initialization
- [ ] Verify GPU usage: run workload and monitor with `nvidia-smi`
- [ ] Document configuration in this file

### Example Template

```nix
systemd.services.<new-service> = {
  serviceConfig = {
    DeviceAllow = [
      "/dev/nvidia0 rw"
      "/dev/nvidiactl rw"
      "/dev/nvidia-modeset rw"
      "/dev/nvidia-uvm rw"
      "/dev/nvidia-uvm-tools rw"
      "/dev/dri/card0 rw"
      "/dev/dri/renderD128 rw"
    ];
    SupplementaryGroups = [ "video" "render" ];
  };
  environment = {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
    CUDA_VISIBLE_DEVICES = "0";
    # Add service-specific variables below
  };
};
```

---

## Performance Expectations

### Immich ML (Photo Analysis)

| Task | CPU (i7-4770) | GPU (P1000) | Speedup |
|------|---------------|-------------|---------|
| Face detection (per photo) | ~2-3s | ~0.5-1s | 2-3x |
| CLIP embeddings (per photo) | ~1-2s | ~0.3-0.5s | 3-4x |
| Object detection (per photo) | ~1.5s | ~0.4s | 3-4x |

### Jellyfin Transcoding (Expected)

| Source → Target | CPU FPS | GPU FPS | Speedup |
|-----------------|---------|---------|---------|
| 4K HEVC → 1080p H264 | ~25-30 | ~120-150 | 4-5x |
| 1080p H264 → 720p H264 | ~60-80 | ~200-250 | 3x |
| Concurrent streams | 1-2 | 4-6 | 3x |

---

## Maintenance Tasks

### Monthly
- [ ] Check GPU temperature trends (should stay 35-65°C under load)
- [ ] Verify driver version matches expected (470.256.02)
- [ ] Review GPU utilization - are GPU-enabled services actually using it?

### After NixOS/Flake Updates
- [ ] Verify legacy driver still builds (`sudo nixos-rebuild build --flake .#hwc-server`)
- [ ] Check for driver version changes in nixpkgs
- [ ] Test GPU functionality with `nvidia-smi` after rebuild

### When Adding New GPU-Accelerated Services
- [ ] Document configuration in this file
- [ ] Add monitoring commands specific to the service
- [ ] Benchmark CPU vs GPU performance
- [ ] Update "Services Using GPU" section above

---

## References

- **NVIDIA P1000 Specs**: https://www.nvidia.com/en-us/design-visualization/quadro/pascal/
- **CUDA Compute Capability 6.1**: https://developer.nvidia.com/cuda-gpus
- **Legacy Driver 470 Support**: https://www.nvidia.com/Download/driverResults.aspx/218826/
- **NixOS NVIDIA Options**: https://search.nixos.org/options?query=nvidia
- **HWC GPU Infrastructure**: `/home/eric/.nixos/domains/infrastructure/hardware/`
- **HWC Charter v6.0**: `/home/eric/.nixos/charter.md`

---

**Document maintained by**: HWC Infrastructure Domain
**Related Charter Section**: Infrastructure → Hardware → GPU (v6.0)
**Last Audit**: 2025-11-01
