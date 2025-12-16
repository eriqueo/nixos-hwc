# NVIDIA GPU Reference - hwc-server

**Hardware**: NVIDIA Quadro P1000 (Pascal, 4GB VRAM)
**Driver**: 580.95.05 (stable)
**CUDA**: 13.0
**Last Updated**: 2025-11-24

---

## Table of Contents

1. [Hardware Specifications](#hardware-specifications)
2. [System Configuration](#system-configuration)
3. [GPU Acceleration Methods](#gpu-acceleration-methods)
4. [Working Examples](#working-examples)
5. [Common Mistakes](#common-mistakes)
6. [Verification & Testing](#verification--testing)
7. [Troubleshooting](#troubleshooting)
8. [P1000-Specific Optimizations](#p1000-specific-optimizations)

---

## Hardware Specifications

### NVIDIA Quadro P1000

| Specification | Value |
|---------------|-------|
| **Architecture** | Pascal (GP107) |
| **CUDA Cores** | 640 |
| **VRAM** | 4GB GDDR5 |
| **Memory Bandwidth** | 80 GB/s |
| **Compute Capability** | 6.1 |
| **TDP** | 47W |
| **NVENC/NVDEC** | Yes (H.264/H.265) |
| **Max Concurrent Streams** | 2-3 (VRAM limited) |

### Driver Information

```bash
# Current Configuration
Driver Version: 580.95.05
CUDA Version: 13.0
Compute Capability: 6.1
```

**Location**: `machines/server/config.nix:166-181`

```nix
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";
  nvidia = {
    driver = "stable";           # 580.95.05
    containerRuntime = true;     # nvidia-container-toolkit
    enableMonitoring = true;     # gpu-monitor service
  };
};
```

### Capabilities

✅ **Supported:**
- CUDA compute (13.0)
- NVENC/NVDEC hardware video encoding/decoding
- H.264/H.265 encode and decode
- OpenGL, Vulkan, OpenCL
- ONNX Runtime with CUDAExecutionProvider (driver >= 545 required)

❌ **Not Supported:**
- TensorRT on amd64 (ARM64 only for Pascal)
- Open-source kernel module (closed-source required)
- GSP firmware (too old architecture)
- RTX features (tensor cores, DLSS, ray tracing)
- FP16 precision (use FP32)

### Limitations

1. **4GB VRAM**: Limits model sizes and concurrent streams
2. **Pascal Architecture**: Last generation before legacy status (post-580.x drivers)
3. **Closed-Source Only**: `hardware.nvidia.open = false` required
4. **No GSP**: `hardware.nvidia.gsp.enable = false` required

---

## System Configuration

### Domain Module: `domains/infrastructure/hardware/gpu/`

**Structure:**
```
domains/infrastructure/hardware/
├── index.nix                   # Aggregator
├── options.nix                 # API definitions (hwc.infrastructure.hardware.gpu.*)
└── parts/
    └── gpu.nix                 # Implementation (~342 lines)
```

### Configuration Options

**Namespace**: `hwc.infrastructure.hardware.gpu.*`

```nix
{
  # Enable GPU support
  hwc.infrastructure.hardware.gpu = {
    enable = true;                           # Master toggle
    type = "nvidia";                         # "nvidia" | "intel" | "amd" | "none"

    # Derived (read-only)
    accel = "cuda";                          # Auto-set based on type

    # NVIDIA-specific options
    nvidia = {
      enable = true;                         # Auto-enabled when type = nvidia
      driver = "stable";                     # "stable" | "beta" | "production"
      containerRuntime = true;               # Enable nvidia-container-toolkit
      enableMonitoring = true;               # Enable gpu-monitor systemd service

      # Laptop hybrid graphics (not applicable to server)
      prime = {
        enable = false;
        nvidiaBusId = "PCI:1:0:0";
        intelBusId = "PCI:0:2:0";
      };
    };

    # Laptop power management (not applicable to server)
    powerManagement = {
      enable = false;
      smartToggle = false;                   # gpu-toggle, gpu-launch scripts
      toggleNotifications = false;
    };

    # Auto-generated container helpers
    containerOptions = [
      "--device=/dev/nvidia0:/dev/nvidia0:rwm"
      "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
      # ... all device flags
    ];

    containerEnvironment = {
      NVIDIA_VISIBLE_DEVICES = "all";
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    };
  };
}
```

### What This Configures

1. **Kernel Modules:**
   - `nvidia`, `nvidia_modeset`, `nvidia_uvm`, `nvidia_drm`
   - Blacklists: `nouveau`
   - Parameters: `nvidia-drm.modeset=1`

2. **Device Permissions (udev):**
   ```bash
   /dev/nvidia0           MODE="0666"
   /dev/nvidiactl         MODE="0666"
   /dev/nvidia-modeset    MODE="0666"
   /dev/nvidia-uvm        MODE="0666"
   ```

3. **Environment Variables:**
   ```bash
   CUDA_CACHE_PATH=/var/cache/hwc/cuda
   LIBVA_DRIVER_NAME=nvidia
   VDPAU_DRIVER=nvidia
   ```

4. **Container Runtime:**
   - `hardware.nvidia-container-toolkit.enable = true`
   - CDI (Container Device Interface) support for Podman
   - Automatic GPU device passthrough

5. **Monitoring Service (optional):**
   - `systemd.services.gpu-monitor`
   - Logs nvidia-smi stats every 60s to `/var/log/hwc/gpu/gpu-usage.log`

### Device Paths

```bash
# GPU Devices
/dev/nvidia0                    # GPU device 0
/dev/nvidiactl                  # Control device
/dev/nvidia-modeset             # Mode setting device
/dev/nvidia-uvm                 # Unified Virtual Memory
/dev/nvidia-uvm-tools           # UVM tools

# DRI Devices (for OpenGL/Vulkan)
/dev/dri/card0                  # DRM device
/dev/dri/renderD128             # Render node

# Driver Libraries (NixOS-specific paths)
/run/opengl-driver/lib/         # 64-bit NVIDIA libraries
/run/opengl-driver-32/lib/      # 32-bit NVIDIA libraries

# Cache & Logs
/var/cache/hwc/cuda/            # CUDA compilation cache
/var/log/hwc/gpu/               # GPU monitoring logs
```

---

## GPU Acceleration Methods

There are **3 primary methods** to enable GPU acceleration in different contexts. Choose based on your service type.

### Method 1: Podman Containers (CDI - Preferred) ⭐

**When to Use**: New container services, modern Podman setup

**Configuration:**
```nix
{
  # In your container service definition
  virtualisation.oci-containers.containers.myservice = {
    image = "myimage:latest";

    # GPU passthrough (CDI)
    extraOptions = [
      "--device=nvidia.com/gpu=0"          # Pass GPU 0
      # OR
      "--device=nvidia.com/gpu=all"        # Pass all GPUs
    ];

    # GPU environment variables
    environment = {
      NVIDIA_VISIBLE_DEVICES = "0";        # or "all"
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      CUDA_VISIBLE_DEVICES = "0";          # Optional: CUDA-specific

      # NixOS-specific: Driver library paths
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
    };
  };
}
```

**Driver Capabilities Explained:**
- `compute`: CUDA compute operations
- `video`: NVENC/NVDEC video encode/decode
- `utility`: nvidia-smi and management utilities
- `graphics`: OpenGL/Vulkan rendering
- `display`: X11 display support

**Pros:**
- ✅ Clean, modern approach
- ✅ Automatic device management
- ✅ Works with nvidia-container-toolkit
- ✅ Less verbose configuration

**Cons:**
- ⚠️ Requires nvidia-container-toolkit configured
- ⚠️ CDI specs must be present in `/var/run/cdi/`

### Method 2: Podman Containers (Manual Device Passthrough)

**When to Use**: Compatibility with older configs, CDI issues

**Configuration:**
```nix
{
  virtualisation.oci-containers.containers.myservice = {
    image = "myimage:latest";

    # Manual device passthrough
    extraOptions = [
      "--device=/dev/nvidia0:/dev/nvidia0:rwm"
      "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
      "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
      "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
      "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
      "--device=/dev/dri:/dev/dri:rwm"      # For OpenGL/Vulkan
    ];

    # Same environment variables as Method 1
    environment = {
      NVIDIA_VISIBLE_DEVICES = "all";
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
    };
  };
}
```

**Pros:**
- ✅ Works without CDI
- ✅ More explicit control
- ✅ Compatible with all Podman versions

**Cons:**
- ⚠️ Verbose configuration
- ⚠️ Must manually specify all devices
- ⚠️ Harder to maintain

### Method 3: Native systemd Services

**When to Use**: Non-containerized services (Jellyfin, Immich, etc.)

**Configuration:**
```nix
{
  systemd.services.myservice = {
    description = "My GPU Service";

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

      # Add to video/render groups
      SupplementaryGroups = [ "video" "render" ];

      # Prevent device access restrictions
      PrivateDevices = false;
    };

    # GPU environment variables
    environment = {
      NVIDIA_VISIBLE_DEVICES = "0";
      NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
      CUDA_VISIBLE_DEVICES = "0";
      LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
    };
  };
}
```

**Pros:**
- ✅ No container overhead
- ✅ Direct device access
- ✅ Better performance (no virtualization)

**Cons:**
- ⚠️ More systemd configuration required
- ⚠️ Must manage permissions manually

---

## Working Examples

These are **production-tested** configurations from hwc-server.

### Example 1: Frigate NVR (ONNX + NVDEC) ✅ WORKING

**Location**: `domains/server/frigate/`

**Purpose**: AI object detection + hardware video decoding

**NixOS Configuration:**
```nix
{
  hwc.server.frigate = {
    enable = true;
    gpu = {
      enable = true;
      device = 0;
    };
  };
}
```

**Container Setup (Generated):**
```nix
virtualisation.oci-containers.containers.frigate = {
  image = "ghcr.io/blakeblackshear/frigate:0.16.2-tensorrt";

  extraOptions = [
    "--device=nvidia.com/gpu=0"
  ];

  environment = {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
    CUDA_VISIBLE_DEVICES = "0";
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
  };
};
```

**Frigate Config (`config/config.yml`):**
```yaml
detectors:
  onnx:
    type: onnx
    device: "0"                          # GPU 0 (must be string!)
    num_threads: 3
    execution_providers:
      - cuda
      - cpu

model:
  path: /config/models/yolov9-s-320.onnx
  model_type: yolo-generic
  input_tensor: nchw
  input_pixel_format: bgr
  input_dtype: float                     # CRITICAL: Use float, not uint8
  width: 320
  height: 320

ffmpeg:
  hwaccel_args:
    - -hwaccel
    - nvdec                              # NVIDIA hardware decoder
    - -hwaccel_device
    - '0'
    - -hwaccel_output_format
    - yuv420p

cameras:
  camera_name:
    ffmpeg:
      inputs:
        - path: rtsp://...
          roles:
            - detect
    detect:
      enabled: true
      fps: 1                             # 1 fps for detection
```

**Performance:**
| Metric | CPU | GPU (CUDA) | Speedup |
|--------|-----|------------|---------|
| Detection inference | ~54ms | ~10ms | 5.4x |
| Concurrent streams | 1-2 | 3-4 | 2x |

**How to Verify:**
```bash
# Check Frigate logs for GPU usage
docker logs frigate 2>&1 | grep -i "cuda\|gpu\|onnx"

# Should see:
# "Detector onnx: CUDA available"
# "Using CUDAExecutionProvider"

# Monitor GPU during detection
watch -n 1 nvidia-smi
# Should show frigate process using GPU
```

---

### Example 2: Tdarr (NVENC Video Transcoding)

**Location**: `domains/server/containers/tdarr/`

**Purpose**: Hardware-accelerated video transcoding (H.264/H.265)

**NixOS Configuration:**
```nix
{
  hwc.server.containers.tdarr = {
    enable = true;
    gpu.enable = true;
    workers = 1;                         # Adjust based on workload
  };
}
```

**Container Setup (Generated):**
```nix
virtualisation.oci-containers.containers.tdarr = {
  image = "ghcr.io/haveagitgat/tdarr:2.26.01";

  extraOptions = [
    "--device=nvidia.com/gpu=0"
  ];

  environment = {
    NVIDIA_VISIBLE_DEVICES = "all";
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
  };
};
```

**Tdarr Flow Configuration:**

**❌ WRONG (CPU Encoding):**
```javascript
// Don't use CPU encoders!
{
  "codec": "hevc",
  "encoder": "libx265",              // CPU-based (SLOW!)
  "preset": "fast",
  "crf": 25
}
```

**✅ RIGHT (GPU Encoding):**
```javascript
// Use NVENC hardware encoder
{
  "codec": "hevc",
  "encoder": "hevc_nvenc",           // GPU-based (FAST!)
  "preset": "p4",                    // NVENC preset (p1-p7)
  "rc": "vbr",                       // Rate control: vbr or cq
  "cq": 25,                          // Quality (lower = better)
  "spatial_aq": 1,                   // Spatial AQ
  "b_ref_mode": "middle"             // B-frame reference mode
}
```

**NVENC Presets:**
- `p1`: Fastest, lowest quality
- `p4`: Balanced (recommended)
- `p7`: Slowest, highest quality

**Performance Comparison:**
| Input | CPU (libx265) | GPU (hevc_nvenc) | Speedup |
|-------|---------------|------------------|---------|
| 1080p H.264 → H.265 | ~180s | ~25s | 7.2x |
| 4K H.264 → H.265 | ~600s | ~90s | 6.7x |

**How to Verify:**
```bash
# Check Tdarr is using GPU
docker logs tdarr 2>&1 | grep -i "nvenc\|nvdec"

# Monitor during transcode
nvidia-smi dmon -s u
# Should show tdarr-ffmpeg using GPU

# Check transcode command in Tdarr UI
# Should see: -c:v hevc_nvenc (not libx265)
```

---

## Common Mistakes

### ❌ Mistake 1: Using CPU Encoders Instead of NVENC

**Wrong:**
```bash
# Tdarr/FFmpeg using CPU encoder
ffmpeg -i input.mp4 -c:v libx265 -preset fast output.mp4
```

**Right:**
```bash
# Use NVENC hardware encoder
ffmpeg -i input.mp4 -c:v hevc_nvenc -preset p4 -rc vbr -cq 25 output.mp4
```

**How to Detect:**
```bash
# CPU encoder = high CPU usage, low GPU usage
# GPU encoder = low CPU usage, high GPU usage
htop         # Check CPU usage
nvidia-smi   # Check GPU usage
```

---

### ❌ Mistake 2: Missing LD_LIBRARY_PATH in Containers

**Wrong:**
```nix
environment = {
  NVIDIA_VISIBLE_DEVICES = "0";
  # Missing LD_LIBRARY_PATH!
};
```

**Right:**
```nix
environment = {
  NVIDIA_VISIBLE_DEVICES = "0";
  NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
  LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";  # REQUIRED on NixOS!
};
```

**Why**: NixOS stores driver libraries in non-standard paths. Without this, CUDA/NVENC won't work.

---

### ❌ Mistake 3: Not Verifying GPU is Actually Being Used

**Wrong Assumption:**
> "I configured GPU, so it must be working!"

**Right Approach:**
```bash
# Always verify with nvidia-smi
nvidia-smi pmon -s u -c 10

# Should show your process using GPU
# If not, configuration is wrong!
```

---

## Verification & Testing

### Pre-Flight Checks

**1. Verify Driver is Loaded:**
```bash
# Check nvidia driver
nvidia-smi

# Should show GPU info with driver version 580.95.05

# Check driver version
cat /proc/driver/nvidia/version
```

**2. Verify Device Permissions:**
```bash
# Check device files exist and are accessible
ls -la /dev/nvidia*

# All should have MODE 0666 (rw-rw-rw-)
```

**3. Verify CUDA is Available:**
```bash
# Check CUDA libraries
ls /run/opengl-driver/lib/libcuda*

# Should show libcuda.so, libcuda.so.1, libcuda.so.580.95.05
```

---

### Container GPU Test

**Quick Test:**
```bash
# Test GPU access in container
podman run --rm \
  --device nvidia.com/gpu=0 \
  -e NVIDIA_VISIBLE_DEVICES=0 \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  -e LD_LIBRARY_PATH=/run/opengl-driver/lib \
  nvidia/cuda:12.0-base \
  nvidia-smi

# Should show nvidia-smi output with GPU info
```

---

## Troubleshooting

### Issue 1: nvidia-smi Shows "No devices found"

**Solutions:**

**Step 1: Check driver loading:**
```bash
lsmod | grep nvidia

# Should show: nvidia_uvm, nvidia_drm, nvidia_modeset, nvidia
```

**Step 2: Rebuild NixOS:**
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

---

### Issue 2: Container Can't Access GPU

**Solutions:**

**Step 1: Test manual device passthrough:**
```bash
podman run --rm \
  --device /dev/nvidia0:/dev/nvidia0:rwm \
  --device /dev/nvidiactl:/dev/nvidiactl:rwm \
  -e LD_LIBRARY_PATH=/run/opengl-driver/lib \
  nvidia/cuda:12.0-base \
  nvidia-smi
```

---

### Issue 3: Poor GPU Performance / High CPU Usage

**Solutions:**

**Step 1: Verify GPU is actually being used:**
```bash
# During workload
nvidia-smi dmon -s u

# GPU util should be > 50% for compute tasks
```

**Step 2: Check application configuration:**
- FFmpeg/Tdarr: Should use `hevc_nvenc` (not `libx265`)
- ONNX: `execution_providers: [cuda, cpu]` (cuda FIRST)

---

## P1000-Specific Optimizations

### VRAM Management (4GB Limit)

**VRAM Budget by Workload:**

| Service | Typical VRAM | Max Concurrent |
|---------|--------------|----------------|
| Frigate (3 cameras, 1fps) | 1.5GB | 2 instances |
| Tdarr (1080p transcode) | 1.0GB | 3 workers |
| Ollama (3B model) | 2.0GB | 1 model |
| Ollama (7B model) | 4.1GB | **OOM - don't use** |
| Immich ML (CLIP) | 2.5GB | 1 instance |

**Recommended Models:**

**Ollama (4GB VRAM):**
- ✅ `qwen2.5-coder:3b` (1.9GB)
- ✅ `phi3.5:3.8b` (2.3GB)
- ✅ `llama3.2:3b` (2.0GB)
- ❌ `mistral:7b` (4.1GB - OOM risk)

**Frigate:**
- ✅ `yolov9-s-320` (1.2GB) - Current choice
- ✅ `yolov8n-320` (0.8GB) - If VRAM tight

---

## Quick Reference

### Essential Commands

```bash
# Check GPU status
nvidia-smi

# Monitor GPU usage (live)
watch -n 1 nvidia-smi

# Monitor GPU utilization
nvidia-smi dmon -s u

# Monitor VRAM usage
nvidia-smi --query-gpu=memory.used,memory.total --format=csv -l 1

# Monitor processes using GPU
nvidia-smi pmon -s u -o T

# Test container GPU access
podman run --rm --device nvidia.com/gpu=0 \
  -e NVIDIA_VISIBLE_DEVICES=0 \
  -e LD_LIBRARY_PATH=/run/opengl-driver/lib \
  nvidia/cuda:12.0-base nvidia-smi
```

### Configuration Snippets

**Container (CDI):**
```nix
extraOptions = [ "--device=nvidia.com/gpu=0" ];
environment = {
  NVIDIA_VISIBLE_DEVICES = "0";
  NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
  LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
};
```

**systemd Service:**
```nix
systemd.services.myservice = {
  serviceConfig = {
    DeviceAllow = [ "/dev/nvidia0 rw" "/dev/nvidiactl rw" ];
    SupplementaryGroups = [ "video" "render" ];
  };
  environment = {
    NVIDIA_VISIBLE_DEVICES = "0";
    LD_LIBRARY_PATH = "/run/opengl-driver/lib";
  };
};
```

**FFmpeg NVENC:**
```bash
ffmpeg -i input.mp4 -c:v hevc_nvenc -preset p4 -rc vbr -cq 25 output.mp4
```

---

**Last Updated**: 2025-11-24
**Hardware**: NVIDIA Quadro P1000 (4GB VRAM)
**Driver**: 580.95.05 (CUDA 13.0)
**System**: NixOS hwc-server
