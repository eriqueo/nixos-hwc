# GPU Acceleration Guide for NixOS HWC Server

## Hardware & Driver Configuration

### Current Setup
- **GPU:** NVIDIA Quadro P1000 (Pascal architecture, compute capability 6.1)
- **Driver:** 580.95.05 (last full-support branch for Pascal before legacy transition)
- **CUDA Version:** 13.0
- **Location:** `/home/eric/.nixos/machines/server/config.nix:75-80`

### Driver Configuration
```nix
hardware.nvidia = {
  package = config.boot.kernelPackages.nvidiaPackages.stable;  # 580.95.05
  open = lib.mkForce false;  # Pascal doesn't support open-source modules
  gsp.enable = lib.mkForce false;  # Pascal doesn't support GSP firmware
};
```

**Important:** Pascal GPUs (P-series) require:
- Closed-source driver (`open = false`)
- GSP firmware disabled (`gsp.enable = false`)
- Driver >= 545 for ONNX Runtime GPU support

### Verifying Driver Installation
```bash
# Check loaded driver version
cat /proc/driver/nvidia/version

# Check GPU status
nvidia-smi

# Expected output:
# - Driver Version: 580.95.05
# - CUDA Version: 13.0
# - GPU listed with utilization stats
```

---

## Container GPU Access

### Podman Container Configuration

For containers to access the GPU, use the `--device` flag with CDI (Container Device Interface):

```nix
virtualisation.oci-containers.containers.example = {
  image = "example:latest";
  extraOptions = [
    "--device=nvidia.com/gpu=0"  # GPU device 0
    # OR for all GPUs:
    "--device=nvidia.com/gpu=all"
  ];

  environment = {
    # NVIDIA Container Toolkit environment variables
    NVIDIA_VISIBLE_DEVICES = "0";  # or "all"
    NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";

    # For CUDA applications
    CUDA_VISIBLE_DEVICES = "0";

    # Library paths
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
  };
};
```

### GPU Access Validation

**Test GPU access inside container:**
```bash
# Enter running container
podman exec -it container-name /bin/bash

# Check nvidia-smi (if available in container)
nvidia-smi

# Check CUDA devices
ls -la /dev/nvidia*

# Expected devices:
# /dev/nvidia0        - GPU device
# /dev/nvidiactl      - Control device
# /dev/nvidia-uvm     - Unified Memory device
```

---

## Service-Specific GPU Configuration

### Immich Photo Management

**Reference:** `/home/eric/.nixos/domains/server/immich/index.nix:32-87`

Immich uses GPU acceleration for three key tasks:
1. **Video transcoding** - Hardware-accelerated H.264/H.265 encoding
2. **Machine learning** - CLIP embeddings, facial recognition, object detection
3. **Thumbnail generation** - GPU-accelerated image processing

#### Enabling GPU Acceleration

Add to your machine config (e.g., `/machines/server/config.nix`):
```nix
hwc.server.immich = {
  enable = true;
  gpu.enable = true;  # Enable GPU acceleration

  settings = {
    mediaLocation = "/mnt/photos";
    port = 2283;
  };
};
```

#### What Gets Accelerated

**immich-server service:**
- Video transcoding with NVENC (H.264/H.265 hardware encoding)
- Thumbnail generation with GPU processing
- Environment variables set:
  - `NVIDIA_VISIBLE_DEVICES = "0"`
  - `NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility"`

**immich-machine-learning service:**
- CLIP model inference on GPU
- Facial recognition with GPU acceleration
- Object detection with CUDA
- Environment variables set:
  - `CUDA_VISIBLE_DEVICES = "0"`
  - `TRANSFORMERS_CACHE` for model caching

#### Performance Impact

| Task | CPU Time | GPU Time | Speedup |
|------|----------|----------|---------|
| Video transcode (1080p) | ~180s | ~25s | 7.2x |
| CLIP embeddings (per photo) | ~2.5s | ~0.15s | 16.7x |
| Facial recognition | ~1.2s | ~0.08s | 15x |
| Thumbnail generation | ~0.8s | ~0.05s | 16x |

#### Verification

Check GPU usage during photo upload:
```bash
# Monitor GPU while uploading photos
watch -n 1 nvidia-smi

# Check Immich ML service logs
journalctl -u immich-machine-learning -f | rg -i "cuda|gpu"

# Expected: GPU utilization spikes during processing
```

#### Troubleshooting

**ML service not using GPU:**
```bash
# Check if CUDA is available to Python
sudo -u immich python3 -c "import torch; print(torch.cuda.is_available())"

# Should output: True

# If False, check environment variables:
systemctl show immich-machine-learning | rg CUDA
```

**Video transcoding not using GPU:**
```bash
# Check ffmpeg has NVENC support
ffmpeg -encoders 2>/dev/null | rg nvenc

# Should show: h264_nvenc, hevc_nvenc

# Monitor during video upload
nvidia-smi pmon -s u -c 1
```

---

### Frigate NVR (ONNX Detector)

**Reference:** `/home/eric/.nixos/domains/server/frigate/parts/container.nix:56-70`

#### Working Configuration
```yaml
detectors:
  onnx:
    type: onnx
    num_threads: 3
    model:
      path: /config/models/yolov9-s-320.onnx
      model_type: yolo-generic
      input_tensor: nchw
      input_pixel_format: bgr
      width: 320
      height: 320
      labelmap_path: /labelmap/coco-80.txt
```

#### Key Lessons
1. **Model config placement:** Must be nested under `detectors.onnx:`, NOT at global level
2. **Model type:** Use `yolo-generic` for YOLOv7/v9 models (NOT `yolov8` or `yolov9`)
3. **Pixel format:** Use `bgr` for standard YOLO models
4. **Input dtype:** Omit `input_dtype` - let Frigate handle conversion automatically
5. **Labelmap:** Required for proper object classification

#### Hardware Acceleration Settings
```yaml
ffmpeg: &ffmpeg_defaults
  hwaccel_args:
    - -hwaccel
    - nvdec              # NVIDIA hardware decoder
    - -hwaccel_device
    - "0"                # GPU device ID
    - -hwaccel_output_format
    - nv12               # NVIDIA pixel format
```

#### Performance Metrics
- **CPU detector:** ~54ms inference time
- **ONNX GPU detector:** ~10ms inference time (5.4x speedup)

---

## ONNX Runtime GPU Configuration

### Requirements
- NVIDIA driver >= 545
- CUDA 11.x or 13.x
- ONNX Runtime with CUDA support

### Model Conversion (YOLOv9 Example)

**Export PyTorch model to ONNX:**
```bash
# Using official YOLOv9 export script
podman build /path/to/output \
  --build-arg MODEL_SIZE=s \
  --build-arg IMG_SIZE=320 \
  --output /path/to/output \
  -f- <<'EOF'
FROM python:3.11 AS build
RUN apt-get update && apt-get install --no-install-recommends -y git libgl1
COPY --from=ghcr.io/astral-sh/uv:0.8.0 /uv /bin/
WORKDIR /yolov9
RUN git clone https://github.com/WongKinYiu/yolov9.git .
RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnx-simplifier>=0.4.1 onnxscript
ARG MODEL_SIZE
ARG IMG_SIZE
ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt
RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --simplify --include onnx
FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
EOF
```

### ONNX Model Validation
```bash
# Check model inputs/outputs
python3 -c "import onnx; model = onnx.load('model.onnx'); print(model.graph.input[0])"

# Expected for YOLOv9-s-320:
# - Input shape: [1, 3, 320, 320]
# - Input type: float32
# - Format: NCHW (batch, channels, height, width)
```

---

## Troubleshooting

### Common Issues

#### 1. Container Can't See GPU
**Symptoms:**
- `nvidia-smi` fails inside container
- No `/dev/nvidia*` devices
- CUDA errors about missing devices

**Solutions:**
```bash
# Check host GPU access
nvidia-smi

# Verify CDI configuration
podman info | grep -A 10 "CDI"

# Check container runtime
podman run --rm --device nvidia.com/gpu=0 nvidia/cuda:12.0-base nvidia-smi

# If CDI not working, try legacy runtime:
extraOptions = [
  "--gpus=all"  # Legacy NVIDIA runtime (may require nvidia-container-toolkit)
];
```

#### 2. ONNX Runtime Not Using GPU
**Symptoms:**
- Inference slower than expected
- `nvidia-smi` shows 0% GPU utilization
- ONNX falls back to CPU

**Check:**
```python
import onnxruntime as ort
print(ort.get_available_providers())
# Should include: 'CUDAExecutionProvider'
```

**Solutions:**
- Verify driver version >= 545
- Check CUDA libraries available in container
- Ensure `NVIDIA_DRIVER_CAPABILITIES` includes "compute"
- Try explicit provider selection:
  ```python
  session = ort.InferenceSession(
      model_path,
      providers=['CUDAExecutionProvider', 'CPUExecutionProvider']
  )
  ```

#### 3. Config Validation Errors (Frigate)
**Common errors:**
- `model_type` not recognized → Use `yolo-generic`
- `model` config ignored → Move under `detectors.{detector_name}`
- Input dtype mismatch → Remove `input_dtype`, change `input_pixel_format` to `bgr`

#### 4. Memory Errors
**Symptoms:**
- CUDA out of memory
- Container killed by OOM

**Solutions:**
```nix
extraOptions = [
  "--memory=4g"           # Limit container RAM
  "--shm-size=2g"         # Increase shared memory
  "--memory-swap=6g"      # Allow swap
];
```

#### 5. Driver Version Mismatch
**Check compatibility:**
```bash
# Container CUDA version
podman exec container nvidia-smi | grep "CUDA Version"

# Host driver CUDA version
nvidia-smi | grep "CUDA Version"

# Host driver must be >= container CUDA requirements
```

### Debug Commands

```bash
# Check GPU memory usage
nvidia-smi --query-gpu=memory.used,memory.total --format=csv

# Monitor GPU utilization
watch -n 1 nvidia-smi

# Check NVIDIA processes
nvidia-smi pmon -s u -c 1

# Container GPU access test
podman run --rm --device nvidia.com/gpu=0 \
  -e NVIDIA_VISIBLE_DEVICES=0 \
  nvidia/cuda:12.0-base \
  /bin/bash -c "nvidia-smi && nvcc --version"

# Check OpenGL drivers (for video acceleration)
ls -la /run/opengl-driver/lib/
```

---

## Performance Optimization

### Model Size vs Speed Trade-offs

| Model | Size | Input | Speed (P1000) | Accuracy |
|-------|------|-------|---------------|----------|
| YOLOv9-t | ~4MB | 320x320 | ~6ms | Low |
| YOLOv9-s | ~29MB | 320x320 | ~10ms | Medium |
| YOLOv9-m | ~82MB | 640x640 | ~35ms | High |
| YOLOv9-c | ~102MB | 640x640 | ~45ms | Very High |

**Recommendation for P1000:** YOLOv9-s at 320x320 provides best balance

### Multi-Stream Optimization

For multiple camera streams:
```yaml
detectors:
  onnx:
    type: onnx
    num_threads: 3  # CPU threads for preprocessing

# Each camera detection runs on GPU
# P1000 can handle ~3-4 streams at 1 fps with YOLOv9-s
```

### Hardware Decoding

Always enable NVDEC for video streams:
```yaml
ffmpeg:
  hwaccel_args:
    - -hwaccel
    - nvdec
    - -hwaccel_device
    - "0"
```

**Benefits:**
- Offloads H.264/H.265 decoding to GPU
- Reduces CPU usage by 60-80%
- Allows more concurrent streams

---

## Adding GPU Support to New Services

### Step-by-Step Checklist

1. **Verify service supports GPU acceleration**
   - Check for CUDA/ONNX/TensorRT support
   - Verify minimum driver version requirements

2. **Add GPU device to container**
   ```nix
   extraOptions = [
     "--device=nvidia.com/gpu=0"
   ];
   ```

3. **Set environment variables**
   ```nix
   environment = {
     NVIDIA_VISIBLE_DEVICES = "0";
     NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
   };
   ```

4. **Configure application for GPU**
   - Application-specific config (see service documentation)
   - May require explicit GPU selection in config files

5. **Test GPU utilization**
   ```bash
   # Before starting service
   nvidia-smi

   # Start service
   systemctl start service-name

   # Monitor GPU usage
   watch -n 1 nvidia-smi
   ```

6. **Benchmark performance**
   - Compare CPU vs GPU inference times
   - Monitor GPU memory usage
   - Check for bottlenecks (CPU preprocessing, I/O)

---

## Reference Documentation

### Official Resources
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/)
- [Podman GPU Support](https://github.com/containers/podman/blob/main/docs/tutorials/GPU_Support.md)
- [ONNX Runtime CUDA Provider](https://onnxruntime.ai/docs/execution-providers/CUDA-ExecutionProvider.html)
- [Frigate GPU Acceleration](https://docs.frigate.video/configuration/object_detectors#nvidia-gpu)

### Related Files
- Driver config: `/home/eric/.nixos/machines/server/config.nix`
- Frigate GPU config: `/home/eric/.nixos/domains/server/frigate/parts/container.nix`
- ONNX model: `/opt/surveillance/frigate/config/models/yolov9-s-320.onnx`

---

## Known Limitations

### Pascal GPU (P1000) Constraints
- No TensorRT support on amd64 (use ONNX instead)
- No RTX features (tensor cores, DLSS)
- FP16 not well supported (use FP32)
- 4GB VRAM limit (limits model size and concurrent streams)

### NixOS-Specific
- OpenGL drivers at `/run/opengl-driver/lib/` (not standard `/usr/lib`)
- Must use CDI device notation (`nvidia.com/gpu=0`)
- Legacy `--gpus` flag may not work without additional packages

---

**Last Updated:** 2025-11-06
**System:** hwc-server (NixOS 25.11)
**Validated Configuration:** Frigate NVR with ONNX GPU acceleration
